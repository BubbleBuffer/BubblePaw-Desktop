#!/usr/bin/env bash
# Regenerates the Rust crate licences the app lists (assets/licences/*.json)
# from native/Cargo.lock with cargo-about. CI runs this and fails when the
# committed files differ. Needs cargo-about 0.9.3:
#   cargo install cargo-about --version 0.9.3 --locked --features cli
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/licences
cargo about generate --manifest-path native/Cargo.toml --config native/about.toml \
  --locked --fail --format json | python3 tool/licences.py > assets/licences/core-crates.json
cargo about generate --manifest-path native/Cargo.toml --config native/about-phone.toml \
  --no-default-features --locked --fail --format json | python3 tool/licences.py > assets/licences/phone-crates.json
