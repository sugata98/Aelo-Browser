# Arc sidebar implementation evidence and Aelo correction

## Scope and result

Inspected the installed `/Applications/Arc.app`, version 1.171.0 build 89666,
arm64. Main executable SHA-256:
`e82d2a4245b6239860e41a149cb31c0c030e35b383456544c81f21d45ee03376`.
This is a focused static reverse-engineering pass, not recovered original Swift
source or a claim of pixel/behavior parity. Arc was not launched or attached;
its personal profiles and running UI were not read. No Arc artwork/fonts were
copied into Aelo.

REA decoded native class/field/selector metadata and the compiled MainMenu nib.
Supplemental LLDB disassembly read two selected functions without running Arc.
The [compact evidence ledger](arc-sidebar-implementation-evidence.json) records
addresses, source identities, coverage and limitations. Full REA bundles remain
in ignored `.build/arc-sidebar-*-evidence-20261104.json` storage.

## What the shipped implementation establishes

| Area | Observed evidence | Consequence for Aelo |
|---|---|---|
| Hierarchy | `Arc.TablistOutlineDelegate` adopts `NSOutlineViewDelegate`; `TablistView` contains outline/scroll/column fields | Use a real hierarchical row renderer with persistent selection/expansion, not a collection of independent action buttons |
| Row cells | `SidebarTableRowView` subclasses `NSTableRowView`; delegate implements height, view, row-view, selection and expansion callbacks | Row geometry, selection and disclosure belong to one coordinated renderer |
| Header/body/dock | `SidebarViewController` has separate header, paging and dock controllers; header has top/bottom/spacing constraint fields | Keep chrome and dock bounded while the hierarchical body scrolls |
| State projection | `TablistViewController` has dataSource, snapshotViewStore, store and viewStore; outline delegate has localState, isUpdatingOutlineView and cellStoreSubscriptions | Aelo should preserve row identity and update affected rows. The exact Arc reducer/diff algorithm remains unknown |
| Sections | Separate UnpinnedSectionHeader/Divider cell classes and pinned-section menu actions | Saved hierarchy and temporary/unpinned tabs need distinct semantics and visual sections |
| Persistence | `RestoreSidebarDataFlow` contains sidebarStorableDataStore, windowsStore and restorableFiles; StorableSidebar has its own resource bundle | Sidebar organization is an independent domain, not a Chromium-group constraint |
| Drag lifecycle | `ARCUI.ArcDraggingSessionImpl` has source, activeDestination, active/source UI drivers, operation ID and lifecycle state; row has splitDropTargetDelaySatisfied | A stable drag session, visible destination feedback and explicit acceptance rules are required |
| Space navigation | Paging controller has spaceViewControllerCache, drag Space IDs, scroll position and pending scroll request; compiled next/previous Space actions exist | Space navigation and sidebar scrolling are coordinated independently of tab groups |

The compiled menu graph recognizes collapse/expand all folders, collapse/expand
pinned section, focus sidebar and next/previous Space actions. Their target
objects can be unresolved first-responder destinations. Encoded actions do not
by themselves prove the handlers' algorithms or runtime reachability.

## Geometry recovered, and what it does not mean

REA's metadata resolves `outlineView:heightOfRowByItem:` to `0x10034f81c`.
Static disassembly shows its call to `0x100355ae8`. The helper includes returns
of 0, 2, 16, 24 and a fallback double value of 40, plus a branch loading a
computed value from another function. Exact VM ranges, universal-file offsets
and byte digests are retained in the ledger.

This establishes item/state-dependent sizing. It does **not** identify each
branch's semantic row kind, prove every tab is 40 points high, establish folder
indentation, or measure runtime pixel bounds. Asset catalog icon sizes are also
not row heights. Full geometry, animation timing and responsive constraints
remain unmeasured. A clean Arc runtime fixture or deeper typed analysis is
needed before describing those values as exact.

The ABI distinction between stored-field metadata and runtime values follows
Swift's [reflection records](https://github.com/swiftlang/swift/blob/main/include/swift/RemoteInspection/Records.h)
and [reflection explanation](https://www.swift.org/blog/how-mirror-works/).
This pass observed compiled declarations, not an Arc store's live values.

## Why Aelo's current UI still differs

Aelo's portable tree now supports independent nesting and preserved UUIDs. That
is the useful domain boundary to retain. Its first renderer remains provisional:

- `AeloWorkspaceHeader::Refresh` calls `rows_->RemoveAllChildViews()` and rebuilds
  all rows; it also replaces picker models and resets the move destination.
- Every row is an MdTextButton inside a FlexLayout stack. Persistent Rename,
  Remove, destination and Move controls consume the main sidebar surface.
- Folders are represented by parent links, but row focus/selection, inline edits
  and updates are not managed by a coordinated outline/table renderer.
- Every closed page remains saved. Arc-style temporary/Today versus saved-pin
  behavior is not implemented.

These are Aelo source observations, not claims that Arc uses a particular diff
algorithm. The observed Arc components support a different architecture than
the current button stack. The user's report of unstable layout is consistent
with the actual Move-row flex regression found in live testing.

## Implementation direction from this evidence

Keep the tested portable model and browser-owned navigation/profile boundaries.
Replace the provisional renderer with a stable hierarchy/selection controller
and dedicated row cells. Keep a compact header and bounded Space dock; let only
the tree body scroll. Put edits and moves in contextual/inline UI rather than
permanent toolbar rows. Preserve row identity and editor state during page-title
and loading updates. Model saved pinned hierarchy separately from temporary
pages. Add a drag-session object with visible drop feedback and cycle-safe,
transactional moves. These are Aelo design decisions guided by evidence, not
verbatim recovered Arc source.

Before the next UI build, specify and exercise selected/hovered/editing/collapsed/
loading/dragging states and narrow/short-window layouts. Verify that navigation
updates cannot reflow the header/dock or discard a focused row/editor. Do not
repeat a whole browser link merely to try another unmeasured spacing value.

## Coverage and open questions

- REA metadata record: `ev_6fd7d6d0da42099558938fd3cfab2a2f0464cf8bcf36b6569584d49e8a950ed3`.
  It retains 852 Objective-C class/metaclass rows and 2,884 method dispatch rows;
  these are record counts, not unique classes/features.
- Compiled UI graph: `ev_f9fd64fbdf759bb2d0aa09e100e1e261c41745d1ac72cb2f60f24e8227596736`;
  selected MainMenu nodes: `ev_57e7fe78d29d63a9f5b01d96aeb70a8f9d1d9ca51d7e58cb9c47bb72a5f99951`.
- Native class/relative-pointer analysis is partial at the tool's 20,000-record
  ceiling. Swift nominal/witness/vtable decoding exhausted that budget before
  producing declarations; zero decoded declarations does not mean absence.
- REA reports no configured Ghidra, Hopper, IDA or Kuna provider. No original
  source, complete pseudocode, complete call graph, exact storable schema or
  full folder/drop algorithm was recovered.
- Hierarchical renderer/controller boundaries: answered by metadata. Exact
  geometry: partially answered. Folder storage/reducer and drop semantics:
  partially answered by fields/actions; algorithm unresolved. Live Arc layout
  and interactions: not observed in this pass.

The Aelo browser's later omnibox popup-state fatal is a separate observed
stability failure. Source review identifies candidate state synchronization
paths, but not a proved cause. Keep the validator enabled and capture the
Show/Hide/visibility/focus sequence before changing behavior. Successful tree
persistence must not be reported as full stable-browser qualification.
