module Theorem
  module Control
    # error class
    class CompletedTest
      attr_reader :test, :duration
      attr_accessor :error, :notary

      def initialize(test, error = nil, notary:, duration: nil)
        @test = test
        @error = error
        @notary = notary
        @duration = duration
      end

      def full_name
        test.full_name
      end

      def name
        test.name
      end

      def failed?
        !@error.nil?
      end
    end
  end
end

module Theorem
  module Control
    # test object for around hooks
    class FlaskTest
      def initialize(test, ctx)
        @test = test
        @ctx = ctx
      end

      def name
        @test.name
      end

      def run!
        @test.run!(@ctx)
      end
    end

    # single use container
    class Flask
      attr_reader :state

      def initialize
        @state = nil
      end

      def run!(test, ctx, flask_test: FlaskTest.new(test, ctx))
        ctx.instance_exec flask_test, &@state
        nil
      rescue Exception => error
        Theorem.handle_exception(error)

        error
      end

      def empty?
        @state.nil?
      end

      def prepare(&block)
        @state = block
      end
    end

    # reusable container
    class Beaker
      def initialize
        @state = []
      end

      def clone
        @state.map!(&:clone)
        self
      end

      def reverse_run!(ctx, **params)
        ctx.instance_exec @state.reverse, ctx, params do |state, ctx, params|
          state.each do |b|
            ctx.instance_exec **params, &b
          end
        end
      end

      def run!(ctx)
        ctx.instance_exec @state, ctx do |state, ctx|
          state.each do |b|
            ctx.instance_eval &b
          end
        end
      end

      def empty?
        @state.empty?
      end

      def concat(beaker)
        @state.concat beaker.instance_variable_get('@state')
      end

      def prepare(&block)
        @state << block
      end
    end
  end
end

# frozen_string_literal: true

module Theorem
  module Control
    module Registry
      # beaker
      def registry
        @registry ||= []
      end

      def filtered_registry(options)
        registry.each do |test_class|
          if options[:include]&.any?
            test_class.tests.select! do |test|
              test.metadata[:tags]&.intersection(options[:include])&.any?
            end
          end

          next unless options[:exclude]&.any?

          test_class.tests.reject! do |test|
            test.metadata[:tags]&.intersection(options[:exclude])&.any?
          end
        end
      end

      def add_to_registry(klass)
        registry << klass
      end

      %i[suite_started test_started test_finished suite_finished].each do |method|
        define_method method do |&block|
          instance_variable_set("@#{method}_subscribers", []) unless instance_variable_get("@#{method}_subscribers")
          instance_variable_get("@#{method}_subscribers").append(block)
        end

        define_method "#{method}_subscribers" do
          return [] unless instance_variable_get("@#{method}_subscribers")

          instance_variable_get("@#{method}_subscribers")
        end
      end
    end
  end
end
module Theorem
  module Control
    class Notation
      def initialize(state = {})
        @state = state
      end

      def write(key, value)
        @state[key] = value
      end

      def read(key)
        @state[key]
      end

      def dump
        @state
      end

      def merge(notary)
        Notation.new(@state.merge(notary.dump))
      end

      def edit(key, &block)
        data = read(key)
        data = block.call(data)
        write(key, data)
      end
    end
  end
end

