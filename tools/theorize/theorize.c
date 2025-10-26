#include <mruby.h>
#include <mruby/hash.h>
#include <mruby/compile.h>
#include <mruby/array.h>

#include <stdio.h>
#include "../../src/mrb_theorem.h"
#define OPTPARSE_IMPLEMENTATION
#define OPTPARSE_API static
#include "optparse.h"

int main(int argc, char *argv[])
{
  mrb_state* mrb = mrb_open();
  mrb_mruby_bin_theorem_gem_init(mrb);
  struct RClass* theorem = mrb_module_get(mrb, "Theorem");

  char* directory = ".";
  char* require[5] = {NULL, NULL, NULL, NULL, NULL};
  char* harness = "Theorem::Harness";
  char* module = "Theorem::Hypothesis";
  char* publisher[5] = {NULL, NULL, NULL, NULL, NULL};
  char* include[5] = {NULL, NULL, NULL, NULL, NULL};
  char* exclude[5] = {NULL, NULL, NULL, NULL, NULL};

  int exclude_size = 0;
  int include_size = 0;
  int require_size = 0;
  int publisher_size = 0;

  struct optparse_long longopts[] = {
    {"require", 'r', OPTPARSE_OPTIONAL},
    {"harness", 'h', OPTPARSE_OPTIONAL},
    {"publisher", 'p', OPTPARSE_OPTIONAL},
    {"module", 'm', OPTPARSE_OPTIONAL},
    {"include", 'i', OPTPARSE_OPTIONAL},
    {"exclude", 'e', OPTPARSE_OPTIONAL},
    {0}
  };

  char* arg;
  int option;
  struct optparse options;
  optparse_init(&options, argv);
  while ((option = optparse_long(&options, longopts, NULL)) != -1) {
      switch (option) {
      case 'm':
        module = options.optarg;
        break;
      case 'i':
        if (include_size > 4)
        {
          fprintf(stderr, "Only 5 includes are supported for now\n");
          return 1;
        }
        include[include_size] = options.optarg;
        include_size++;
        break;
      case 'e':
        if (exclude_size > 4)
        {
          fprintf(stderr, "Only 5 excludes are supported for now\n");
          return 1;
        }
        exclude[exclude_size] = options.optarg;
        exclude_size++;
        break;
      case 'r':
        if (require_size > 4)
        {
          fprintf(stderr, "Only 5 requires are supported for now\n");
          return 1;
        }
        char* req = options.optarg;
        require[require_size] = req;
        require_size++;
        break;
      case 'h':
        harness = options.optarg;
        break;
      case 'p':
        if (publisher_size > 4)
        {
          fprintf(stderr, "Only 5 publishers are supported for now\n");
          return 1;
        }
        char* pub = options.optarg;
        publisher[publisher_size] = pub;
        publisher_size++;
        break;
      case '?':
          fprintf(stderr, "%s: %s\n", argv[0], options.errmsg);
          return 1;
      }
  }

  arg = optparse_arg(&options);
  if (!arg)
  {
    fprintf(stderr, "Need a directory to run tests against\n");
    return 1;
  } 

  directory = arg;

  for (int i=0; i<require_size; i++)
  {  
    FILE* file = fopen(require[i], "r");
    if (file == NULL)
    {
      fprintf(stderr, "File %s could not be loaded.\n", require[i]);
      return 1;
    }
    mrb_load_file(mrb, file);
    if (mrb->exc) {
      mrb_print_error(mrb);
      return 1;
    }
    fclose(file);
  }

  mrb_value hash = mrb_hash_new(mrb);
  mrb_hash_set(mrb, hash,  mrb_symbol_value(mrb_intern_lit(mrb, "directory")), mrb_str_new_cstr(mrb, directory));
  mrb_hash_set(mrb, hash,  mrb_symbol_value(mrb_intern_lit(mrb, "module")), mrb_str_new_cstr(mrb, module));
  mrb_hash_set(mrb, hash, mrb_symbol_value(mrb_intern_lit(mrb, "harness")), mrb_str_new_cstr(mrb, harness));

  // publishers
  mrb_value arr = mrb_ary_new(mrb);
  for (int i=0; i<publisher_size; i++)
  {
    mrb_ary_push(mrb, arr, mrb_str_new_cstr(mrb, publisher[i]));
  }
  mrb_hash_set(mrb, hash, mrb_symbol_value(mrb_intern_lit(mrb, "publishers")), arr);

  // meta
  mrb_value meta = mrb_hash_new(mrb);
  mrb_value includes = mrb_ary_new(mrb);
  mrb_value excludes = mrb_ary_new(mrb);

  // meta - includes
  for (int i=0; i<include_size; i++)
  {
    mrb_ary_push(mrb, includes, mrb_str_new_cstr(mrb, include[i]));
  }
  mrb_hash_set(mrb, meta, mrb_symbol_value(mrb_intern_lit(mrb, "include")), includes);

  // meta - excludes
  for (int i=0; i<exclude_size; i++)
  {
    mrb_ary_push(mrb, excludes, mrb_str_new_cstr(mrb, exclude[i]));
  }
  mrb_hash_set(mrb, meta, mrb_symbol_value(mrb_intern_lit(mrb, "exclude")), excludes);

  mrb_hash_set(mrb, hash, mrb_symbol_value(mrb_intern_lit(mrb, "meta")), meta);
  mrb_value ret = mrb_funcall(mrb, mrb_obj_value(theorem), "run!", 1, hash);
  if (mrb->exc)
  {
    mrb_print_error(mrb);
    return -1;
  }

  mrb_mruby_bin_theorem_gem_final(mrb);
  mrb_close(mrb);
  return mrb_int(mrb, ret);
}