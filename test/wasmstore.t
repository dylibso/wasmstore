  $ export WASMSTORE_ROOT=./test/tmp
Add wasm module `a`
  $ cat a.wasm | wasmstore add - a.wasm 
  314418a1e31ba09cbf48bf4663938bcb87d6a58087652cc53021bc6a4997c446

Rollback `a`
  $ wasmstore rollback a.wasm
  $ wasmstore contains a.wasm
  false
  $ wasmstore add a.wasm
  314418a1e31ba09cbf48bf4663938bcb87d6a58087652cc53021bc6a4997c446

Add wasm module `b`
  $ wasmstore add b.wasm
  de332fe6a29c04d0de4b135f4d251780cdf5f3476d44c17cac493ea3df2e4685

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

Versions
  $ wasmstore versions b.wasm | awk '{ print $1 }'
  de332fe6a29c04d0de4b135f4d251780cdf5f3476d44c17cac493ea3df2e4685

Restore 2
  $ wasmstore restore $SNAPSHOT2

Versions
  $ wasmstore add a.wasm b.wasm
  314418a1e31ba09cbf48bf4663938bcb87d6a58087652cc53021bc6a4997c446
  $ wasmstore versions b.wasm | awk '{ print $1 }'
  de332fe6a29c04d0de4b135f4d251780cdf5f3476d44c17cac493ea3df2e4685
  314418a1e31ba09cbf48bf4663938bcb87d6a58087652cc53021bc6a4997c446

Restore 2
  $ wasmstore restore $SNAPSHOT2

Store should no longer contain `a.wasm`
  $ wasmstore contains a.wasm
  false
  $ wasmstore list
  de332fe6a29c04d0de4b135f4d251780cdf5f3476d44c17cac493ea3df2e4685	/b.wasm

Run garbage collector
  $ wasmstore gc
  3

Remove branch
  $ wasmstore branch test --delete

Run garbage collector
  $ wasmstore gc
  8

Invalid WASM module
  $ head -c 5 a.wasm | wasmstore add - invalid.wasm
  ERROR invalid module: unexpected end-of-file (at offset 0x4)

Versions
  $ wasmstore add a.wasm b.wasm
  314418a1e31ba09cbf48bf4663938bcb87d6a58087652cc53021bc6a4997c446
  $ wasmstore versions b.wasm | awk '{ print $1 }'
  de332fe6a29c04d0de4b135f4d251780cdf5f3476d44c17cac493ea3df2e4685
  314418a1e31ba09cbf48bf4663938bcb87d6a58087652cc53021bc6a4997c446
