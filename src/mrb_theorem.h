#ifndef MRUBY_THEOREM_GEM_H
#define MRUBY_THEOREM_GEM_H

#include <mruby.h>
#include <mruby/compile.h>

mrb_value mrb_mruby_bin_theorem_monotonic(mrb_state* mrb, mrb_value self);
void mrb_mruby_bin_theorem_gem_init(mrb_state* mrb);
void mrb_mruby_bin_theorem_gem_final(mrb_state* mrb);

#endif