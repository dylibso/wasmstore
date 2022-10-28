  $ export WASMSTORE_ROOT=./test/tmp
Add wasm module `a`
  $ cat a.wasm | wasmstore add - a.wasm 
  64a95e86cda3f338b69616f61643e8c303f4470a5feec8ee6a224c1a1d16321f

Add wasm module `b`
  $ wasmstore add b.wasm
  93a44bbb96c751218e4c00d479e4c14358122a389acca16205b1e4d0dc5f9476

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
  93a44bbb96c751218e4c00d479e4c14358122a389acca16205b1e4d0dc5f9476	/b.wasm

Run garbage collector
  $ wasmstore gc
  1

Remove branch
  $ wasmstore branch test --delete

Run garbage collector
  $ wasmstore gc
  5
