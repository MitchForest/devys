# Archived Packages

These packages are preserved from earlier exploration phases. They are excluded from builds but kept in the repo for future use.

| Package | Comes Back When |
|---------|----------------|
| **Agents** | V1.1 cloud agent orchestration needs programmatic agent control |
| **Chat** | V2 multiplayer / team features |
| **Server** | V1.5 automation orchestrator, V2 iOS companion |
| **Browser** | Post-V1 web dev workflows |
| **Canvas** | Post-V1 if needed |
| **MetalASCII** | Demo/experiment |

## To restore a package

1. Move it from `_archive/` back to `Packages/`
2. Add it as a local package reference in `Devys.xcodeproj`
3. Add it as a framework dependency to the mac-client target
4. Re-add `import` statements in the mac-client source files that need it
