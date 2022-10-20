# wasmstore

A content-addressable store for WASM modules

- Built-in WASM validation
- History and branching/merging
- CLI and HTTP interfaces

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
- `POST /api/v1/module/*`
  - Add a new module, the request body should contain the WASM module
  - Example: `curl --data-binary @mymodule.wasm http://127.0.0.1:6384/api/v1/module/mymodule.wasm`
- `DELETE /api/v1/module/*`
  - Delete a module by hash or path
- `GET /api/v1/hash/*`
  - Get the hash of the module stored at a specific path
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
- `POST /api/v1/restore/:hash`
  - Revert to the specified commit hash
- `GET /api/v1/snapshot`
  - Returns the latest commit hash
- `GET /api/v1/watch`
  - A WebSocket endpoint that sends updates about changes to the store to the client

There are existing clients for [Rust](https://github.com/dylibso/wasmstore/tree/main/client/rust) and [Javascript](https://github.com/dylibso/wasmstore/tree/main/client/js)

### Authentication

Using the `wasmstore server --auth` flag or the `WASMSTORE_AUTH` environment variable you can restrict certain authentication keys
to specific request methods:

```sh
$ wasmstore server --auth "MY_SECRET_KEY:GET,POST;MY_SECRET_READONLY_KEY:GET"
$ WASMSTORE_AUTH="MY_SECRET_KEY:GET,POST;MY_SECRET_READONLY_KEY:GET" wasmstore server
```

On the client side you should supply the key using the `Wasmstore-Auth` header

## Command line

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

## A note on garbage collection

When the gc is executed for a branch all prior commits are squashed into one
and all non-reachable objects are removed. For example, if an object is still
reachable from another branch it will not be deleted. Because of this, running
the garbage collector may purge prior commits, potentially causing `restore`
to fail.
