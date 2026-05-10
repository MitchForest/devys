# Devys

Devys is a native macOS 26 terminal-first coding environment.

The product direction is a fast terminal app that can grow into a compact IDE without losing terminal primacy: native windows and tabs, a project drawer, file viewing, syntax-highlighted editors, diff viewing, and agent workflows that feel like part of macOS instead of a web app inside a shell.

## Product Shape

- Native macOS app, built with Swift and SwiftUI.
- Strict macOS 26 target. There are no older macOS, iOS, or compatibility fallback paths in the active product.
- Terminal-first workflow with file and editor affordances layered around the terminal.
- Liquid glass and heavy material surfaces through the shared UI design system.
- Direct distribution outside the Mac App Store.

## Active Source Layout

- `Apps/mac-client` is the active macOS app host.
- `Packages/Terminal` owns reusable terminal, composer, and product shell pieces.
- `Packages/Editor`, `Packages/Syntax`, `Packages/Text`, and `Packages/Rendering` own file viewing, syntax, text, and Metal rendering capabilities.
- `Packages/UI` owns shared design-system primitives.
- `Packages/SSH` and `Packages/RemoteCore` contain remote capability foundations.

Internal planning notes, generated dependency builds, archived experiments, and local automation state are intentionally excluded from the public source tree.

## Build

Use the shared Xcode scheme:

```sh
xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build
```

Package-local checks can be run from each package directory with:

```sh
swift test
```

## Permissions

The app is intentionally unsandboxed and hardened-runtime enabled.

That is the correct posture for a terminal-first developer tool that needs to launch shells, interact with repositories, inspect files selected by the user, and eventually run git and diff workflows. Microphone and speech usage strings are present for composer dictation.

## Distribution

Primary distribution should be a Developer ID signed, hardened-runtime, notarized DMG download from the Devys website.

The Mac App Store is not the target distribution channel for the current product shape because App Sandbox would constrain the shell, repository, file-system, and tool-spawning workflows that make the app useful.

Recommended release path:

1. Archive `mac-client` in Release configuration.
2. Sign with a Developer ID Application certificate.
3. Notarize with Apple notary tooling.
4. Staple the notarization ticket.
5. Package as a DMG and publish on the website.
6. Add Sparkle for native in-app updates once the first public distribution path is stable.
