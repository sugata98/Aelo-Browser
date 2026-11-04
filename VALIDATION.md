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
confirmed 255 completed `.o` outputs. The attempt then stopped after 1,052
completed steps because the optional Xcode Metal compiler was absent. The
driver now checks the actual Metal compiler during preflight. Its installation
and successful build completion/launch are not yet verified. The nine
build-tool tests pass.

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

- Metal Toolchain 26.6 (17F109) was installed through Xcode Components. Both
  `metal --version` and `metallib --version` run successfully from its mounted
  Apple toolchain. The default sandboxed `xcrun` still selects a placeholder;
  the build now supports ANGLE's explicit toolchain-directory option through
  `AELO_METAL_TOOLCHAIN_DIR`. All 10 build-tool tests pass. Build completion
  and launch remain unverified.

- The failed ANGLE Metal shader compiles successfully when its module cache
  is explicitly placed under the build root (150,688-byte AIR probe output).
  The driver now applies this through generated tool adapters; all 10 build
  safety tests still pass. Full compilation has been restarted.

- The resumed four-job full Chromium build generated ANGLE's actual shader
  AIR (150,608 bytes) and Metal library (360,535 bytes). The driver lock was
  held and Ninja output records were advancing when checked. This verifies
  the Metal build fix; browser build completion and launch remain unverified.

- After the Metal fix, the full build completed another 522 steps and stopped
  at Dawn/Tint source generation because Go attempted to write its default
  user cache. The driver now confines Go build/module caches to the build
  root; all 10 build-tool tests pass. An incremental retry is underway;
  generator completion and final browser launch remain unverified.

- The restarted build successfully completed the Dawn/Tint generator action
  in Ninja (including `gen/src/tint/cmd/bench/enums_core_bench.cc`). This
  verifies the Go-cache fix in the real full Chromium build. Compilation
  continues with four jobs; final app build and launch remain pending.

- Clang crashed once compiling Blink display-lock state. The exact compile
  command passed on retry with unchanged source/compiler/flags. Crash
  reproducers and retry log are retained in ignored build storage; the cause
  remains unestablished. The incremental full build was resumed.

- The resumed full build also recorded a successful Ninja action for the
  formerly failing `display_lock_document_state.o`; no failures were present
  in that resumed build log at the verification check.

- A second Clang crash affected the Bluetooth service after 6,923 additional
  steps. Its exact compile command passed unchanged on retry. The cause is
  unknown; crash evidence is retained and the four-job full build resumed.

- Full Chromium `chrome` target build completed successfully; driver state
  is `action_completed`. App identity/version/executable were checked. The
  native app controller displayed its welcome window. Page rendering and
  renderer-sandbox qualification using disposable storage remain pending.
- Strict recursive code-signature verification failed on the generated bundle
  (resource seal error); distribution signing is unqualified. Direct sandboxed
  launch aborted in AppKit/HIServices registration, and the Terminal fallback
  was rejected by computer-use safety review. User launch with explicit
  disposable-profile arguments is required for the next check.

- Full Chromium disposable-profile launch verified after user Terminal launch.
  The live version page reports the expected executable and `/private/tmp/`
  profile. HTTPS Example Domain navigation, document completion and painted
  page pixels passed through local CDP diagnostics. A native window capture
  omitted page pixels; the CDP screenshot is retained in docs.
- macOS `sandbox_check(pid, NULL, 0)` returned 1 for all six observed renderer
  processes and the GPU process, with errno 0. The browser broker returned 0.
  No sandbox/certificate/web-security disabling arguments were observed.
- Strict signature resource-seal verification, embedded revision provenance,
  workspace integration and broad browser-platform compatibility remain open.


### Workspace port in progress — 3 November 2026

- Added full-Chromium sidebar/Spaces controls and packaged the existing home
  design. Compilation and live UI qualification are pending; the earlier
  successful full-browser launch does not qualify this new patch.
- Ten build-tool tests and the existing native workspace regression executable
  passed. The first compile exposed an observer API mismatch, corrected using
  Chromium's native observer lifetime management; incremental retry is active.
- See docs/chromium-workspace-port.md for implementation boundaries and required
  live gates. CEF workspace/profile files were not changed or imported.

- Workspace UI full chrome target rebuild completed successfully with 18 jobs.
  The new header and region view compiled, driver state is action_completed,
  and the executable exists. Live UI checks are still pending.
- Disposable-profile launch from the agent host failed at Crashpad Mach-port
  registration (permission denied). Launch Services also reports a missing
  executable despite its verified presence. No security flags were changed.
  A normal user launch is needed before interaction/rendering qualification.

- 4 November: REA ordinary-user process launch reached the new UI and
  reproduced SIGABRT in Label::PaintText on a transparent layer. New sidebar
  labels now request grayscale rendering; no checks were disabled. Incremental
  rebuild and live regression verification are pending. The earlier request
  for user Terminal launch is superseded by the working REA launch route.


### Workspace live qualification — 4 November 2026

This supersedes the pending build/live status above. The label-fix full chrome
build completed successfully at 02:03 UTC. REA supplied a working ordinary-user
launch without requiring the user to run Terminal. The app stayed open through
native UI checks of home/sidebar, create/edit/switch Spaces, focused new-tab
membership, All tabs, pin/unpin, close/Reopen, split navigation and collapse.

Default shared the synthetic fixture cookie across Spaces; separate Profile 1
had no cookie at the same origin. Version pages confirmed both disposable
profile paths and the built executable. Fourteen observed renderers and the GPU
were sandboxed (sandbox_check=1, errno=0); broker=0. A controlled application
Quit recorded Normal exit and closed CDP; relaunch without a startup URL
restored Personal selection, both Spaces, tabs and split membership.

The prior label-paint startup fatal did not recur. An earlier test process
disappeared for an unknown reason, so these checks do not establish long-term
stability. The independent CEF watchdog, empty-Space/per-Space-pin parity, import,
nested folders, broad extensions and distribution signing remain unfinished.
See docs/chromium-workspace-launch-evidence.json and docs/chromium-workspace-port.md.


### Independent folder sidebar — implementation checks, 4 November 2026

The new portable C++ tree and native sidebar replace group-backed organization
in source. All three CTest suites passed (legacy workspace, new workspace_tree,
and build_tools with ten cases). Model checks include 100-level nesting,
subtree moves, ordering, pins, empty containers, Unicode/duplicate URLs, rejected
invalid snapshots and preservation of the prior in-memory state. These model
snapshot tests do not establish on-disk UI restoration. Changed native
translation units and GN header dependency checks passed; a full 18-job browser
link is running. Live nested-folder and restart checks are pending; prior
group-sidebar evidence does not qualify this implementation. See
docs/chromium-folder-sidebar.md for controls, persistence and remaining gates.

- The first independent-tree full browser build completed. Fresh disposable
  launch painted the home and + Folder saved a parent-linked record, but the
  Move row stretched vertically and hid the tree. This is a failed layout
  gate, not successful folder qualification. A scoped axis/footer layout fix
  is rebuilding before the remaining live checks.
