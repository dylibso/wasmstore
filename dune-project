(lang dune 3.4)

(name wasmstore)

(generate_opam_files true)

(source
 (github username/reponame))

(authors "Author Name")

(maintainers "Maintainer Name")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name wasmstore)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends ocaml dune irmin-git wasm cmdliner)
 (tags
  (topics "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
