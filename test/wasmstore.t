  $ export WASMSTORE_ROOT=./test/tmp

Parsing fail
  $ head -c 12 a.wasm | wasmstore add - a.wasm 
  ERROR invalid module: unexpected end-of-file (at offset 0xb)

Add wasm module `a`
  $ cat a.wasm | wasmstore add - a.wasm 
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31

Rollback `a`
  $ wasmstore rollback a.wasm
  $ wasmstore contains a.wasm
  false
  $ wasmstore add a.wasm
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31

Add wasm module `b`
  $ wasmstore add b.wasm
  d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5

Make sure the store contains the hash and path
  $ wasmstore contains b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31
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
  d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5

Restore 2
  $ wasmstore restore $SNAPSHOT2

Versions
  $ wasmstore add a.wasm b.wasm
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31
  $ wasmstore versions b.wasm | awk '{ print $1 }'
  d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31

Restore 2
  $ wasmstore restore $SNAPSHOT2

Store should no longer contain `a.wasm`
  $ wasmstore contains a.wasm
  false
  $ wasmstore list
  d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5	/b.wasm

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
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31
  $ wasmstore versions b.wasm | awk '{ print $1 }'
  d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31

Set
  $ wasmstore set d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5 c.wasm
  $ wasmstore hash c.wasm
  d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5

  $ wasmstore set d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5 b.wasm
  $ wasmstore versions b.wasm | awk '{ print $1 }'
  d926c50304238d423d63f52f5f460b1a7170fe870e10f031b9cbd74b29bc06e5
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31

Export
  $ wasmstore export -o ./exported
  $ ls ./exported
  b.wasm
  c.wasm

Backup
  $ wasmstore backup backup.tar.gz
  $ tar tzf ./backup.tar.gz | grep 'objects/65/8830c0dfcc89d80c695357f0774eb20ca47adb4286eedd52eb527f9cf03fd5'
  ./objects/65/8830c0dfcc89d80c695357f0774eb20ca47adb4286eedd52eb527f9cf03fd5

Add `a` again
  $ wasmstore add a.wasm
  b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31

Remove `a` by hash
  $ wasmstore remove b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31

No longer contains `a`
  $ wasmstore contains b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31
  false

No longer contains `a`
  $ wasmstore contains a.wasm
  false

No longer contains `a`
  $ wasmstore find b6b033aa8c568449d19e0d440cd31f8fcebaebc9c28070e09073275d8062be31 > /dev/null
  [1]