module Theorem
  module Control
    # test new
    class Test
      def initialize(name, namespace, arguments: {}, **metadata, &block)
        @name = name
        @namespace = namespace
        @block = block
        @arguments = arguments
        @metadata = metadata
        @notary = Notation.new
      end

      attr_reader :block, :name, :arguments, :namespace, :metadata, :notary

      def full_name
        "#{namespace} #{name}"
      end

      def notate(&block)
        block.call(notary)
      end

      def run!(ctx)
        ctx.instance_exec self, **arguments, &block
      end
    end

    # module
    module ClassMethods
      def inherited(klass)
        klass.extend ClassMethods
        klass.include(control)
        klass.instance_exec self do |me|
          @parent_before_all ||= []
          @before_all.concat me.before_all_beaker.clone

          @parent_before_each ||= []
          @before_each.concat me.before_each_beaker.clone

          @parent_after_each ||= []
          @after_each.concat me.after_each_beaker.clone

          @parent_after_all ||= []
          @after_all.concat me.after_all_beaker.clone
        end
        super
      end

      def before_all(&block)
        @before_all.prepare(&block)
      end

      def around(&block)
        @around.prepare(&block)
      end

      def before_each(&block)
        @before_each.prepare(&block)
      end

      def after_each(&block)
        @after_each.prepare(&block)
      end

      def after_all(&block)
        @after_all.prepare(&block)
      end

      def experiments(klass, **opts, &block)
        obj = Class.new
        obj.include(control)
        obj.instance_eval &block if block
        obj.instance_exec self, klass, opts do |consumer, experiment_klass, params|
          @tests.concat experiment_klass.tests(_experiment_namespace: consumer.to_s, arguments: params)
        end
      end

      def tests
        @tests
      end

      def before_all_beaker
        @before_all
      end

      def before_each_beaker
        @before_each
      end

      def after_each_beaker
        @after_each
      end

      def after_all_beaker
        @after_all
      end

      def test(name, **hargs, &block)
        @tests << Test.new(name, to_s, **hargs, &block)
      end

      def run!
        return [] if @tests.empty?

        test_case = new

        # run before all beakers to create state in test case
        before_failures = run_before_all_beakers(test_case)

        if before_failures.any?
          before_failures.each do |failure|
            publish_test_completion(failure)
          end
          return before_failures
        end

        # duplicate the before_all arrangement for the after all hook
        duplicate_test_case = test_case.clone

        results = []
        @tests.each do |test|
          test_start = clock_time

          publish_test_start(test)

          error ||= run_before_each_beakers(test_case)

          before_test_case = test_case.clone
          error ||= run_test(test, before_test_case)
          error ||= run_after_each_beakers(before_test_case, error: error)

          notary = test_case.notary.merge(test.notary)

          duration = clock_time - test_start

          completed_test = CompletedTest.new(test, error, duration: duration, notary: notary.dump)

          # publish_early if there are no after_all beakers
          publish_test_completion(completed_test) if @after_all.empty?

          results << completed_test
        end

        after_failures = run_after_all_beakers(results, duplicate_test_case)

        if after_failures.any?
          after_failures.each do |failure|
            publish_test_completion(failure)
          end
          return after_failures
        end

        results.each do |completed_test|
          # merge any after_all notations
          completed_test.notary.merge!(duplicate_test_case.notary.dump)
          publish_test_completion(completed_test) unless @after_all.empty?
        end

        results
      end

      private

      def clock_time
        Theorem.monotonic
      end

      def run_test(test, test_case)
        if @around.empty?
          begin
            test.run!(test_case)
            nil
          rescue Exception => error
            Theorem.handle_exception(error)

            error
          end
        else
          @around.run!(test, test_case)
        end
      end

      def run_after_all_beakers(results, test_case)
        @after_all.reverse_run!(test_case)

        []
      rescue Exception => error
        Theorem.handle_exception(error)

        results.each do |test|
          test.error = error
          test.notary = test_case.notary
        end

        results
      end

      def run_after_each_beakers(test_case, **params)
        @after_each.reverse_run!(test_case, **params)
        nil
      rescue Exception => error
        Theorem.handle_exception(error)

        error
      end

      def run_before_each_beakers(test_case)
        @before_each.run!(test_case)
        nil
      rescue Exception => error
        Theorem.handle_exception(error)

        error
      end

      def run_before_all_beakers(test_case)
        @before_all.run!(test_case)
        []
      rescue Exception => error
        Theorem.handle_exception(error)

        @tests.map do |test|
          CompletedTest.new(test, error, notary: test_case.notary)
        end
      end

      def publish_test_completion(completed_test)
        control.test_finished_subscribers.each do |subscriber|
          subscriber.call(completed_test)
        end
      end

      def publish_test_start(test)
        control.test_started_subscribers.each do |subscriber|
          subscriber.call(test)
        end
      end
    end
  end
end
# frozen_string_literal: true

