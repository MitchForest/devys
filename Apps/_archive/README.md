# Archived Apps

These app targets are preserved from earlier exploration phases. They are excluded from builds but kept in the repo for future use.

| App | What It Was For | Comes Back When |
|-----|------------------|-----------------|
| **mac-server** | Remote automation host exposed over a network API with terminal/session orchestration | V1.5 automation orchestrator |
| **ios-client** | iPhone companion for remote terminal access and host connection flows | V2 iOS app |

## To restore an app

1. Move it from `_archive/` back to `Apps/`
2. Add a new native target in `Devys.xcodeproj`
3. Add its source group, resources, and package dependencies
