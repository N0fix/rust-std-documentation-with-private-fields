This repository stores rust's std documentation built with private fields.

This is similar to https://stdrs.dev/, but this should stay up-to-date so that it can be used with struct generation.

The script used to generate this is available in `script.sh` and it a slightly modified version of the one provided by https://stdrs.dev/.

Basically, it builds rust toolchains with `--document-private-items --document-hidden-items`.