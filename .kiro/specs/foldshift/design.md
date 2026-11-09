# Design: FoldShift

## Layers

```
levels/*.json ──► FSLevelData ──► FSPuzzle (pure logic, no nodes) ──► FSWorld (3D view + input)
                                     ▲                                     │
                                     └──── FSSolver (tests, par) ◄─────────┘ same rules, same core solvers
```

`FSPuzzle` is the single source of truth for rules. The game and the solver both call `try_fold()` and
`walk_to()`, so a level that the solver proves solvable is solvable in the game by construction.

## Level format

```json
{
  "id": "c1_l2", "chapter": 1, "title": "Two Steps", "hint": "...", "par": 2,
  "islands": [
    {"origin": [0, 0, 0], "rows": [". . a", ". . a"]}
  ],
  "flaps": {"a": {"hinge": "W", "angles": [180, 0], "start": 180, "parent": "."}},
  "start": [0, 0, 0], "goal": [1, 0, 2],
  "cranes": [[0, 1, 1, "front"]],
  "seals": [{"at": [0, 1, 0], "unlocks": "a"}]
}
```

- `rows`: one character per cell (spaces between cells are ignored). `.` base paper, `a`-`z` flap cells,
  `_` empty. Row r runs along +Z, column c along +X; cell (r, c) covers x ∈ [c, c+1], z ∈ [r, r+1].
- Each island becomes one `OVFoldDocument`: grid vertices, 2 triangles per cell, `F` edges inside a panel, `V`
  hinge edges on the flap's `hinge` side (N/S/E/W = side where its parent is), `C` cuts elsewhere, `B` boundary.
  `OVHingeSolver.build()` turns it into a panel tree.
- Coordinates in `start`/`goal`/`cranes`/`seals` are `[island, row, col]`.

## Rules (FSPuzzle)

- State: flap angle index per flap, Kami's node (tile × side), unlocked flaps, collected cranes, fold count.
- `try_fold(flap, index)`: rejected if locked; if Kami rides the flap subtree her node must stay walkable after the
  fold; if she does not ride it, her node must not become covered. Otherwise accepted, fold count +1.
- `walk_to(node)`: path via `OVSurfaceNavigator`; seals and cranes on the path are applied in order.
- Won when Kami's tile is the goal tile.

## Solver (FSSolver)

0-1 BFS over `(angles, node, unlocked)`. Walking costs 0, folding costs 1. Navigation graphs are cached per angle
configuration. Output: par, a solution move list, and the set of collectible cranes.

## Presentation (FSWorld)

- One `MeshInstance3D` per island fed by `OVPaperMesh.update_from_hinge_solver()`; flap panels use a second
  material (two-tone paper) so players can read what moves.
- Tile pick bodies via `OVCollisionSync.make_tile_body()`, re-synced each frame while a flap moves.
- Drag-to-fold: on drag start the picked tile's panel hinge is grabbed; each frame θ is chosen from the allowed range
  (2° samples, then refined) to minimize screen distance between the rotated grab point and the finger.
- Kami (GLB from Blender) hops tile to tile, aligning her basis to the surface normal.
- Camera rig: yaw/pitch/distance springs (`OVSpring`).

## Screens

Title → Chapters → Levels → Game (HUD, pause, complete) plus Settings and Achievements, all built from
`OVThemeFactory`.
