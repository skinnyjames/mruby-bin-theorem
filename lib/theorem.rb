require_relative './theorem/hypothesis'
require_relative './harness'
require_relative './experiment'
require_relative './theorem/harness'
require_relative './publishers/stdout_reporter'
require_relative './matchers'

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