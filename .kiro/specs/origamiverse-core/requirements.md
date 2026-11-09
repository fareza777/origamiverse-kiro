# Requirements: OrigamiVerse Core

OrigamiVerse Core is the Godot 4 addon (`addons/origamiverse_core`) that both FoldShift and PaperVerse are built on.
It owns everything about paper: data, folding math, meshes, materials, input, audio, persistence and export.

## R1. FOLD data model
**User story:** As a developer, I want one in-memory model of the FOLD 1.2 format so both apps exchange paper data in
an open, documented format.

1. WHEN a FOLD JSON string is parsed THEN the core SHALL load `vertices_coords` (2D or 3D), `edges_vertices`,
   `edges_assignment`, `edges_foldAngle` and `faces_vertices`, plus `file_*` metadata and `file_frames`.
2. WHEN the document is serialized THEN the core SHALL emit valid FOLD JSON with `file_spec` 1.2 and
   `file_creator` set, and re-parsing it SHALL give an equal document (round trip).
3. WHEN a document is invalid (index out of range, mismatched array lengths, degenerate edge) THEN `validate()`
   SHALL return human-readable errors and never crash.
4. WHEN `edges_foldAngle` is missing THEN the core SHALL derive it from assignments (V = +180, M = -180, else 0).
5. WHEN faces are polygons with more than 3 vertices THEN the core SHALL triangulate them and mark the new
   diagonals as flat (`F`) edges.

## R2. Crease pattern editing model
1. The core SHALL hold an editable crease pattern as line segments with an assignment (M, V, F, C) on a square sheet.
2. WHEN segments cross or touch THEN planarization SHALL split them at intersections and merge vertices closer than
   a tolerance.
3. WHEN the pattern is converted to a FOLD document THEN every bounded face SHALL be extracted and triangulated,
   and the sheet border SHALL be `B`.
4. Snapping SHALL offer grid points, existing vertices, segment midpoints and 22.5° angle increments.

## R3. Rigid hinge folding (panel tree)
1. WHEN a document's faces are grouped into rigid panels joined by straight M/V hinges THEN the hinge solver SHALL
   compute each panel's world transform for any set of hinge angles, exactly and in O(panels).
2. Positive angles SHALL be valleys (child front turns toward parent front), negative SHALL be mountains, matching
   FOLD `edges_foldAngle`.
3. WHEN a panel folds by 180° THEN it SHALL sit one paper thickness above its parent so stacked paper never z-fights.
4. WHEN the hinge graph has a cycle or a non-collinear hinge THEN the solver SHALL report it instead of producing
   a wrong pose.

## R4. Compliant folding simulation (bar and hinge)
1. The core SHALL simulate arbitrary triangulated crease patterns with an XPBD bar-and-hinge model: edge length
   constraints, crease dihedral constraints targeting `foldAngle × fold_percent`, and stiffer facet constraints.
2. WHEN `fold_percent` changes THEN the mesh SHALL converge to the new pose within 1 second on the target device
   for patterns up to 400 triangles.
3. The simulation SHALL stay finite (no NaN) and report a strain metric per frame.
4. A user-chosen face SHALL stay fixed so the model does not drift.

## R5. Paper rendering
1. The mesh builder SHALL produce flat-shaded triangle meshes from solver output and update them every frame without
   reallocating when topology is unchanged.
2. The paper shader SHALL render distinct front and back colors, procedural fiber grain, and crease lines whose
   style depends on assignment (mountain, valley, facet, boundary), on both Mobile and Compatibility renderers.
3. Paper presets SHALL be available as data (name, front, back, grain, sheen).

## R6. Timeline animation
1. A timeline SHALL hold keyframes of named float channels with per-key easing and return interpolated values for
   any time.
2. Keyframes SHALL serialize to and from JSON.

## R7. Undo and redo
1. An undo stack SHALL record reversible actions with labels, support redo, cap history length, and emit a signal on
   change.

## R8. Persistence
1. Saves SHALL be JSON in `user://`, written atomically (temp file then rename) with a backup of the previous save.
2. WHEN the primary save is corrupt THEN loading SHALL fall back to the backup, then to defaults.
3. Saves SHALL carry a schema version.

## R9. Export
1. The core SHALL export a folded state as FOLD (with a folded-form frame), Wavefront OBJ, and binary glTF (GLB).

## R10. Touch input
1. A gesture tracker SHALL turn touch (and mouse for desktop QA) into tap, double tap, long press, one-finger drag,
   two-finger pinch and twist events with screen-density-aware thresholds.

## R11. Collision and navigation
1. Collision helpers SHALL keep physics shapes in sync with folded panels and folded meshes for ray picking.
2. A surface navigator SHALL build a walk graph over folded tiles, connecting tiles across flat, concave (floor to
   wall) and convex (over a ledge) edges, excluding covered or upside-down tiles, and answer shortest paths.

## R12. Audio and feel
1. The core SHALL synthesize its paper sound effects and ambient loops at runtime (no third-party audio files).
2. Volumes SHALL be controlled per bus (Music, SFX) and haptics SHALL be optional.

## R13. Monetization readiness
1. A feature gate SHALL answer `is_unlocked(feature_id)`; in this release it returns true for everything.

## R14. Quality
1. Every module above SHALL have headless unit tests that run with one command and return a non-zero exit code on
   failure.
