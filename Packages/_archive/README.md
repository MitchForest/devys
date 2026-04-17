# Archived Packages

These packages are preserved from earlier exploration phases. They are excluded from builds but kept in the repo for future use.

| Package | What It Was For | Comes Back When |
|---------|------------------|-----------------|
| **Server** | Remote runtime protocol and client for the old automation host / mobile companion direction | V1.5 automation orchestrator, V2 iOS companion |
| **SSH** | Direct interactive SSH client library for macOS and iOS | Remote host workflows return as a first-class product surface |
| **MetalASCII** | GPU ASCII rendering experiment and demo runner | Demo/experiment |

## To restore a package

1. Move it from `_archive/` back to `Packages/`
2. Add it as a local package reference in `Devys.xcodeproj`
3. Add it as a framework dependency to the mac-client target
4. Re-add `import` statements in the mac-client source files that need it
