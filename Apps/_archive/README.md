# Archived Apps

These app targets are preserved from earlier exploration phases. They are excluded from builds but kept in the repo for future use.

| App | Comes Back When |
|-----|----------------|
| **mac-server** | V1.5 automation orchestrator |
| **ios-client** | V2 iOS app |
| **assistant-mac** | Separate product exploration |
| **assistant-ios** | Separate product exploration |

## To restore an app

1. Move it from `_archive/` back to `Apps/`
2. Add a new native target in `Devys.xcodeproj`
3. Add its source group, resources, and package dependencies
