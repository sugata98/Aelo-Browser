# Developer Preview 0.1 validation

Verified on this Apple Silicon Mac on 3 November 2026. Results apply to the current preview, not all macOS versions or browser workloads.

## Automated checks — passed

The native workspace test executable checks fresh initialization; the three-Space/two-Profile mapping; pins and split references after reload; archive cleanup and restoration preserving logical IDs; a replacement home tab when the last tab is archived; invalid references blocking saves; recovery from damaged JSON using the last valid backup with the original preserved; domain/local URL normalization; escaped search queries; and treating `javascript:` command-bar input as search text.

The final build completed without compiler warnings. CTest passed. App packaging verifies ad-hoc signatures recursively, including Chromium and the helper apps.

## Live native app checks — passed

| Check | Observed result |
|---|---|
| Chromium rendering | The local home page and a real HTTPS page loaded inside the native window |
| Command Bar | URL entry and keyboard submission navigated the active tab |
| Shared Profile | Cookie set in Personal was visible in Focus |
| Separate Profile | Work loaded the same local site with no shared cookie |
| Split browsing | Two browser views rendered simultaneously, separated by the native divider |
| Archive/restore | A live tab was archived and restored through ⌘W / ⇧⌘T |
| Pinned tabs | Pin moved the tab into the Pinned section and persisted through restart |
| Unsaved-page cancel | Typing a synthetic draft, then ⌘W, showed Stay/Leave; Stay preserved the tab and its draft |
| Unsaved-page accept | Leave archived the tab and created a replacement home tab when needed |
| Quit behavior | Earlier checks exited normally; the renamed release build also reproduced a teardown watchdog timeout after saving. Clean shutdown is not reliably qualified. |
| Restart | Active Space, tabs and pins reopened; a saved two-pane layout rendered both pages after a full quit/relaunch |

The fixture server uses concurrent handlers: Chromium may preconnect idle sockets, so a single-threaded HTTP server can otherwise cause a misleading apparent navigation hang across Profiles.

Test data was isolated from Arc and the normal Aelo preview profile. No real account, password, extension or user browsing database was imported. Remote debugging was not enabled for these GUI checks.

## Not yet verified

- Chrome extensions, Web Store, native messaging and password managers.
- Real OAuth flows, passkeys, payments, DRM/proprietary codecs, calls and screen sharing.
- Download completion, upload, permissions, PDF/print and DevTools under realistic workloads.
- Drag-and-drop reorder and command-bar action/tab-switch combinations beyond the observed navigation path.
- Sidebar folder support, Auto-Archive, Arc imports, Peek, Boosts, Easels, sync and AI (not implemented).
- Multiwindow behavior, background tab suspension, extensive accessibility and reduced-transparency/contrast qualification.
- Full back/forward history or form-state recovery after restart (only saved URLs are restored).
- Public notarization and automatic updates (not implemented).

This qualification establishes a working first prototype and several core data/lifecycle behaviors. It is not a browser security audit or an assertion of Arc feature parity.

## Aelo release verification

The renamed app was rebuilt and its native workspace tests passed. Live launch, Aelo branding, menus and two-pane rendering were checked. The native host hierarchy is released before engine shutdown, but the teardown watchdog issue remains reproducible and is disclosed in the release notes.

## Full Chromium migration branch — 3 November 2026

On `feat/full-chromium-migration`, the full Chromium source checkout matches
`fb096c0011f9d50f0a264a9376420cdea9c421e3` (156.0.8078.80). Xcode 26.6,
first-launch status and macOS SDK 26.5 preflight passed. Dependency sync
completed successfully at 11:16 IST with the documented public dependency
snapshot overrides. Chromium's dependency hooks completed. Initial GN
generation was blocked by missing depot_tools Python bootstrap metadata;
the build driver now initializes those pinned tools before configuration.
GN generation later succeeded with 36,370 targets. The initial build scheduler
found a missing LiteRT schema caused by an incomplete earlier LFS checkout.
LiteRT was recovered at the original pinned commit using its official upstream
LFS transport, preserving the incomplete files separately. Independent checks
passed for the revisions and missing-file checks of all 150 Git dependencies.
`git lfs fsck --objects` passed for the recovered LiteRT checkout. The full
Chromium build is now compiling native objects; Ninja's first progress check
confirmed 255 completed `.o` outputs. The nine build-tool tests pass. Successful
build completion and launch are not yet verified.

`git apply --check` accepts the four-file branding/data/Keychain/native-host
isolation patch against that pinned source. Live behavior under those new
identities remains unverified. See [migration details](docs/chromium-migration.md)
for the exact configuration, download recovery steps and remaining gates.

The build-tool tests and existing native workspace tests pass through CTest.
The CEF packaging repair produces an ICNS file that `sips` can decode and an
app whose recursive signatures verify. These checks do not establish full
Chromium browser compatibility.

An opt-in lifecycle trace with synthetic data recorded an ordinary CEF
shutdown completing in 0.212 seconds. A quit-during-creation fixture also
completed teardown. Neither reproduced the documented watchdog failure;
that issue remains unresolved. Chromium's mock Keychain was used only for
disposable fixture data, so these runs do not qualify real credential storage.
CEF UI investigation is paused while the full Chromium build is prioritized.
