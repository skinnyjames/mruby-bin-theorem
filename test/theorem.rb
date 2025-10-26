

module Fixture
  include Theorem::Control::Hypothesis
end

module Tests
  module Harness
    include Theorem::Control::Harness

    load_tests do |options|
      puts options
      directory = options[:directory] || '.'

      Dir.glob("#{directory}/**/*.rb").each do |file|
        eval File.read(file)
      end

      # registry.each do |test_class|
      #   test_class.tests.reject! do |test|
      #     a = test.metadata[:tags]&.intersection(options[:exclude])&.any?
      #   end
      # end

      filtered_registry(options[:meta])
    end
  end
  
  module World
    include Theorem::Control::Hypothesis
    include Theorem::StdoutReporter
    include Harness
  end
end

class Base
  include Tests::World
  include Matchers
end
