# Design: OrigamiVerse Core

## Reference study and licenses

| Project | License | What we learned | What we adapted |
| --- | --- | --- | --- |
| [edemaine/fold](https://github.com/edemaine/fold) | MIT | FOLD 1.2 spec: field names, assignment letters (B M V F U C J), `edges_foldAngle` in degrees with valley positive, `file_frames` for folded states. | The data model and JSON field names. No code copied; our parser is written in GDScript. |
| [amandaghassaei/OrigamiSimulator](https://github.com/amandaghassaei/OrigamiSimulator) | MIT | Bar-and-hinge model: axial bars, crease hinges driven to `foldAngle × percent`, stiffer facet hinges, wing/edge gradient split. | The physical model. We reformulated it as XPBD (position based) so it converges in ~12 iterations per frame on a phone CPU instead of hundreds of explicit GPU steps. |
| [ELF32bit/godot-folder](https://github.com/ELF32bit/godot-folder) | MIT | A Godot 4 FOLD prototype. Its GPU path uses `RenderingDevice` compute (unavailable on the Compatibility renderer, so unusable on many Android GPUs) and its own notes call the CPU fallback "not very stable". Its CPU loop uses `Dictionary` lookups with `Array` keys per edge per step. | The idea of storing FOLD in a graph class and building meshes from it. We replaced the solver and used packed arrays with precomputed index buffers. |

All three are MIT, compatible with our MIT license. Attribution is in `THIRD_PARTY_NOTICES.md`.

## Module map

```
addons/origamiverse_core/
  ov_core.gd                     version, constants, coordinate mapping
  fold/ov_fold_document.gd       OVFoldDocument  (R1)
  fold/ov_triangulator.gd        OVTriangulator  (R1.5)
  fold/ov_crease_pattern.gd      OVCreasePattern (R2)
  sim/ov_hinge_solver.gd         OVHingeSolver   (R3)
  sim/ov_bar_hinge_solver.gd     OVBarHingeSolver (R4)
  sim/ov_spring.gd               OVSpring (critically damped tween for angles)
  render/ov_paper_mesh.gd        OVPaperMesh     (R5.1)
  render/paper.gdshader          paper shader    (R5.2)
  render/ov_paper_presets.gd     OVPaperPresets  (R5.3)
  anim/ov_timeline.gd            OVTimeline      (R6)
  edit/ov_undo_stack.gd          OVUndoStack     (R7)
  io/ov_save_store.gd            OVSaveStore     (R8)
  io/ov_exporter.gd              OVExporter      (R9)
  input/ov_gesture_tracker.gd    OVGestureTracker (R10)
  world/ov_collision_sync.gd     OVCollisionSync (R11.1)
  world/ov_surface_navigator.gd  OVSurfaceNavigator (R11.2)
  audio/ov_paper_audio.gd        OVPaperAudio    (R12)
  meta/ov_feature_gate.gd        OVFeatureGate   (R13)
  ui/ov_theme_factory.gd         shared premium UI theme + fonts
```

## Coordinates

FOLD uses right-handed (x, y, z) with the sheet in the xy plane, front facing +z. Godot is Y-up.
`OVCore.fold_to_godot(x, y, z) = Vector3(x, z, -y)` is a proper rotation (determinant +1), so counter-clockwise
faces in FOLD stay counter-clockwise seen from +Y and the paper front faces +Y.

## OVFoldDocument

Packed storage: `vertices: PackedVector3Array` (Godot space), `edges: PackedInt32Array` (pairs),
`assignments: PackedByteArray` (enum), `fold_angles: PackedFloat32Array` (degrees), `faces: Array[PackedInt32Array]`,
`meta: Dictionary`, `frames: Array[Dictionary]`. Derived caches (`edge_index(u, v)`, face adjacency) are built on
demand and invalidated by `touch()`.

## OVHingeSolver (rigid)

1. Union-find faces across `F` edges into panels. `M`/`V` edges between two panels form a hinge; all its edges must be
   collinear. `C`/`B` edges join nothing.
2. BFS from the root panel builds a spanning tree. A non-tree hinge means a cycle (reported, R3.4).
3. Each hinge stores pivot `a`, unit axis `u` oriented so `u × d = n` where `d` points from the hinge into the child and
   `n` is the parent's front normal. Then a positive rotation by θ about `u` turns the child toward the parent's front,
   which is the FOLD valley convention.
4. Thickness: the pivot is lifted by `sign(θ) · t/2` along `n`. Rotating 180° about a lifted axis lands the child exactly
   `t` above the parent. At θ = 0 the rotation is the identity, so the lift causes no jump.
5. `T_child = T_parent · Rot(pivot, u, θ)`; evaluated top-down each update.

## OVBarHingeSolver (compliant, XPBD)

State `x`, `v`, inverse mass `w` (0 for the pinned face). Each substep:
`p = x + v·dt`; for K iterations project constraints; `v = (p − x)/dt · damping`; `x = p`.

- Bar: `C = |p_i − p_j| − L0`, compliance `α_bar`.
- Hinge on edge (a, b) with wings c (tri 1) and d (tri 2): `θ = atan2((n1 × n2)·ê, n1·n2)`,
  `∇c = n1/h1`, `∇d = n2/h2`, `∇a = −(1−s1)∇c − (1−s2)∇d`, `∇b = −s1∇c − s2∇d`, where `h` is the wing height and `s`
  the projection parameter of the wing onto the edge. The split makes the gradient translation and rotation invariant.
  Target `θ0 = foldAngle·percent` for M/V (compliance `α_crease`), `0` for F (compliance `α_facet`, 50× stiffer).
- The angle is unwrapped against last frame's value so targets near ±180° do not flip.
- All topology lives in `PackedInt32Array` built once in `setup()`. Per frame cost is O(edges × iterations).

## OVPaperMesh

One surface, unshared vertices (flat shading), `cull_disabled` shader. Per vertex: `UV` = sheet coordinates (grain),
`UV2` = barycentric (edge distance for crease lines), `COLOR.rgb` = crease code of the edge opposite each corner.
Codes: 0 none, 0.25 facet, 0.5 valley, 0.75 mountain, 1.0 boundary/cut. Position and normal buffers are rewritten in place
through `RenderingServer.mesh_surface_update_vertex_region` when topology is unchanged.

## OVSurfaceNavigator

Input tiles: id, center, unit normal, 4 corners. A node is (tile, side ±1) with surface normal `s·n`. Nodes are walkable
when `normal·up > −0.25` (floors and walls, never ceilings) and not covered (another tile lies parallel within 2.5
thicknesses above it with overlapping footprint). Two nodes on tiles that share an edge midpoint (within tolerance)
connect when, with `dA`, `dB` the in-plane directions from the edge into each tile:

- flat: `nA·nB ≈ 1` and `dA·dB ≈ −1`
- concave (floor → rising wall): `nB ≈ dA` and `nA ≈ dB`
- convex (over a ledge): `nB ≈ −dA` and `nA ≈ −dB`

Paths come from `AStar3D` rebuilt only after a fold settles.

## Error handling

Parsing and validation return `OVResult`-style dictionaries (`ok`, `errors`, `value`) rather than asserting, because
PaperVerse imports user files.

## Testing strategy

`shared-core/tests/` contains one test file per module plus `run_tests.gd`, a minimal runner that discovers
`test_*` methods, counts assertion failures and quits with that count as the exit code.
