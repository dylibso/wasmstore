#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdint.h>
#include <stdlib.h>

void wasmstore_error_free(char *s);
char *wasmstore_verify_string(const uint8_t *, size_t);
char *wasmstore_verify_file(const char *);

value Val_some(value v) {
  CAMLparam1(v);
  CAMLlocal1(some);
  some = caml_alloc_small(1, 0);
  Store_field(some, 0, v);
  CAMLreturn(some);
}

value wasm_verify_string(value s) {
  CAMLparam1(s);
  CAMLlocal2(e, x);
  x = Val_unit;
  char *err = wasmstore_verify_string(String_val(s), caml_string_length(s));
  if (err != NULL) {
    e = caml_copy_string(err);
    wasmstore_error_free(err);
    x = Val_some(e);
  }
  CAMLreturn(x);
}

value wasm_verify_file(value s) {
  CAMLparam1(s);
  CAMLlocal2(e, x);
  x = Val_unit;
  char *err = wasmstore_verify_file(String_val(s));
  if (err != NULL) {
    e = caml_copy_string(err);
    wasmstore_error_free(err);
    x = Val_some(e);
  }
  CAMLreturn(x);
}
