require "pathname"

class Resolver
  def self.write_to_file(path, filename)
    File.write(filename, new(path).code)
  end

  def initialize(file_path, document = File.read(file_path))
    @file_path = file_path
    @document = document
  end

  def code
    resolve_imports!

    @document
  end

  def resolve_imports!
    file_path_dir = File.dirname(@file_path)

    @document = @document.gsub(/(?:require_relative\s+["'](.*)["'])/) do |path|
      base_path = Pathname.new(@file_path)
      path = Pathname.new("#{path.gsub(/require_relative\s+["']/, "").chop}.rb")
      resolved_path = Pathname.new(base_path.dirname).join(path).to_s

      Resolver.new(resolved_path).code
    end
  end
end

Resolver.write_to_file("#{__dir__}/lib/theorem.rb", "#{__dir__}/mrblib/theorem.rb")

MRuby::Gem::Specification.new('mruby-bin-theorem') do |spec|
  spec.license = 'MIT'
  spec.author  = 'zero stars'
  spec.summary = 'extensible test runner'
  spec.version = '0.1.0'
  spec.add_dependency "mruby-class-ext"
  spec.add_dependency 'mruby-metaprog'
  spec.add_dependency 'mruby-file-stat'
  spec.add_dependency 'mruby-dir'
  spec.add_dependency 'mruby-dir-glob'
  spec.add_dependency 'mruby-regexp-pcre'
  spec.bins = ["theorize"]
end