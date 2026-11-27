# ADR-0006: Lock buddies on iCloud (CloudKit)

## Status

Proposed (PR #18), 24 November 2026.

## Context

Lock buddies tie two people's locks together. That needs the two phones to share a little data: a first name and today's distance. Jog Lock has no server, its run data stays private, and no secrets go in the repository.

## Decision

- **iCloud (CloudKit), no server of our own.**
  - The person who invites makes a zone in their private iCloud database and shares the whole zone by link (`CKShare(recordZoneID:)`, anyone with the link can join).
  - The buddy accepts the link and sees the zone in their shared database.
  - Each phone writes one `Status` record: name, lock day, counted metres, target, met, updated. A `Team` record holds the mode.
- **Syncing.**
  - A `CKDatabaseSubscription` on each side sends a silent push when something changes. The app also syncs when it opens and when the lock buddy screen opens.
  - Records are read with zone changes (no queries), so the CloudKit schema needs no indexes.
- **Rules in core.**
  - `TeamMode.together`: both meet their own target, then both open.
  - `TeamMode.forEachOther`: your apps open when your buddy's distance today reaches your target.
  - A rest day is always open.
  - What a buddy shared on another lock day doesn't count.
  - A team never locks apps already open today.
  - The team counts only once a buddy has joined.
  - Banking stays with your own running.
- **Leaving.** The owner deletes the zone, ending the team for both. A member deletes their record and leaves the share.

## Consequences

- **The app target gets three new entitlements:** iCloud (CloudKit, container `iCloud.com.abdullahaziz.JogLockTracker`), push notifications (`aps-environment`) and `CKSharingSupported`, plus the remote-notification background mode.
- **Set-up in Xcode.** The container may need to be added once in Signing & Capabilities.
- **Before the App Store**, deploy the CloudKit schema to production in CloudKit Console.
- **Silent pushes aren't guaranteed.** A buddy's run may only show when the app next opens or the shield's Run now opens it.
- **The share link can be forwarded.** Only the most recently updated other record counts as the buddy.
- **What's shared.** A first name and today's distance go to the buddy's phone through iCloud. That's data shared with another user, so the privacy policy should say so.
