# Independent folder sidebar

## Status — 4 November 2026

The layout-fix full Chromium build succeeded (commit 221d813). A fresh
synthetic-profile run verified a visible hierarchy, Projects > Research >
Sources, a real page and pin inside Sources, expand/collapse, sibling Down
ordering, and Move to the displayed root destination. A clean normal quit and
no-URL restart preserved the exact 10-node tree including UUIDs, ordering,
pins, an empty folder and an empty Space. Profile 1 had independent tree data
and an empty fixture cookie while Default retained its synthetic cookie.
Five observed renderers and the GPU were sandboxed.

Qualification is incomplete. Drag/non-default picker interactions were blocked
by native-control capture/window errors. A later profile/window/new-tab typing
sequence crashed in Chromium's omnibox popup-state validator. The cause is
unestablished, and stability is not qualified. See the latest findings below.
The user's requested [Arc implementation investigation](arc-sidebar-implementation.md)
now guides replacement of the provisional button-stack renderer.

## Organization and browser ownership

`chromium/workspace/aelo_workspace_model.h` defines an engine-independent ordered
forest of Spaces, folders and pages. Spaces are roots. Folders can contain other
folders and pages, to a maximum validated depth of 128. Page UUIDs are independent
of URLs, Chromium groups, tab indexes and transient session IDs. Duplicate URLs
remain distinct pages. Empty folders and Spaces are represented explicitly.

The native Views sidebar renders this tree instead of the expanded Chromium tab
list. Chromium's native strip remains available when collapsed and its controller
continues to own live tabs. The tree never creates a second browser engine or
replaces WebContents, permission prompts, session history, split ownership or
Profile isolation. A page row selects an existing tab in the same Profile, or
opens its saved URL when it has no live tab. Saved-page reopening permits HTTP,
HTTPS, the built-in new tab and about:blank; it does not execute arbitrary saved
schemes. Existing live internal pages can still be selected normally.

A page is a saved sidebar item: closing its live tab leaves the item available to
open again. Remove can forget a closed page or an empty container. It cannot
silently delete a populated subtree or close a live page and bypass beforeunload.
This is not yet Arc's separate Today/auto-archive/closed-pin behavior.

## Controls

- Select a Space, then use + Folder to create a folder at its root. Select a
  folder and use + Folder again to nest another folder inside it.
- Select a folder or page, edit its name, then press Rename.
- Click a folder to expand/collapse it. New folders and moves expand the parent.
- + Tab creates a native tab in the selected folder (or beside the selected
  page). Cmd+T tabs are adopted into the current tree location on observation.
- Pin changes the saved page's own pin flag; it does not move the page out of
  its folder or depend on Chromium's global pin constraint.
- Drag into a container's middle to nest. Drag to a row's top/bottom quarter to
  reorder siblings. The visible Space-root row allows moving back to the root.
  Drag payloads are scoped to the originating sidebar, not external strings.
- Move and its destination picker provide a keyboard-accessible alternative to
  nesting. Up/down buttons reorder the selected item among its siblings.
- Split, Reopen, profile switching and the collapsed tab strip continue using
  Chromium's own browser commands.

## Persistence and preservation

The profile-local `aelo.workspace_tree` dictionary stores version 1, active Space
and ordered node records (parent UUID, kind, title, URL, pin, expansion and custom
name flag). Chromium PrefService writes the profile preferences; the prior valid
snapshot is also retained in `aelo.workspace_tree_backup`. Invalid versions,
duplicate IDs, dangling parents, cycles, page parents, nested Spaces and excessive
depth are rejected. An invalid primary tree is preserved and shown as requiring
recovery; this implementation does not automatically overwrite it with defaults.

Native session rebuild, tab restore and Reopen records carry the page UUID as
`aelo.workspace_page_id`. WebContents replacement retains that identity. Native
session restore retains navigation/session behavior; the workspace retains
organization even when a page is not currently open. Unrecognized native groups
are adopted as independent named Spaces when their pages are first encountered;
the native group records are preserved, and later tree changes do not edit them.

Each Chromium Profile has its own tree and cookie store. Spaces within one
Profile share browsing data. No cross-profile move destination is exposed.
Incognito uses its off-the-record preference overlay rather than writing this
tree to the original Profile. Private-mode persistence behavior still needs live
qualification.

The legacy CEF `src/Workspace.mm`, workspace.json and profile directories are
unchanged. No personal Arc or browser profiles are read or imported. The original
CEF data model and this portable C++ tree are not yet bridged.

## Verification

Passed: standalone model tests for nested folders (100 levels), order changes,
subtree moves between Spaces, duplicate URLs, Unicode titles, pins, expansion,
empty containers, snapshot round-trip, rejected cycles/dangling IDs/invalid kinds/
excessive depth and preservation of the last valid in-memory model. All three
CTest suites passed, including the existing workspace suite and ten build-tool
tests. Chromium header dependency checks and changed-object compilation passed.
The patch reverse-application check passed; 0001 and 0003 are unchanged.