module Theorem
  module Control
    # compatibility with let in rspec
    module Let
      def let(name, &block)
        setup_let(name, &block)
        instance_exec @let_registry do |registry|
          @before_each.prepare do
            define_singleton_method name do
              raise "can't find #{name}" unless registry[:let][name]

              registry[:let][name][:value] ||= instance_exec &registry[:let][name][:block]
            end
          end

          @after_each.prepare do
            registry[:let][name][:value] = nil
          end
        end
      end
      alias_method :each_with, :let

      def let_it_be(name, &block)
        setup_let(name, :let_it_be, &block)
        instance_exec @let_registry do |registry|
          @before_all.prepare do
            define_singleton_method name do
              raise "can't find #{name}" unless registry[:let_it_be][name]

              registry[:let_it_be][name][:value] ||= instance_exec &registry[:let_it_be][name][:block]
            end
          end
          @after_all.prepare do
            registry[:let_it_be][name][:value] = nil
          end
        end
      end
      alias_method :all_with, :let_it_be

      private

      def setup_let(name, type=:let, &block)
        @let_registry ||= {}
        @let_registry[type] ||= {}
        @let_registry[type][name] = { block: block, value: nil }

        define_singleton_method name do
          raise "can't find #{name}" unless @let_registry[type][name]

          @let_registry[type][name][:value] ||= @let_registry[type][name][:block].call
        end
      end
    end
  end
end

module Theorem
  module Control
    # control hypothesis
    module Hypothesis
      def self.included(mod)
        mod.define_singleton_method(:included) do |klass|
          klass.define_singleton_method(:control) do
            mod
          end

          klass.attr_reader :notary

          klass.define_method :initialize do
            @notary = Notation.new
          end

          klass.define_method :notate do |&block|
            block.call(@notary)
          end

          klass.instance_eval do
            @before_all ||= Beaker.new
            @before_each ||= Beaker.new
            @after_all ||= Beaker.new
            @after_each ||= Beaker.new
            @around = Flask.new
            @tests = []
            @completed_tests = []
            @self = new
          end
          
          klass.extend Let
          klass.extend ClassMethods

          mod.add_to_registry(klass)
        end

        mod.const_set(:Beaker, Beaker) unless mod.const_defined?(:Beaker)
        mod.const_set(:Test, Test) unless mod.const_defined?(:Test)
        mod.const_set(:CompletedTest, CompletedTest) unless mod.const_defined?(:CompletedTest)
        mod.extend(Registry)

        super
      end
    end
  end
end



module Theorem
  module Control
    # control harness
    module Harness
      def self.included(mod)
        mod.extend(ClassMethods)
        mod.define_singleton_method :included do |inner|
          inner.define_singleton_method :run! do |options: {}|
            tests = inner.instance_exec options, &mod.test_loader

            inner.suite_started_subscribers.each do |subscriber|
              subscriber.call tests.map(&:tests).flatten.map do |test|
                { name: test.name, metadata: test.metadata }
              end
            end

            starting = Theorem.monotonic
            results = inner.instance_exec tests, options, &mod.run_loader
            ending = Theorem.monotonic

            duration = ending - starting

            inner.suite_finished_subscribers.each do |subscriber|
              subscriber.call(results, duration)
            end

            inner.instance_exec results, &mod.run_exit
          end
        end
      end

      # harness helpers
      module ClassMethods

        def load_tests(&block)
          @on_load_tests = block
        end

        def on_exit(&block)
          @on_exit = block
        end

        def on_run(&block)
          @on_run = block
        end

        def run_exit
          @on_exit || default_exit
        end

        def run_loader
          @on_run || default_runner
        end

        def test_loader
          @on_load_tests || default_loader
        end

        private

        def default_exit
          lambda do |results|
            return results.any?(&:failed?) ? 1 : 0
          end
        end

        def default_loader
          lambda do |options|
            directory = options[:directory] || '.'

            # ExtendedDir.require_all("./#{directory}")

            registry
          end
        end

        def default_runner
          lambda do |tests, options|
            tests.each_with_object([]) do |test, memo|
              memo.concat test.run!
            end
          end
        end
      end
    end
  end
end


# harness
module Theorem
  # default test harness
  module Harness
    include Theorem::Control::Harness

    load_tests do |options|
      directory = options[:directory] || '.'

      Dir.glob("#{directory}/**/*.rb").each do |file|
        eval File.read(file)
      end

      filtered_registry(options[:meta])
    end
  end
end

