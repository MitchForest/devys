# Ghostty Vendor Staging

This directory stages the pinned Ghostty artifacts for the libghostty rewrite.

Committed files:

- this `README.md`

Generated locally:

- `GhosttyKit.xcframework`
- `share/ghostty`

Bootstrap and build:

```sh
./scripts/bootstrap-ghostty.sh
./scripts/bootstrap-zig.sh
./scripts/build-ghostty.sh
```
