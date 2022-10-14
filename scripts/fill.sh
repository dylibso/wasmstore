#!/usr/bin/env bash

for i in $(seq "$1"); do
  x=$(date +%s%N)
  echo "$x" | wasm-tools smith --min-funcs 10 --min-imports 10 --min-exports 10 | _build/default/bin/main.exe add - "$i/$x.wasm"
done
