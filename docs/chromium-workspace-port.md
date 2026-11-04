# Full Chromium workspace UI port

## Status — 4 November 2026

The first full Chromium fork build and disposable-profile launch passed before
this change. The launched browser used upstream Chromium window controls, not
the existing AppKit workspace shell. The new workspace UI passes the full chrome target build and the basic live
workspace checks below, using disposable Chromium profiles.

## Current implementation

- Native Views vertical tabs are enabled by default, initially 248 points wide.
  Explicit existing vertical-tab preferences are respected.
- Aelo heading, Space picker, Space creation/editing, and Search/Code/Read links
  sit above the native tab list. Collapsing the sidebar hides the workspace
  header while retaining Chromium's collapsed tab controls.
- A Space is currently a Chromium tab group in the current window. The picker
  enters native group focus mode. All tabs exits focus mode and exposes tabs
  outside Spaces. Existing groups are also listed; no pre-existing tabs are
  moved or closed automatically. The first two newly created Spaces are named
  Personal and Focus. Edit opens the native group name/color editor.
- Native tabs retain their own navigation, loading/audio indicators, pinning,
  context menus, drag handling, and extension integration. This port does not
  create parallel WebContents or virtualize browser process ownership.
- The footer routes Split, Reopen, and Profiles through Chromium's command
  controller. Availability is checked before execution. Profiles opens the
  native profile control; a Space does not create a separate cookie store.
- The original script-free Aelo home design is packaged as Chromium's new-tab
  HTML resource. It uses system fonts and the existing artwork/CSS from
  resources/home.html. Browser URL handling, extension new-tab overrides, CSP,
  certificate checks and renderer sandbox settings are not changed.
- The default macOS startup mode resumes the previous session, using Chromium
  session persistence. Explicit user startup choices and policy take priority.
  Live session/Space restoration passed the controlled quit/relaunch check.

## Storage and migration boundaries

The existing engine-independent src/Workspace.mm model, its JSON contract,
AppKit shell, and CEF profile directories are unchanged. This first adapter
uses Chromium's group/session data rather than importing or overwriting
workspace.json. No personal profiles have been inspected or imported.

Chromium Profiles remain the isolation boundary. Spaces in a profile share
cookies, history and extensions. A different profile uses a separate Chromium
Profile, normally in its own native window. The full fork retains its separate
Aelo/Chromium data root and Aelo Safe Storage keychain namespace.

The original model's persistent empty Spaces, per-Space pins, Space dock,
archive semantics, cross-window organization and direct CEF workspace import
are not yet bridged. Native pins currently remain profile/window tab-strip
pins, visible across focused groups. Closing a group's final tab removes that
live group. These differences must not be described as full workspace parity.
Nested folders, Arc import, extension compatibility qualification, and the
previous CEF watchdog regression remain separate unfinished work.

## Validation

- Ten build-tool tests passed.
- Existing native workspace regression executable passed persistence, Profile
  mapping, archive recovery, corruption fallback, validation and URL handling.
- Workspace patch reverse-application check passed against the pinned checkout.
- Initial compile stopped on forbidden ScopedObservation<TabStripModel,...>:
  Chromium now manages observer lifetimes in TabStripModelObserver itself.
  The adapter was corrected to AddObserver and native automatic removal.
- Full retry completed successfully with --jobs 18 and the verified Metal
  toolchain. Driver state is action_completed/build; both workspace header and
  region view objects and the real application executable exist. Log: ignored
  .build/chromium-build-workspace-retry.log.
- The label-fix rebuild completed successfully on 4 November at 02:03 UTC,
  with 18 jobs and zero remaining build steps. The ignored log is
  .build/chromium-build-workspace-label-fix.log.
- Agent-shell GUI launch cannot register Crashpad Mach ports. REA provided an
  ordinary-user launch; no security-disabling flags or injected scripts were
  used. Native UI actions were checked through computer use, with read-only
  CDP diagnostics for page, process and profile evidence.

## Launch regression found on 4 November 2026

REA process capture ran the exact Aelo executable under ordinary user
permissions, with a disposable profile. It reached DevTools and the native
window paint loop, then exited with SIGABRT after about one second:

`FATAL:ui/views/controls/label.cc:955 DCHECK failed: view->layer()->fills_bounds_opaquely()`

Evidence: `ev_943872bb7c5f34a0b661ef322a82fbdf795b251a1d78a31eb9aaf828838c45c8`.
The complete bounded capture is retained in ignored build storage at
`.build/chromium/rea-workspace-label-crash.json`. Capture output was truncated
at its configured budget; the fatal condition, paint stack and SIGABRT were
observed. This is a new UI regression, separate from the shell's Mach-port
restriction. A normal user launch of the same build would also hit this check.

The sidebar's new labels used subpixel text on the vertical strip's transparent
composited layer. They now use grayscale text rendering, including the new
button labels. The opacity invariant remains enabled. The footer also keeps
New Tab at its preferred height and uses a dedicated spacer to position the
profile/split controls at the bottom. The rebuilt app passed first paint and the live checks below. The observed
label-paint startup regression is resolved in this build; broader stability
is not established by these checks.


## Live qualification — 4 November 2026

The disposable run verified the original home page and native sidebar; creation,
editing and switching of Personal and Focus; focused Cmd+T membership; All tabs;
pin/unpin; close/Reopen; independently navigable split panes; and sidebar
collapse/expand. Pinning removes a tab from its Space into native global pins.

Personal and Focus shared a synthetic cookie in Default. A separate regular
Profile 1 showed an empty cookie store at the same fixture origin. Both profile
paths and the built executable were verified through chrome://version. All 14
observed renderers and the GPU returned sandbox_check=1, errno=0; the browser
broker returned 0. No browser protection was disabled.

A normal application Quit closed the endpoint and recorded exit_type=Normal.
Relaunch with the same disposable root and no startup URL restored Personal
selected, both Spaces, tabs and split membership. The browser was left open on
Personal with the original home page.

One earlier verification process disappeared unexpectedly; its cause was not
established. Recovery restored the synthetic session, and the later controlled
normal quit/relaunch passed. This does not establish long-term stability or
resolve the separate CEF shutdown watchdog. Distribution resource-seal signing,
embedded revision provenance and broad extension compatibility remain open.

See [structured evidence](chromium-workspace-launch-evidence.json) and the
[home page capture](chromium-workspace-home.png). The PNG captures page content
only; native sidebar and interaction results came from live UI inspection.
Runtime logs and disposable profiles remain excluded from Git.
