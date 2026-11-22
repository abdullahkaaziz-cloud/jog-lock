# ADR-0002: Keep platform-neutral logic in a local Swift package

## Status

Accepted

## Date

2026-11-22

## Context

The distance engine, the run log format and the run files need no iPhone hardware, but they lived in the app target. Testing them meant an iOS simulator run on a Mac. On GitHub Actions a macOS minute costs ten Linux minutes, and the free allowance for a private repo is about 200 macOS minutes a month.

The coming anti-cheat and treadmill work adds more pure logic (matching GPS distance against steps, learning stride length), which needs thorough tests.

## Decision

Move that logic into `Packages/JogLockCore`, a local Swift package with Swift Testing tests. The app links the package through the Xcode project and keeps only what needs iOS frameworks: Core Location, Core Motion, notifications and SwiftUI.

- Package code uses Foundation only and Swift 6 language mode. Public types are `Sendable` value types where possible.
- Anything that touches the outside world is passed in: `RunStore` takes its root folder, so tests use a temporary folder and the app uses `Documents/Runs`.
- CI runs `swift test` in a Linux container on every pull request. The macOS job only builds the app.

## Alternatives considered

- **App target plus an iOS unit-test target.** Standard, but every test run needs a simulator on macOS.
- **The same source files compiled into both the app and a package.** Avoids an Xcode project change, but one file in two modules is confusing and breaks easily.

## Consequences

- Most tests run in seconds on any Mac or Linux machine, and cheaply in CI.
- Types the app uses must be `public`, with explicit initialisers.
- The app needs `import JogLockCore` wherever it uses these types.
