(lang dune 3.2)
(cram enable)

(name wasmstore)

(generate_opam_files true)

(source
 (github dylibso/wasmstore))

(authors "Dylibso Inc.")

(maintainers "Zach Shipko <zach@dylib.so>")

(license BSD-3-clause)

(documentation https://github.com/dylibso/wasmstore)

(package
 (name wasmstore)
 (synopsis "A WASM datastore")
 (description "An OCaml library and command line program used to store WebAssembly modules")
 (depends 
   ocaml
   dune
   irmin
   irmin-fs
   irmin-watcher
   lwt
   lwt_eio
   eio_main
   (cohttp-lwt-unix (>= "6.0.0~alpha2"))
   fmt
   logs
   websocket
   (cmdliner (>= "1.0.0"))
   yojson
   ctypes
   ctypes-foreign
   conf-rust-2021)
 (tags
  (topics wasm database irmin)))

