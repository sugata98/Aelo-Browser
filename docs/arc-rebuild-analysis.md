# Arc reconstruction: architecture audit and build plan

Inspected on 3 November 2026. Target: `/Applications/Arc.app`, macOS version 1.165.1 (87405). Scope assumption: macOS first, with eventual Arc feature parity. This is an evidence-backed architecture and feature audit, not a recovery of Arc's original source code or a completed implementation.

## Recommendation

Build an independent, local-first browser on a maintained Chromium foundation. For the stated goal of all Arc features, start with a small Chromium fork and keep browser changes narrow. Implement the workspace model separately from Chromium so it can evolve without spreading changes throughout the engine.

Use native AppKit/SwiftUI where it materially improves the macOS experience; use an Objective-C++ boundary for integration with Chromium C++. Do not make a complete replacement native browser shell the first milestone. First prove that an upstream Chromium build can host the workspace model and two simultaneously visible web contents while preserving extensions and profile behavior. Replacing more of the shell can follow.

A CEF-based native shell is a credible alternative if the priority becomes an earlier personal browser, but first test its exact extension, login, DRM, password-manager and media requirements. This inspection does not establish CEF compatibility with every Arc feature. An Electron prototype can demonstrate interaction design, but it is a poor default for the promised compatibility target: Electron explicitly does not support arbitrary Chrome Web Store extensions. [Electron extension documentation](https://www.electronjs.org/docs/latest/api/extensions), [CEF project](https://github.com/chromiumembedded/cef).

There are 49 days between this inspection and the announced sunset. A full production browser with all Arc features is not a credible seven-week promise from a standing start. A migration tool and a focused macOS preview are better deadline targets. Full parity remains a subsequent, explicitly tracked objective.

## Deadline and immediate preservation

Arc's official announcement says desktop Arc stops working on **22 December 2026**, when Arc accounts are deactivated. It also says account data is deleted within 30 days of deactivation. Treat preservation as a separate urgent task; finishing a replacement should not be a prerequisite for saving your data. [Official announcement](https://arc.net/).

The official macOS export instructions point to Settings → Advanced → Export Data. That control was **not present in the Advanced panel observed in this installed build**. Do not assume the online instructions match this binary. Verify the supported export path/version while Arc is still available. No app update or export was performed in this investigation.

Plan to preserve Spaces, Favorites, pinned tabs, folder hierarchy, Boosts, Easels/captures where exportable, and custom shortcuts. Handle passwords through a deliberate supported export/import flow. A list of links cannot preserve profile isolation, extension state, layouts, passwords or sessions. A raw profile copy is also not a guaranteed portable restoration: encrypted browser data may depend on the original application and Keychain context.

## What was actually inspected

Evidence labels used below:

- **REA**: static binary metadata decoded by REA, tied to an exact executable hash.
- **Package**: Info.plist, framework dependencies, exported symbols, readable strings, scripts and resources inspected with local read-only tools.
- **UI**: controls and explanatory text observed in the running app. This establishes presence, not successful end-to-end operation.
- **Proposed**: a reconstruction design or acceptance criterion; not a claim about Arc's implementation.

The investigation covered the application bundle, main executable, ArcCore executable, bundled feature resources, AppleScript dictionary, linked frameworks, selected embedded JavaScript, and live settings for General, Profiles, Max, Links, Shortcuts and Advanced. It also observed the sidebar and Tabs menu.

No private profile files, credentials or browsing databases were extracted. Existing personal tab contents were not used as evidence. UI inspection opened settings and menus, then returned to the original browser window without changing preferences.

### Binary identity

| Component | Finding |
|---|---|
| App | Arc 1.165.1, build 87405 |
| Bundle identifier | `company.thebrowser.Browser` |
| Minimum OS declared | macOS 13.0.0 |
| Main executable | Universal Mach-O, x86_64 and arm64; REA selected arm64 |
| Main executable size | 164,733,504 bytes |
| Main SHA-256 | `8e435466264211767801f9977545fd1f07ff5fc713be345890864ea0e23d596e` |
| Engine | `ArcCore.framework`, declared version `153.0.8010.53` |
| Engine SHA-256 | `1b4607ae710a828032328042d613bee389fed6e722fc5939a2b6220148043f44` |

The engine also contains `Chrome/153.0.8010.53` strings, Chromium resource packs and renderer/GPU helper apps. These corroborate the Chromium basis; this version identification is not a finding that the installed browser is fully patched against current vulnerabilities.

### Architecture established by the artifacts

1. **Native application layer.** The main executable links AppKit, SwiftUI, Combine and ArcCore. REA decoded Swift-mangled Objective-C-visible classes including native web-content hosting and split-view controls. Resource bundles expose 55 ARC-prefixed feature/UI modules. Arc is not simply an Electron page with a sidebar.
2. **Browser engine and native bridge.** ArcCore exports Objective-C classes such as `ArcBrowserApplication`, `ArcBrowser`, `ArcBrowserContext`, `ArcWebContents`, `ArcBrowserContextExtensions`, downloads/history/preferences objects, navigation and PiP controllers. The app contains a higher-level ADK bridge vocabulary. This supports a native-shell/Chromium-engine boundary; it does not recover its complete ABI or C++ source.
3. **Separate workspace persistence.** Embedded filenames identify sidebar, windows, profiles, archive, session restoration, Boosts, captures, shortcuts and link-routing stores. The exact schemas and migration semantics were not decoded from personal data.
4. **External service integrations.** Firebase Auth/Firestore, gRPC and CloudKit-related components are packaged. Both Firebase and CloudKit sync names remain in the binary. Their presence does not identify the active sync backend for every account or prove current server availability.
5. **Operational layer.** Sparkle update framework, Sentry, Lottie and Datadog-related resources are present. Bundling a dependency does not prove its runtime configuration or that it transmits data.

### Concrete bridge evidence

REA decoded these selectors in ArcCore; they are API declarations/dispatch metadata, not observed call traces:

| Capability | Examples |
|---|---|
| Profile contexts | `createBrowserContext:type:completion:error:`, `loadBrowserContext:type:completion:`, `availableBrowserContextAttributes` |
| Browser lifetime | `createBrowser:withDelegate:forWindow:`, `restoreBrowser:withSessionID:browserCreatedCallback:finishedCallback:`, `tryToTerminate:` |
| Extensions | `installExtensionFromWebstore:unattended:completion:`, `installExtensionFromUnpackedPath:completion:`, `listExtensions`, `getAllExtensionCommands` |
| Browser UI integration | `executeExtensionAction:`, `pinExtension:`, `showExtensionContextMenu:`, `triggerExtensionOmniboxInput:inputText:disposition:` |
| Boost-like effects | `registerStylesheet:withIdentifier:forHostPattern:`, `registerScript:withIdentifier:forHostPattern:`, color-filter, color-scheme and zoom registration |
| Navigation | `load:initiatorOrigin:transition:fromAddressBar:typedWithHttpScheme:`, `goBack`, `goForward`, `reloadWithoutCache` |
| Downloads | `pause`, `resume`, `canResume`, `currentState`, progress and target-path accessors |
| Accessibility | `enableAccessibilityForScreenReader`, `ensureBasicAccessibilityEnabled` |

Two especially useful resource findings:

- The Boost selector-picker script finds the hovered DOM element, constructs/ranks CSS selectors, reports match counts and returns matching rectangles. A faithful replacement needs element selection and robust selectors, beyond a CSS text field.
- The Easel helper intercepts links and routes them to a new tab, rather than allowing inline navigation. Embedded-content navigation policy is part of the product behavior.

### Local state surfaces identified

Names observed in the shipped executable include `StorableSidebar.json`, `StorableWindows.json`, `StorableSessionRestorationData.json`, `StorableProfiles.json`, `StorableProfileContainers.json`, `StorableBoostsData.json`, `StorableLinkRouting.json`, `StorableArchive.json`, `StorableArchiveItems.json`, `StorableCaptures.json`, `StorableKeyBindings.json`, and `StorableLibrary.json`.

These are migration discovery leads, not a guarantee that each file exists in the current user profile or that its name reflects its complete role. The importer must use versioned parsers and fixture tests, not guesses based on filenames.

## Feature parity map

Every row remains in scope for the eventual clone. Priority controls implementation order, not a silent reduction of the requested product. “UI” means observed controls, not a completed behavioral test.

| Feature family | Evidence in this build | Reconstruction work | Stage |
|---|---|---|---|
| Vertical sidebar, Favorites, pinned and Today tabs, nested folders | UI; resource bundles; AppleScript `topApp`/`pinned`/`unpinned` locations | Persistent tree, navigation identity, reorder/move/rename, keyboard focus | First preview |
| Spaces and per-Space themes | UI; SpaceCreation/SpaceStyleEditor bundles | Ordered workspace records, switching, color/icon/title, multiwindow rules | First preview |
| Profiles | UI; REA context creation | Separate browser contexts for cookies, logins, history and extensions | First preview |
| Multiple Spaces sharing one Profile | Explicit live Profiles explanation | Space → profile reference; do not create a new cookie jar per Space | First preview |
| Command Bar | UI placeholder; CommandBar/URLInputter bundles; ranking symbols | URLs/search/open-tab switching/actions, suggestions, keyboard navigation | First preview |
| Split View | REA native split controls; layout strings; shortcut | Multiple live web contents, pane focus, resizing, reordering, saved layouts | First preview |
| Auto-Archive and recovery | UI profile setting (12-hour default shown); archive stores | Inactivity semantics, exclusions, archive search, undo/reopen | First preview |
| Session restoration and multiple windows | UI restore setting; REA restoration API | Atomic workspace save plus engine restoration; crash recovery | First preview |
| Chrome extensions | REA installation/action/command interfaces | Store installs, permissions, updates, toolbar popups, shortcuts, side panels, profile scope | Engine gate; then preview |
| Normal browser platform | Engine interfaces and packages | Downloads, permissions, history, find, PDF/print, dialogs, file pickers, private windows, DevTools | Engine gate; then preview |
| Peek | Live Links settings; PeekState strings | Preview surface, Shift-click policy, pinned/Favorite cross-site rules, promote/dismiss | Next |
| Little Arc | Live Links settings; LittleBrowser bundle | Separate lightweight windows, global shortcut, promote to Space, archive rules | Next |
| Air Traffic Control | Live button; routing store and action strings | Rule matching and precedence for external URLs and destination Spaces | Next |
| Boosts | Live setting; editor/dialog bundles; REA effects APIs; selector JS | Per-site CSS/JS, picker/Zap-style selection, editor, enable/disable, persistence | Next |
| Picture in Picture and media controls | Live automatic PiP setting; media/PiP bundles; engine APIs | Video detachment/return, tab audio, media session and keyboard integration | Next |
| Captures and library/home | Capture/AppTray/Home resources; capture shortcuts | Selected/full-page capture, local assets, library, search and previews | Next |
| Easels | EaselUI resource; inline-link helper | Canvas/object model, images/links/captures, persistence; sharing separately | Later |
| Notes/rich text | TextEditor/ArcRichTextEditor resources | Determine currently reachable vs retained legacy behavior before rebuilding | Audit; later |
| Tidy Tabs | Live Max setting | Group Today tabs; define thresholds, deterministic fallback and undo | Later |
| Instant Links | Live Max setting | Search-result navigation and multi-query behavior with explicit fallback | Later |
| Five-second previews | Live Max setting | Hover/Shift previews, summaries, cancellation, cache and failures | Later |
| Tidy titles and downloads | Live Max settings | Optional rename services, provenance, undo and original-name preservation | Later |
| Ask on Page / Ask Arc / ChatGPT shortcut | AskInPage/AskArc artifacts; live ChatGPT option | Grounded page questions and provider integration; verify current reachability | Later |
| Live folders and site integrations | GitHub Live Folder strings; app-specific resources | Authentication, refresh, reconciliation, failure state and opt-in behavior | Later |
| Sync | Live Sync Sidebar setting; Firebase/CloudKit artifacts | Your own service, encryption/recovery, conflicts/deletes, offline retry | Later |
| Sharing Spaces/folders/splits/Easels/Boosts | SharableObjects and sharing resources | Your own hosting, stable IDs, permissions, revocation and asset lifecycle | Later |
| Import/export | Import bundles; REA importer interfaces; official export guidance | Arc workspace importer, portable export, mapping and per-item error report | First preservation milestone |
| Custom shortcuts and automation | Live list reports 100 items; shipped AppleScript dictionary | Central action registry, shortcut conflict policy; scripting support | Next |
| Translation, ad blocking, site controls | Dedicated bundles; engine content-settings and blocklist interfaces | Use engine-backed services; verify site exceptions and persistence | Preview/next |
| Native polish and accessibility | UI sound/haptics/drag settings; AppKit metadata | VoiceOver, reduced motion, focus, fullscreen, drag/drop, custom icon and signing | Throughout |
| Updates and diagnostics | Sparkle/Sentry/Datadog resources | Your own signed releases, engine update pipeline, crash diagnostics | Before daily use |

## Proposed implementation architecture

```text
macOS application shell
  AppKit window/content hosting; SwiftUI settings and workspace controls
            |
application actions + workspace reducer/store
  profiles | spaces | sidebar tree | tabs | splits | archive | routing
            |
small Objective-C++ / C++ browser integration boundary
  profiles | WebContents lifetime | extension actions | downloads | permissions
            |
maintained Chromium fork
  rendering | networking | sandbox | extensions | browser platform services

local workspace database + migrations + portable import/export
optional independent services: sync, sharing, AI
```

This is a proposed decomposition, not Arc's recovered source layout. Chromium's existing browser services should remain authoritative for browser profile data. The workspace store owns Arc-like organization; do not duplicate cookie/password/permission implementations in Swift.

Recommended application entities:

- `Profile`: stable identity and dedicated engine profile directory; owns privacy/extension/search defaults.
- `Space`: name, theme, ordering and a `profileID`. Many Spaces may reference one Profile.
- `SidebarItem`: typed folder, tab, split group, Easel or supported legacy object; explicit parent/order.
- `TabRecord`: persistent logical identity, original pinned URL, current navigation/session reference, title override, activity/archival state. A live renderer is temporary and may be discarded.
- `SplitLayout`: pane membership, orientation/geometry, focused pane and layout version. Verify observed pane constraints before fixing a maximum.
- `WindowState`: active Space, focused content, bounds, fullscreen and session restoration mapping.
- `ArchiveEntry`, `RoutingRule`, `Boost`, `Capture`, `ShortcutBinding`: separately versioned records.

Proposed invariants: moving a tab between Spaces in the same Profile preserves its login context; moving between different Profiles requires an explicit reopen policy. Closing a web-content surface must not accidentally delete a pinned bookmark. Renderer discard is different from archiving. A split references logical tabs rather than owning untracked duplicate tabs. Private sessions must not enter persistent workspace/history/sync records.

Use a transactional local database with schema migrations for the new workspace model. Add portable JSON/HTML export. This is an engineering recommendation, not evidence that Arc uses that database format.

## Engine choice and compatibility gate

| Foundation | Suitability | Main tradeoff |
|---|---|---|
| Small Chromium fork | Recommended for the all-features goal | Retains browser services but requires C++ expertise, build infrastructure and ongoing upstream merges |
| CEF + native shell | Candidate for a smaller personal browser | Faster embedding path; browser-feature and extension parity must be demonstrated on the chosen build |
| Electron | Useful for a throwaway UX study | Official extension support is deliberately incomplete |
| WKWebView-based shell | Outside the requested Chromium requirement | Does not satisfy the stated engine choice |

Before spending weeks on visual polish, prove these in the selected foundation: a real password-manager extension including native messaging if needed; Web Store installation and updates; Google/Microsoft login; passkeys; video calls with permission prompts and device changes; protected video playback and required codecs; PDF/printing; two live split panes; safe private browsing; restart/crash recovery.

Chromium alone does not entitle a new browser to Chrome's private service APIs or production Google Sync. Plan independent sync and explicitly validate service access. [Chromium API key documentation](https://www.chromium.org/developers/how-tos/api-keys/).

Chromium's Mac build documentation requires Xcode and the macOS SDK and uses depot_tools, GN and Ninja. This machine currently reports Command Line Tools as its selected developer directory; a working browser build environment has not been established. [Official Mac build instructions](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md).

## Build sequence and reviewable milestones

These dates are proposed planning targets, not commitments. They assume experienced macOS/C++ development and working build infrastructure. A solo developer should allow additional time; cloud services, mobile applications and full production parity are not covered by the seven-week preview target.

| Window | Deliverable | Exit condition |
|---|---|---|
| 3–6 Nov | Preservation plan, reproducible build setup, versioned behavior ledger | Supported export identified; representative import fixtures available; upstream Chromium launches |
| 7–13 Nov | Engine feasibility spike | Required extensions/login/media tested; two live panes; separate Profiles; signed dev app; documented engine decision |
| 14–27 Nov | Workspace preview | Spaces, Favorites/pins/Today, nested folders, Command Bar, archive, split layout and restart restoration |
| 28 Nov–11 Dec | Personal beta | Arc import, Peek/Little Arc/routing as capacity permits; no known data-loss paths; real daily-use compatibility report |
| 12–21 Dec | Preservation and release buffer | Verified portable export; restore rehearsal; signed build/update test; remaining parity gaps disclosed |
| After preview | Complete the parity ledger | Boosts/capture/media polish; Easels; optional sync/sharing/AI; complete compatibility and accessibility qualification |

Preservation should happen near the start, not on the last day. If the first compatibility gate fails, revise the engine choice before continuing the UI implementation. Do not hide a failing browser-platform requirement behind a polished sidebar.

The first coding deliverable should therefore be an **engine-and-workspace spike**: two independent Profiles, two Spaces sharing one of them, a small persistent sidebar, two live panes, one installed real extension, and restart restoration. That tests the riskiest assumptions while establishing a usable foundation.

## Validation needed before claiming parity

Use disposable profiles and fixture pages. The following scenarios have not been exercised in this audit:

1. Pinned-tab navigation and reset-to-original behavior; closing vs archiving vs deleting; Favorites scope across Profiles.
2. Nested-folder moves, duplicate URLs, Unicode/empty titles, reordered Spaces, cross-profile moves, undo and redo.
3. Split focus, independent back/forward, pane removal, dragging, fullscreen and multiwindow interaction.
4. Auto-Archive across sleep/wake and clock changes; exceptions for active, audible, pinned or downloading tabs; recovery.
5. Browser/renderer crash, force quit, corrupted workspace record and interrupted schema migration.
6. Extension background workers, popups, side panels, shortcuts, permissions, store updates and native messaging.
7. OAuth redirects, passkeys, password/autofill prompts, WebAuthn, HTTP authentication and private sessions.
8. Downloads, resume/cancel, file pickers, uploads, printing, PDF, notifications, certificate errors and external protocols.
9. WebRTC, screen sharing, camera/microphone changes, PiP, audio focus, DRM and codecs.
10. Boost selector durability on dynamic pages, iframe/shadow-DOM behavior, CSS/JS host scope, injection timing and removal.
11. Sync concurrent edits, conflicting moves/deletes, offline queues, key recovery, sign-out and device loss.
12. AI cancellation/errors/undo, source grounding and the actual reachable legacy feature set.
13. VoiceOver and keyboard focus throughout the sidebar, command bar, split panes and settings; reduced motion, appearance, Retina and multiple displays.
14. Fresh installation, signing/notarization, custom app icon, update and rollback, with existing workspace data retained.

Capture Arc's observed result, clone result, fixture/build version and pass/fail evidence for each. Current settings visibility is insufficient evidence for these behaviors. Performance targets should follow a measured Arc baseline using the same pages, Profiles and tab counts.

## REA coverage and remaining investigation

REA successfully opened both universal binaries, selected arm64 and decoded native Objective-C dispatch metadata without executing recovered target code. The main-app expanded record contains 845 class/metaclass records and 2,905 dispatch implementation records; the engine record contains 367 class/metaclass records and 2,352 dispatch implementation records. These are retained record counts, not unique feature/class counts, and coverage is partial.

Important limitations:

- No Ghidra, Hopper, IDA or Kuna decompiler provider was available. No function pseudocode, complete call graph or recovered source was produced.
- REA's plist/native utility path failed while compiling its helper because the selected Apple compiler and SDK were incompatible. The plist facts in this report instead came from Python's read-only plist parser.
- GNU objdump was unavailable to the REA provider; local Apple `otool`/`nm`/`strings` supplied complementary package findings and are labelled separately.
- Metadata readers reached record budgets; Swift declaration/witness/vtable coverage is not complete. Unresolved ivar offsets are retained as limitations.
- Two complete metadata responses exceeded the MCP delivery budget. Their evidence was successfully retained and exported; this is separate from the partial binary-decoding coverage above.
- Doctor found Codex registration but no configured native decompiler. The default shell Node 20 could not launch the CLI; using an existing newer Node launched diagnostics, which still reported an unsupported runtime version. No Node, compiler, decompiler or MCP configuration was installed or changed.
- No behavior after sunset, active server protocol, sync cryptography, DRM availability or complete extension compatibility was proved.

For a deeper function-level pass, establish a compatible Apple toolchain and configure one supported native decompiler. If using Ghidra for these universal binaries, first create a read-only arm64 slice in the analysis workspace and preserve its relationship to the original hash. Then trace small, named scenarios rather than attempting an indiscriminate full-app decompilation: command-bar dispatch, sidebar persistence, archive decisions, split creation, profile assignment and engine ownership. This work is useful follow-up; it is not a prerequisite for beginning a behavior-led independent implementation.

Rebuild your own implementation against upstream browser code. ArcCore is evidence for the needed boundary, not the engine binary to ship in the new product. Keep Arc assets and third-party bundled fonts out of the new browser's source and distribution.

## Deliverables and provenance

- `arc-package-evidence.json`: package versions, feature bundles, framework inventory and executable hashes from local read-only inspection.
- `arc-core-rea-evidence.json`: combined REA ledger containing both main-app metadata records and the ArcCore metadata record, including all reported coverage limits.
- `arc-rea-summary.json`: compact selected REA classes/selectors, counts, evidence identities and coverage status for review.

External sources were checked on 3 November 2026: [Arc sunset and export guidance](https://arc.net/), [Electron extension limitations](https://www.electronjs.org/docs/latest/api/extensions), [Chromium Mac build instructions](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md), [Chromium service API restrictions](https://www.chromium.org/developers/how-tos/api-keys/), and [CEF project documentation](https://github.com/chromiumembedded/cef). Architecture recommendations and milestone estimates are analyst judgments, not vendor promises.
