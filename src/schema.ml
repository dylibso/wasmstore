include Irmin.Schema.KV (Irmin.Contents.String)
module Hash = Irmin.Hash.SHA256
module Key = Irmin.Key.Of_hash (Hash)
module Node = Irmin.Node.Generic_key.Make (Hash) (Path) (Metadata)
module Commit = Irmin.Commit.Generic_key.Make (Hash)
