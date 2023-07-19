open Ctypes

external wasm_verify_file_stub : unit -> unit = "wasm_verify_file"
external wasm_verify_string_stub : unit -> unit = "wasm_verify_string"
external wasm_error_free_stub : unit -> unit = "wasm_error_free"

let fn = Foreign.foreign ~release_runtime_lock:false

let wasm_verify_file =
  fn "wasm_verify_file" (ocaml_string @-> size_t @-> returning (ptr char))

let wasm_verify_string =
  fn "wasm_verify_string" (ocaml_string @-> size_t @-> returning (ptr char))

let wasm_error_free = fn "wasm_error_free" (ptr char @-> returning void)
let clone_string s = Bytes.unsafe_of_string s |> Bytes.to_string

let wrap res =
  if is_null res then None
  else
    let s = coerce (ptr char) string res in
    let out = clone_string s in
    let () = wasm_error_free res in
    Some out

let verify_file filename : string option =
  let len = Unsigned.Size_t.of_int (String.length filename) in
  let ptr = ocaml_string_start filename in
  wrap @@ wasm_verify_file ptr len

let verify_string str : string option =
  let len = Unsigned.Size_t.of_int (String.length str) in
  let ptr = ocaml_string_start str in
  wrap @@ wasm_verify_string ptr len
