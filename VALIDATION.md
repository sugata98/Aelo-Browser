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
| Orderly quit | The app exited with status 0 after closing its embedded browser views |
| Restart | Active Space, tabs and pins reopened; a saved two-pane layout rendered both pages after a full quit/relaunch |

The fixture server uses concurrent handlers: Chromium may preconnect idle sockets, so a single-threaded HTTP server can otherwise cause a misleading apparent navigation hang across Profiles.

Test data was isolated from Arc and the normal Orbit preview profile. No real account, password, extension or user browsing database was imported. Remote debugging was not enabled for these GUI checks.

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
