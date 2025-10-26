require_relative './theorem/harness'

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
