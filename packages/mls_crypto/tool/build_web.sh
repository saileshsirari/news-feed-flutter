#!/bin/sh
# Builds the encryption library for the browser and puts it in the app's
# web/mls/ (next to web/sqlite3.wasm). Plain Rust, no threads (see
# rust/Cargo.toml); run again after changing the Rust code.
set -e
cd "$(dirname "$0")/.."
wasm-pack build rust --release --target web --no-typescript --no-pack \
  --out-dir ../../../web/mls --out-name mls_crypto_web \
  -- --no-default-features
rm -f ../../web/mls/.gitignore
ls -l ../../web/mls
