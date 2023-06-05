# wasmstore

[![Latest github release](https://img.shields.io/github/v/release/dylibso/wasmstore?include_prereleases&label=latest)](https://github.com/dylibso/wasmstore/releases/latest)
[![npm](https://img.shields.io/npm/v/@dylibso/wasmstore)](https://www.npmjs.com/package/@dylibso/wasmstore)
[![pypi](https://img.shields.io/pypi/v/wasmstore)](https://pypi.org/project/wasmstore/)
[![crates.io](https://img.shields.io/crates/v/wasmstore-client)](https://crates.io/crates/wasmstore-client)

A content-addressable store for WASM modules

- Built-in WASM validation
- History management, branching and merging
- Command-line interface
- HTTP interface
  - Simple authentication with roles based on HTTP request methods
  - Optional SSL

## Overview

- WebAssembly modules are identified by their `hash` and are associated with a `path`, similar to a path on disk
  - Storing modules based on their hashes allows wasmstore to de-duplicate identical modules
  - Paths make it possible to give modules custom names
- Any time the store is modified a `commit` is created
  - Commits can be identified by a hash and represent a checkpoint of the store
  - Contains some additional metadata: author, message and timestamp
- Every time an existing `path` is updated a new `version` is created automatically
  - `rollback` reverts a path to the previous version
  - `restore` reverts to any prior `commit`
  - `versions` lists the history for a path, including module hashses and commit hashes
- A `branch` can be helpful for testing, to update several paths at once or for namespacing
  - The `main` branch is the default, but it's possible to create branches with any name 
  - `snapshot` gets the current `commit` hash
  - `merge` is used to merge a `branch` into another

## Building

### Docker

There is a `Dockerfile` at the root of the repository that can be used to build and run the `wasmstore` server:

```shell
$ docker build -t wasmstore .
$ docker run -it wasmstore
```

### Opam

The `wasmstore` executable contains the command-line interface and the server, to build it you will need [opam](https://opam.ocaml.org)
installed.

```shell
$ opam install . --deps-only
$ dune build
$ dune exec ./bin/main.exe --help
```

`wasmstore` can also be built using [opam-monorepo](https://github.com/tarides/opam-monorepo):

```shell
$ opam repository add dune-universe git+https://github.com/dune-universe/opam-overlays.git
$ opam install opam-monorepo
$ opam monorepo pull
$ dune build ./bin
$ dune exec ./bin/main.exe --help
```

## Installation

Once `wasmstore` has been built it can be installed with:

```sh
$ make PREFIX=/usr/local install
```

## HTTP Interface

The server can be started using the `wasmstore` executable:

```sh
$ wasmstore server
```

or `docker-compose`:

```sh
$ docker-compose up
```

All endpoints except the `/branch` endpoints accept a header named `Wasmstore-Branch`
that will cause the call to modify the specified branch instead of the default
branch.

- `GET /api/v1/modules/*`
  - Returns a JSON object mapping module paths to their hashes for the
    specified path
  - Example: `curl http://127.0.0.1:6384/api/v1/modules`
- `GET /api/v1/module/*`
  - Get a single module by hash or path, the module hash will also be stored in
    the `Wasmstore-Hash` header in the response.
  - Example: `curl http://127.0.0.1:6384/api/v1/module/mymodule.wasm`
- `HEAD /api/v1/module/*`
  - Returns `200` status code if the path exists, otherwise `404`
- `POST /api/v1/module/*`
  - Add a new module, the request body should contain the WASM module
  - Example: `curl --data-binary @mymodule.wasm http://127.0.0.1:6384/api/v1/module/mymodule.wasm`
- `DELETE /api/v1/module/*`
  - Delete a module by hash or path
- `GET /api/v1/hash/*`
  - Get the hash of the module stored at a specific path
- `POST /api/v1/hash/:hash/*`
  - Set the path to point to the provided hash (the hash should already exist in the store)
- `PUT /api/v1/branch/:branch`
  - Switch the default branch
- `POST /api/v1/branch/:branch`
  - Create a new branch
- `DELETE /api/v1/branch/:branch`
  - Delete a branch
- `GET /api/v1/branch`
  - Return the name of the default branch
- `GET /api/v1/branches`
  - Return a JSON array of active branch names
- `POST /api/v1/gc`
  - Run garbage collection
- `POST /api/v1/merge/:branch`
  - Merge the specified branch into the default branch
- `POST /api/v1/restore/:hash/*`
  - Revert to the specified commit hash
  - It's possible to revert the entire tree or a single path 
- `POST /api/v1/rollback/*`
  - Revert to the last commit
  - This can also be used to revert the entire tree or a single path
- `GET /api/v1/snapshot`
  - Returns the latest commit hash
- `GET /api/v1/commit/:hash`
  - Returns a JSON object with information about a commit
- `GET /api/v1/versions/*`
  - Returns an array of pairs (module hash, commit hash) of all previous modules stored at the provided path
- `GET /api/v1/version/:index/*`
  - Returns a previous version of a module at the provided path
- `GET /api/v1/watch`
  - A WebSocket endpoint that sends updates about changes to the store to the client
- `* /api/v1/auth`
  - This endpoint can be used with any method to check capabilities for an authentication secret

There are existing clients for [Rust](https://github.com/dylibso/wasmstore/tree/main/client/rust), [Javascript](https://github.com/dylibso/wasmstore/tree/main/client/js)
[Python](https://github.com/dylibso/wasmstore/tree/main/client/python) and [Go](https://github.com/dylibso/wasmstore/tree/main/client/go)

### Authentication

Using the `wasmstore server --auth` flag or the `WASMSTORE_AUTH` environment variable you can restrict certain authentication keys
to specific request methods:

```sh
$ wasmstore server --auth "MY_SECRET_KEY:GET,POST;MY_SECRET_READONLY_KEY:GET"
$ WASMSTORE_AUTH="MY_SECRET_KEY:GET,POST;MY_SECRET_READONLY_KEY:GET" wasmstore server
```

On the client side you should supply the key using the `Wasmstore-Auth` header

## Command line

See the output of `wasmstore --help` for a full list of commands

### Examples

Add a file from disk

```sh
$ wasmstore add /path/to/myfile.wasm
```

Get module using hash:

```sh
$ wasmstore find <MODULE HASH>
```

Get module using path:

```sh
$ wasmstore find myfile.wasm
```

Create a new branch:

```sh
$ wasmstore branch my-branch
```

Add module to non-default branch

```sh
$ wasmstore add --branch my-branch /path/to/another-file.wasm
```

Merge a branch into the main branch

```sh
$ wasmstore merge my-branch
```

Delete a branch

```sh
$ wasmstore branch my-branch --delete
```

Get the current commit hash:

```sh
$ wasmstore snapshot
```

Restore to a prior commit:

```sh
$ wasmstore restore <COMMIT HASH>
```

Run garbage collection:

```sh
$ wasmstore gc
```

Export the main branch to a directory on disk:

```sh
$ wasmstore export -o ./wasm-modules
```

Backup the entire database:

```sh
$ wasmstore backup backup.tar.gz
```

To create a new store from a backup:

```sh
$ mkdir $WASMSTORE_ROOT
$ cd $WASMSTORE_ROOT
$ tar xzf /path/to/backup.tar.gz
```

## A note on garbage collection

When the gc is executed for a branch all prior commits are squashed into one
and all non-reachable objects are removed. For example, if an object is still
reachable from another branch it will not be deleted. Because of this, running
the garbage collector may purge prior commits, potentially causing `restore`
to fail.
