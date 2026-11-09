# Requirements: PaperVerse — 3D Origami Studio

A pocket origami lab: draw a crease pattern with your finger, watch it fold in 3D in real time, animate it, dress it
in paper, and export it to FOLD, GLB or OBJ. Built on the same OrigamiVerse Core as FoldShift.

## R1. Crease editing
1. WHEN the user drags on the crease canvas with a draw tool THEN a crease SHALL be added between the snapped start
   and end points (snap to grid, existing vertices, midpoints, intersections and 22.5° angles).
2. Tools: Mountain, Valley, Cut, Flat (reference line), Erase (tap a crease), Flip (tap to swap mountain/valley).
3. Grid density SHALL be selectable (4, 8, 16 divisions); two-finger pinch/pan SHALL zoom the canvas.
4. WHEN the pattern changes THEN the 3D model SHALL rebuild and refold within one second.
5. Creases that cannot split the paper SHALL be reported, not silently lost.

## R2. Real-time folding simulation
1. A fold slider (0–100 %) SHALL drive the compliant bar-and-hinge solver live.
2. A rigid mode SHALL fold tree-like patterns exactly with `OVHingeSolver`; the app SHALL explain when a pattern
   is not rigid-foldable.
3. Tapping a face in 3D (with the Pin tool) SHALL make it the fixed face.
4. Strain SHALL be visualized as a number so users can tell when paper is being forced.
5. The solver SHALL sleep when the model has settled to save battery.

## R3. Templates
1. At least 12 templates SHALL be available: procedural (half fold, accordion fan, Miura-ori) and classic patterns
   converted from the MIT-licensed Origami Simulator examples (bases, flapping bird, crane, twist).
2. Creating from a template SHALL produce an editable copy.

## R4. Animation timeline
1. Channels "fold" (0–1) and "spin" (turntable degrees) SHALL be keyframeable at the playhead with per-key easing.
2. Play, pause, loop and scrub SHALL drive the simulation in real time.

## R5. Materials
1. Paper presets from `OVPaperPresets` plus custom front/back colors SHALL be applied live.
2. Crease assignment colors SHALL be toggleable in 3D.

## R6. Undo, save, load
1. Every edit (crease, tool action, key, material, pin) SHALL be undoable and redoable.
2. Projects SHALL autosave as FOLD files with PaperVerse extensions in `user://projects`, with thumbnails.
3. Projects SHALL be renamable, duplicable and deletable from the home screen.
4. The user SHALL be able to import any FOLD file.

## R7. Export
1. FOLD (crease pattern + folded frame), GLB and OBJ+MTL of the current folded state, and a PNG snapshot.
2. On Android exports SHALL go through the system save dialog, with an in-app fallback folder.

## R8. Quality
1. Headless tests SHALL prove every template planarizes, simulates without NaN and stays under a strain threshold.
2. 30 FPS floor on the Redmi Note 11 for templates up to 400 triangles.
3. Offline, no account, no data collection.
