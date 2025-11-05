
#include "mrb_theorem.h"
#include "monotonic.h"
#include <fcntl.h>

mrb_value mrb_mruby_bin_theorem_monotonic(mrb_state* mrb, mrb_value self)
{
  return mrb_float_value(mrb, monotonic_seconds());
}

void mrb_mruby_bin_theorem_gem_init(mrb_state* mrb)
{
  struct RClass* class = mrb_define_module(mrb, "Theorem");
  mrb_define_class_method(mrb, class, "monotonic", mrb_mruby_bin_theorem_monotonic, MRB_ARGS_NONE());
}

void mrb_mruby_bin_theorem_gem_final(mrb_state* mrb)
{
}