module Theorem
  # shared examples
  class Experiment
    class << self
      def test(name, &block)
        @tests ||= []
        @tests << { name: name, block: block }
      end

      def tests(_experiment_namespace: to_s, **opts)
        @tests.map do |hash|
          Control::Test.new(hash[:name], _experiment_namespace, **opts, &hash[:block])
        end
      end
    end
  end
end

module Theorem
  module Control
    # control harness
    module Harness
      def self.included(mod)
        mod.extend(ClassMethods)
        mod.define_singleton_method :included do |inner|
          inner.define_singleton_method :run! do |options: {}|
            tests = inner.instance_exec options, &mod.test_loader

            inner.suite_started_subscribers.each do |subscriber|
              subscriber.call tests.map(&:tests).flatten.map do |test|
                { name: test.name, metadata: test.metadata }
              end
            end

            starting = Theorem.monotonic
            results = inner.instance_exec tests, options, &mod.run_loader
            ending = Theorem.monotonic

            duration = ending - starting

            inner.suite_finished_subscribers.each do |subscriber|
              subscriber.call(results, duration)
            end

            inner.instance_exec results, &mod.run_exit
          end
        end
      end

      # harness helpers
      module ClassMethods

        def load_tests(&block)
          @on_load_tests = block
        end

        def on_exit(&block)
          @on_exit = block
        end

        def on_run(&block)
          @on_run = block
        end

        def run_exit
          @on_exit || default_exit
        end

        def run_loader
          @on_run || default_runner
        end

        def test_loader
          @on_load_tests || default_loader
        end

        private

        def default_exit
          lambda do |results|
            return results.any?(&:failed?) ? 1 : 0
          end
        end

        def default_loader
          lambda do |options|
            directory = options[:directory] || '.'

            # ExtendedDir.require_all("./#{directory}")

            registry
          end
        end

        def default_runner
          lambda do |tests, options|
            tests.each_with_object([]) do |test, memo|
              memo.concat test.run!
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Theorem
  module Control
    # reporter mixin
    module Reporter
      def self.extended(mod)
        mod.extend(mod)
        mod.define_singleton_method :included do |root|
          subscriptions = mod.subscriptions || []
          subscriptions.each do |subscription, handler|
            mod.instance_exec root, subscription, handler do |root, sub, handle|
              root.send(sub, &handle)
            end
          end
        end
      end

      def subscribe(name, &block)
        @subscriptions ||= {}
        @subscriptions[name] = block
      end

      def subscriptions
        @subscriptions
      end
    end
  end
end

module Theorem
  class ::String
    # colorization
    def colorize(color_code)
      "\e[#{color_code}m#{self}\e[0m"
    end

    def red
      colorize(31)
    end

    def green
      colorize(32)
    end

    def yellow
      colorize(33)
    end

    def blue
      colorize(34)
    end

    def pink
      colorize(35)
    end

    def light_blue
      colorize(36)
    end
  end

  # Default Stdout reporter
  module StdoutReporter
    extend Control::Reporter

    subscribe :test_finished do |test|
      print test.failed? ? 'x'.red : '.'.green
    end

    subscribe :suite_finished do |results, duration|
      puts "\n"
      report_summary(results)

      failed_tests = results.select(&:failed?)

      report_failures(failed_tests)

      puts "\nTotal time: #{duration} seconds"
      puts "Total tests: #{results.size} (#{failed_tests.size} failed)\n"
    end

    def inflate_percentiles(tests)
      sorted = tests.reject { |t| t.duration.nil? }.sort_by(&:duration)
      tests.each_with_object([]) do |test, arr|
        _, below = sorted.partition do |duration_test|
          if test.duration.nil?
            true
          else
            test.duration >= duration_test.duration
          end
        end
        hash = {}
        hash[:percentile] = (below.size.to_f / (sorted.size.to_f + 1)) * 100
        hash[:test] = test
        arr << hash
      end
    end

    def report_summary(tests)
      inflated = inflate_percentiles(tests)

      top_20 = 80 / (100.0 * (tests.size + 1).to_f)
      lowest_20 = 20 / (100.0 * (tests.size + 1).to_f)

      inflated.each do |test|
        icon = test[:test].failed? ? '❌'.red : '✓'.green
        puts "#{icon} #{test[:test].full_name.blue} : #{duration(test)}"
      end
    end

    def duration(test)
      return 'Not run' if test[:test].duration.nil?

      str = "#{format('%<num>0.10f', num: test[:test].duration)} seconds"
      rank = test[:percentile]
      if rank < 10
        str.red
      elsif rank > 90
        str.green
      elsif rank < 30
        str.yellow
      else
        str
      end
    end

    def report_failures(tests)
      tests.each do |failure|
        puts "\n\nFailure in #{failure.full_name}\nError: #{failure.error.message.to_s.red}\nBacktrace:\n------\n#{failure.error.backtrace.map(&:red).join("\n")}"
      end
    end
  end
