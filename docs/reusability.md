# Reusability: one skeleton, two apps

Skeleton Crew entry for Kiroween 2026. The skeleton is **OrigamiVerse Core**
(`shared-core/addons/origamiverse_core/`), a Godot 4 addon with no dependency on any app.

## What the core provides

| Area | Classes |
| --- | --- |
| Fold data | `OVFoldDocument` (FOLD format), `OVCreasePattern`, `OVTriangulator` |
| Simulation | `OVHingeSolver` (rigid panels), `OVBarHingeSolver` (compliant XPBD), `OVSpring` |
| Rendering | `OVPaperMesh`, `OVPaperPresets`, paper shader |
| Animation / edit | `OVTimeline`, `OVUndoStack` |
| IO | `OVExporter` (FOLD, OBJ, GLB), `OVSaveStore` (atomic write, backup, schema version) |
| Input / camera | `OVGestureTracker`, `OVOrbitCamera` |
| World | `OVCollisionSync`, `OVSurfaceNavigator` |
| Audio / UI | `OVPaperAudio` (synthesized, no audio files), `OVThemeFactory`, `OVUiKit` |
| Product | `OVFeatureGate` (entitlement checks) |
| Testing | `OVTestCase`, `OVTestRunner` (headless, exit code = failures) |

## How the two apps use it

| Capability | FoldShift (puzzle game) | PaperVerse (studio) |
| --- | --- | --- |
| Fold model | islands with hinge forests | user-drawn crease patterns |
| Solver | `OVHingeSolver` + puzzle rules + level solver | both solvers, adaptive substeps |
| Mesh | `OVPaperMesh` for islands | `OVPaperMesh` for the sheet |
| Navigation | `OVSurfaceNavigator` walks Kami over folds | not used |
| Timeline | not used | `OVTimeline` fold and spin channels |
| Export | not used | FOLD / GLB / OBJ via `OVExporter` |
| Persistence | `OVSaveStore` progress | `OVSaveStore` projects |

Both apps share paper rendering, folding math, undo, saves, audio and UI theme. Neither contains a copy
of the other's code.

## Rules that keep it reusable

- Core never references app scripts. Apps depend on core, never the reverse.
- The core has its own Godot project (`shared-core/`) and its own headless test suite.
- `python tools/sync_core.py` copies the addon into each app so every app opens standalone;
  `--check` fails on drift, and a Kiro hook syncs on save.
- Core classes use the `OV` prefix to avoid collisions.

## Adding a third app

1. Create `apps/<name>/` as a Godot project.
2. Add it to the target list in `tools/sync_core.py` and run the script.
3. Use `OVFoldDocument` plus a solver, `OVPaperMesh` for display, and `OVSaveStore` for saves.
4. Gate any paid feature through `OVFeatureGate.is_unlocked(feature_id)`.
