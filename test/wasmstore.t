  $ export WASMSTORE_ROOT=./test/tmp
Add wasm module `a`
  $ cat a.wasm | wasmstore add - a.wasm 
  effcf1148d83384fcb7011f9c814a2621ab75d0486ba45f039338bb907610fe4

Add wasm module `b`
  $ wasmstore add b.wasm
  aeb940829d6cca8f5b36746c276899b1516d212daf2a7bcdc3843d0eeb65cee3

Make sure the store contains the hash and path
  $ wasmstore contains 0312a97e84150ab77401b72f951f8af63a05062781ce06c905d5626c615d1bc2
  true
  $ wasmstore contains a.wasm
  true

Snapshot 1
  $ export SNAPSHOT1=`wasmstore snapshot`

Make a new branch
  $ wasmstore branch test

Remove `a`
  $ wasmstore remove a.wasm

Snapshot 2
  $ export SNAPSHOT2=`wasmstore snapshot`

Restore 1
  $ wasmstore restore $SNAPSHOT1
  $ wasmstore contains a.wasm
  true

Restore 2
  $ wasmstore restore $SNAPSHOT2

Store should no longer contain `a.wasm`
  $ wasmstore contains a.wasm
  false
  $ wasmstore list
  aeb940829d6cca8f5b36746c276899b1516d212daf2a7bcdc3843d0eeb65cee3	/b.wasm

Run garbage collector
  $ wasmstore gc
  1

Remove branch
  $ wasmstore branch test --delete

Run garbage collector
  $ wasmstore gc
  5
