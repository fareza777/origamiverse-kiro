# Design: PaperVerse

## Layers

```
PVProject (pattern + timeline + material + pin)  ──►  OVCreasePattern.to_document()  ──►  OVFoldDocument
        │ save/load as FOLD (+ "paperverse:*" keys)                                      │
        ▼                                                                                ▼
PVProjectStore (user://projects)                                  PVFoldView: OVBarHingeSolver | OVHingeSolver
                                                                              OVPaperMesh + paper.gdshader
PVCreaseCanvas (2D editor) ── edits through OVUndoStack ──► PVStudio (screen) ──► OVTimeline drives fold/spin
```

## Screens

- **Home**: new blank sheet, template gallery (live crease-pattern previews), project grid with thumbnails,
  import FOLD, about/privacy.
- **Studio** (portrait): top bar (back, name, undo, redo, export), 3D fold view, bottom tab panel:
  *Crease* (canvas + tools), *Fold* (slider, mode, pin, stats), *Animate* (timeline), *Paper* (materials).

## Project file

A valid FOLD 1.2 document (the planarized, triangulated pattern) plus:

| key | content |
| --- | --- |
| `paperverse:name` | project name |
| `paperverse:pattern` | `OVCreasePattern.to_dict()` (the editable source lines) |
| `paperverse:timeline` | `OVTimeline.to_dict()` |
| `paperverse:material` | preset dict with colors |
| `paperverse:view` | fold percent, pin face, mode, show assignment |

Other tools can open the file as plain FOLD; PaperVerse restores the editable lines from `paperverse:pattern`.

## Simulation scheduling

`PVFoldView` steps the solver in `_process`. Substeps adapt to keep the solver under ~7 ms per frame
(measured with `Time.get_ticks_usec`). When `crease_error_degrees() < 0.5` and the mesh moved less than 1e-4 for
20 frames, the view sleeps until fold percent, pattern or pin change.

## Export path

`OVExporter` produces bytes/text; `PVExport` writes them through `DisplayServer.file_dialog_show` (native dialog;
Storage Access Framework on Android). If native dialogs are unavailable, files go to `user://exports` and the UI
shows where.