end
module Matchers
  class Expect
    attr_reader :actual

    def initialize(actual)
      @actual = actual
    end

    def to(matcher, error = matcher.error(actual))
      raise StandardError.new(error) unless matcher.match(@actual)
    end

    def not_to(matcher, error = "Assertion failed for #{matcher.class}")
      raise StandardError.new(error) unless !matcher.match(@actual)
    end
  end

  class ProcExpect
    def initialize(proc)
      @proc = proc
    end

    def to(matcher, error = "Assertion failed for #{matcher.class}")
      raise StandardError.new(error) unless matcher.match(@actual)
    end

    def not_to(matcher, error = "Assertion failed for #{matcher.class}")
      raise StandardError.new(error) unless !matcher.match(@actual)
    end
  end

  class MatchBase
    def initialize(expected)
      @expected = expected
    end

    def match(actual)
      raise StandardError.new("Need to define a matcher for #{self.class}")
    end
  end

  class Be < MatchBase
    def match(actual)
      @expected.object_id == actual.object_id
    end

    def error(actual)
      "#{actual.class}.object_id(#{actual.object_id}) does not equal #{@expected.class}.object_id(#{@expected.object_id})"
    end
  end

  class Match < MatchBase
    def match(actual)
      @expected =~ actual
    end

    def error(actual)
      "#{actual.inspect} does not match #{@expected.inspect}"
    end
  end

  class Eql < MatchBase
    def match(actual)
      @expected == actual
    end

    def error(actual)
      "#{actual.inspect} does not equal #{@expected.inspect}"
    end
  end

  class Include < MatchBase
    def match(actual)
      case @expected
      when Array
        (@expected - actual).size.zero?
      else
        actual.include?(@expected)
      end
    end

    def error(actual)
      "#{actual.inspect} does not include #{@expected.inspect}"
    end
  end

  class ErrorBlock < MatchBase
    def initialize(ctx, block)
      @ctx = ctx
      @expected = block
    end
    
    def match(actual)
      begin
        actual.call

        return false
      rescue StandardError => ex
        return @ctx.instance_exec(ex, &@expected) unless @expected.nil?
      end
    end
  end

  def aggregate_failures(&block)
    errors = []
    begin
      self.instance_eval(&block)
    rescue StandardError => ex
      errors << ex
    end

    unless errors.empty?
      raise StandardError.new("Aggregate failed: #{errors.join("\n")}")
    end
  end

  def expect(actual = nil,  &block)
    unless block.nil?
      Expect.new(block.to_proc)
    else
      Expect.new(actual)
    end
  end

  def match(expected)
    Match.new(expected)
  end

  def eql(expected)
    Eql.new(expected)
  end

  def be(expected)
    Be.new(expected)
  end

  def include(expected)
    Include.new(expected)
  end

  def raise_error(&block)
    ErrorBlock.new(self, block)
  end
end

module Theorem
  def self.custom_exceptions
    errors = []
    errors
  end

  def self.handle_exception(error)
    unless error.is_a?(StandardError) || custom_exceptions.include?(error.class)
      raise error
    end
  end

  # needs mruby-require
  def self.run!(options)
    modstr = options.fetch(:module, "Theorem::Hypothesis")
    harnstr = options.fetch(:harness, nil)

    mod = Object.const_get(modstr)

    if modstr == "Theorem::Hypothesis" && options[:publishers].empty?
      mod.include Theorem::StdoutReporter
    end

    if harnstr
      harness = Object.const_get(harnstr)
      mod.include harness
    end
  
    options[:publishers].each do |publisher|
      pub = Object.const_get(publisher)
      mod.include pub
    end

    mod.run!(options: options)
  end


  module Hypothesis
    include Theorem::Control::Hypothesis
    include Harness
    include Matchers
  end
end