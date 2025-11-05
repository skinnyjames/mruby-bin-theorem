MRuby::Gem::Specification.new('mruby-bin-theorem') do |spec|
  spec.license = 'MIT'
  spec.author  = 'zero stars'
  spec.summary = 'extensible test runner'
  spec.version = '0.2.0'
  spec.add_dependency "mruby-class-ext"
  spec.add_dependency 'mruby-metaprog'
  spec.add_dependency 'mruby-file-stat'
  spec.add_dependency 'mruby-dir'
  spec.add_dependency 'mruby-dir-glob'
  spec.add_dependency 'mruby-regexp-pcre'
  spec.bins = ["theorize"]
end