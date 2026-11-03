# Full Chromium workspace UI port

## Status — 3 November 2026

The first full Chromium fork build and disposable-profile launch passed before
this change. The launched browser used upstream Chromium window controls, not
the existing AppKit workspace shell. This port is under compilation; the new UI
has **not yet passed a full build or live interaction checks**.

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
  Live session/Space restoration still needs verification.

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
- Retry uses python3 scripts/build_chromium.py build --jobs 18 with the verified
  Metal toolchain. Log: ignored .build/chromium-build-workspace-retry.log.

Required live gates: new-tab appearance; create, edit and switch two Spaces;
new-tab membership while focused; All tabs escape; pin/unpin behavior; split
creation and navigation; close/reopen; sidebar collapse; quit/relaunch session
restoration; separate-profile isolation; renderer sandbox. Use disposable
--user-data-dir only and retain evidence in docs after actual verification.
