
#include "mrb_theorem.h"
#include "monotonic.h"
#include <fcntl.h>

mrb_value mrb_mruby_bin_theorem_monotonic(mrb_state* mrb, mrb_value self)
{
  return mrb_float_value(mrb, monotonic_seconds());
}

mrb_value mrb_io_nonblock(mrb_state* mrb, mrb_value self)
{
  int fd = mrb_int(mrb, mrb_funcall(mrb, self, "fileno", 0, NULL));
  int flags = fcntl(fd, F_GETFL, 0);
  fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  return mrb_nil_value();
}

void mrb_mruby_bin_theorem_gem_init(mrb_state* mrb)
{
  struct RClass* ioclass = mrb_class_get(mrb, "IO");
  mrb_define_method(mrb, ioclass, "nonblock!", mrb_io_nonblock, MRB_ARGS_NONE());

  struct RClass* class = mrb_define_module(mrb, "Theorem");
  mrb_define_class_method(mrb, class, "monotonic", mrb_mruby_bin_theorem_monotonic, MRB_ARGS_NONE());
}

void mrb_mruby_bin_theorem_gem_final(mrb_state* mrb)
{
}