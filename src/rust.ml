(* Generated by ocaml-rs *)

open! Bigarray

(* file: lib.rs *)

external wasm_verify_file: string -> (unit, string) result = "wasm_verify_file"
external wasm_verify_string: string -> (unit, string) result = "wasm_verify_string"
