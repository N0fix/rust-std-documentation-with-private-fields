#!/bin/bash

set -euo pipefail

targets=(x86_64-unknown-linux-gnu x86_64-pc-windows-gnu)
out_dir=html
rust_dir=rust
init_only=false
clean=false

function print_help() {
    cat << EOF
This script generates internal documentation for the nightly version of Rust's
standard library.

Usage: mkdocs.sh [FLAGS]
    FLAGS:
        --out       Output directory for generated docs. Default: $out_dir
        --rust-dir  The directory to use for the Rust git repo. Default: $rust_dir
        --clean     Remove the Rust target directory after completion
        --help      Print this help message and exit.
EOF
}

function check_prereqs() {
    which rustup >> /dev/null || {
        echo 'Please install rustup and try again.'
        echo 'See https://rustup.rs'
        echo 'Or just run:'
        echo "  curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly --profile minimal --component rust-docs"
        exit 1
    }
    which git >> /dev/null || { echo 'Please install git and try again.'; exit 1; }
    which rg >> /dev/null || { echo 'Please install ripgrep (rg) and try again.'; exit 1; }
}

while [ $# -gt 0 ]; do
    case "$1" in
        --out)
            out_dir="$2"
            shift; shift
            ;;
        --version)
            version="$2"
            shift; shift
            ;;
        --clean)
            clean=true
            shift
            ;;
        --rust-dir)
            rust_dir="$2"
            shift; shift
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown argument '$1'"
            print_help
            echo "Unknown argument '$1'"
            exit 1
            ;;
    esac
done

check_prereqs
echo "$version"
rustup toolchain install "$version" --profile minimal -c cargo -c rustc -c rust-docs
rustup target add "${targets[@]}"
rustc_hash="$(rustc +"$version" -vV | rg '^commit-hash: (.+)$' --replace '$1')"

[ -e "$rust_dir" ]      || mkdir -p "$rust_dir"
[ -d "$rust_dir/.git" ] || git clone https://github.com/rust-lang/rust "$rust_dir"

pushd "$rust_dir" > /dev/null
git fetch --all
git reset --hard "$rustc_hash"
git submodule update --init --recursive --force
popd > /dev/null

# Dirty fix for latest versions
sed -i '1s/^/#![feature(rustc_private)]/' "$rust_dir"/library/std/src/lib.rs
# --generate-link-to-definition causes errors currently (and has been for a while - need to file an issue and investigate)
rustdoc_unstable_flags=(-Z unstable-options --document-hidden-items) # --generate-link-to-definition)
rustdoc_stable_flags=(--document-private-items --crate-version "${rustc_hash:0:7}")
export RUSTDOCFLAGS="--show-type-layout ${rustdoc_stable_flags[*]} ${rustdoc_unstable_flags[*]}"
export RUSTC_BOOTSTRAP=1
export RUSTFLAGS="-Zforce-unstable-if-unmarked"
for target in "${targets[@]}"; do
    echo "Building docs for $target"
    cargo +"$version" doc --target "$target" \
        --manifest-path "$rust_dir"/library/sysroot/Cargo.toml \
        --target-dir "$rust_dir"/target \
    2>&1 | tee cargo_"$target".log || exit 1
done
echo "Successfully documented all targets."
echo "Building final output..."
# :? errors on emtpy or null
rm -rf "${out_dir:?}"/*
mkdir -p "$out_dir/"
# cp static_root/* "$out_dir"/

for target in "${targets[@]}"; do
    mv "$rust_dir/target/$target/doc" "$out_dir/$target"
    printf "Updated: $(date -u)\nHash: %s" "$rustc_hash" > "$out_dir/$target/meta.txt"
done
rm -rf "${rust_dir:?}"/target
echo "All done!"
