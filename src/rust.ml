open Ctypes

external _wasm_verify_file : unit -> unit = "wasm_verify_file"
external _wasm_verify_string : unit -> unit = "wasm_verify_string"
external _wasm_error_free : unit -> unit = "wasm_error_free"

let fn = Foreign.foreign

let wasm_verify_file =
  fn "wasm_verify_file" (ocaml_string @-> size_t @-> returning (ptr char))

let wasm_verify_string =
  fn "wasm_verify_string" (ocaml_string @-> size_t @-> returning (ptr char))

let wasm_error_free = fn "wasm_error_free" (ptr char @-> returning void)
let clone_string s = Bytes.unsafe_of_string s |> Bytes.to_string

let wrap res =
  if is_null res then Ok ()
  else
    let s = coerce (ptr char) string res in
    let out = clone_string s in
    let () = wasm_error_free res in
    Error (`Msg out)

let verify_file filename : (unit, [ `Msg of string ]) result =
  let len = Unsigned.Size_t.of_int (String.length filename) in
  wrap @@ wasm_verify_file (ocaml_string_start filename) len

let verify_string str : (unit, [ `Msg of string ]) result =
  let len = Unsigned.Size_t.of_int (String.length str) in
  wrap @@ wasm_verify_string (ocaml_string_start str) len
