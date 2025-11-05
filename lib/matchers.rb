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