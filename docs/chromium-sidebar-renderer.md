# Stable sidebar projection and contextual editing

## Scope

This Aelo implementation follows the boundaries established by the
[Arc investigation](arc-sidebar-implementation.md), not recovered Arc source
or exact Arc geometry. The independent portable workspace model is unchanged.
The earlier binary uses the provisional renderer; this source revision requires
full linking and live qualification.

## Behavior specified before the full UI rebuild

- The header contains brand/Actions, Space selection and creation actions.
  Name and destination editors are absent from the normal browsing surface.
- Actions or a row context menu exposes Rename, Move, Pin, sibling ordering and
  forgetting a closed page/empty container. Live pages cannot be forgotten to
  bypass native close or beforeunload. Invalid/cyclic destinations stay excluded.
- Rename opens a bounded inline editor: Enter saves, Escape cancels and returns
  focus to a visible selected row. Cancel abandons the edit; a newly created
  empty folder remains a valid saved item.
- Move opens a bounded destination editor with Move/Cancel. Native title/loading
  updates preserve a still-valid chosen destination instead of resetting it.
- Each visited tree UUID owns one native row object. Title/selection updates
  update that row; collapse/Space changes hide rows without destroying them.
  Only removal of a model node destroys its cached row. Row order follows the
  ordered model, and the hierarchy alone scrolls.
- Rows use LabelButton keyboard/action support with plain native selection/hover
  backgrounds and a keyboard focus ring. They are not outlined MdTextButton
  pills. Existing minimum-height/padding policy is retained; no Arc-wide
  40-point row-height claim or guessed Arc geometry is introduced.
- Creating a page explicitly with + Tab reveals its destination. Session restore
  does not use that explicit action to change expansion state.
- Native navigation, profiles, session history and sandbox ownership stay in
  Chromium. No popup-state validator or security checks are changed.

## States and required live gates

| State | Required result |
|---|---|
| Selected / keyboard focused | One selected row; focus remains on the same UUID during unrelated refreshes |
| Hovered | Plain hover feedback, without pill borders or a header size change |
| Renaming | Typed text and cursor survive page-title/loading updates; Enter/Cancel/Escape behave as specified |
| Moving | Chosen destination survives unrelated updates; dropdown is bounded horizontally |
| Collapsed | Descendants hide, row identities remain cached; clean restart expansion test must exclude external input |
| Loading / title changed | Text updates without rebuilding all rows, resetting Move or reflowing header/dock |
| Dragging | Source/target lifecycle is observed; hierarchy does not mutate on invalid/descendant drops; native delivery still requires live evidence |
| Narrow / short window | Header and footer remain bounded, editors keep natural height, only the tree body scrolls |

Opt-in `--vmodule=aelo_workspace_header=1` records row create/remove, selection,
move, load/save collapsed counts and drag start/end/rejected-drop events. It
records UUIDs/counters, not names, page text or URLs. Correlate those events with
native UI and final profile snapshots; input-delivery errors do not establish a
source defect. Omnibox lifecycle logging remains available for any recurrence of
the separate unresolved fatal.

## Implementation checks

GN header checks passed for the vertical targets and the main UI target. The
changed header renderer and its frame consumer compiled successfully. All three
existing CTest suites passed. Patch 0002 reverse-application and source whitespace
checks passed; canonical model copies match. Patches 0001/0003 are unchanged.
The first object check used an incorrect frame-object path; the path was corrected
from generated ui.ninja. A missing MenuSourceType definition was corrected with
its explicit generated header. The final object checks passed.

Full linking and the live states above remain required. Model tests and changed
object compilation do not qualify this renderer. The old omnibox fatal remains
unresolved; no causal fix or stable-release claim is made.
