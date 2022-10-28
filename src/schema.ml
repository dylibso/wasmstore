include Irmin.Schema.KV (Irmin.Contents.String)
module Hash = Irmin.Hash.SHA256
module Key = Irmin.Key.Of_hash (Hash)
module Node = Irmin.Node.Make (Hash) (Path) (Metadata)
module Commit = Irmin.Commit.Make (Hash)