The bounded live passes and later failure are recorded below. Remaining gates:
drag nest/reorder and rejected descendant move; non-default keyboard Move
selection; deliberately collapsed-state restart; native Reopen identity and
restored-tab binding; same-profile Space cookie sharing in this tree build;
and stability through profile/window/new-tab transitions. Separate-profile
isolation and the observed renderer sandbox passed in the disposable run.
Use fresh disposable data only.

No Arc import, model bridge, undo/redo, Today auto-archive, full cross-window drag,
full extension compatibility or complete Arc parity is claimed. The CEF shutdown
watchdog, distribution resource seal and embedded source-revision provenance
remain separate work.


## First live layout regression

The 4 November run used /private/tmp/aelo-folders-46kyhdxr. The home page was
painted and the + Folder action created a valid parent-linked record in
Default/Preferences. Native AX and screenshot showed Move controls occupying
the remaining height with no visible tree rows. Folder interaction is therefore
not qualified. A normal application Quit closed the test endpoint; no personal
data or browser protection was changed. The fix also guards against selection
of a Space removed by another window while its menu is open.


## Later live results and failure

Disposable root: /private/tmp/aelo-folders-fixed-xkkkx2r1. On clean Quit,
Default/Preferences recorded exit_type Normal. The complete workspace tree
before and after no-URL restart compared equal, with no new page UUIDs. An
empty Empty Space was selected after restart. Saved on-disk data and live
native state, not model snapshots alone, establish this bounded result.

Native-control coordinate/drag calls returned noWindowsAvailable and some
captures failed with ScreenCaptureKit -3811. AX button actions still supported
folder creation/renaming, collapse/expand, pinning, sibling reordering and Move
to the displayed default destination. No drag or non-default-picker pass is
claimed. Collapse-state persistence itself was not compared in a deliberately
collapsed final snapshot.

A later process (21668) exited after profile/window transitions, +Tab and URL
input. The log .build/chromium-folder-restart.log records a fatal at
location_bar_view.cc:1986: kClassic popup state with classic=0, aim=0 while the
omnibox had focus. The stack is in omnibox key/popup validation, with no Aelo
sidebar frame. This does not establish causality. Source review found an
unconditional kClassic publication after presenter Show and a possible external
native visibility synchronization gap; both require lifecycle evidence before
fixing. No validator, sandbox or security check was disabled. The disposable
profile marked Crashed after this later failure; this does not erase the earlier
separately verified normal shutdown/restoration result.

The native-control recovery opened an incidental blank default window after
that test process exited; the blank window was closed normally, and no personal
content was used for testing. Do not call getApp unless the disposable endpoint
is confirmed live. The browser is not left open as a qualified stable build.


## Omnibox lifecycle diagnostic build

The next build adds opt-in VLOG(1) events for popup appearance decisions,
Show return values, presenter Show/Hide/Close, state-manager transitions and
native widget visibility. The events correlate object pointers and booleans;
they do not log URLs, queries, titles or page content. They neither change popup
behavior nor suppress the existing validator. Enable only in a bounded
disposable-profile reproduction with:

```text
--enable-logging --vmodule=omnibox_popup_view_webui=1,omnibox_popup_presenter_base=1,omnibox_popup_state_manager=1,widget=1
```

Compare the same manager/presenter/widget through show-return, visibility and
state transitions before choosing a fix. A failed immediate Show and an external
hide after a successful Show remain separate hypotheses. Patch reverse-application
and whitespace checks passed. Compilation and reproduction are pending; this
is diagnostic instrumentation, not a causal fix or a stability pass.


## Diagnostic build and bounded non-reproduction

Commit a9fd1c1 built successfully, with zero remaining steps. The four changed
translation units compiled. The original bundle launched with a fresh disposable
profile at /private/tmp/aelo-popup-lifecycle-ndgwycka. A finite two-profile,
multiwindow, new-tab, active-popup profile-switch and window-close sequence did
not reproduce the original fatal. The pre-quit log contains 150 lifecycle events,
including 23 Show returns, all open=true, and no fatal lines. This does not prove
that either suspected path caused the earlier failure. Logging and UI timing may
affect a race. No popup behavior or validation fix has been applied.

Normal menu Quit closed CDP; both Default and Profile 1 recorded Normal exit.
All 13 observed renderers and the GPU were sandboxed (1, errno0), broker0.
The next reproduction should cover restored sessions, not treat this finite
fresh-session run as a stability pass. See
[diagnostic evidence](chromium-omnibox-lifecycle-evidence.json).

Target-binding correction: CUA initially selected an older default-instance
process despite the diagnostic endpoint being live. Its blank tabs received a
synthetic fixture navigation and one additional blank tab before the mismatch
was detected. Those actions are excluded from this diagnostic result. No personal
page contents or profile files were inspected. Normal menu Quit retired that
incidental instance, then a process inventory confirmed the sole Aelo process
was the disposable target. Subsequent UI actions matched CDP and the diagnostic
log. Future runs must verify this correlation after the first native action; a
live CDP endpoint alone does not prove CUA selected the same process.
