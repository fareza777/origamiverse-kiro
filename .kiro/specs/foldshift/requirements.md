# Requirements: FoldShift — Origami Puzzle Adventure

Kami, a small paper fox, crosses floating paper islands. The player folds the world itself: flaps of paper
swing on real hinges to become bridges, walls Kami can walk up, ramps over ledges, and covers that hide or reveal
secrets. Built entirely on OrigamiVerse Core.

## R1. Folding interaction
1. WHEN the player drags a flap THEN the flap SHALL rotate about its hinge in real time so the grabbed point follows
   the finger (direct manipulation), computed by `OVHingeSolver` every frame.
2. WHEN the finger lifts THEN the flap SHALL spring to the nearest allowed angle for that flap.
3. WHEN the resulting fold breaks a rule (locked flap, would crush Kami, would leave Kami on a ceiling) THEN the flap
   SHALL spring back, the move SHALL not count, and the game SHALL give visual, audio and haptic feedback with a
   short reason.
4. A valid fold that changes the angle SHALL count as one fold.

## R2. Movement and gravity
1. WHEN the player taps a tile Kami can reach THEN Kami SHALL walk the shortest path from `OVSurfaceNavigator`.
2. Kami SHALL walk across flat seams, up walls (concave edges) and over ledges (convex edges); Kami's up vector SHALL
   follow the paper normal ("gravity follows paper").
3. WHEN a tile is unreachable THEN the game SHALL show a soft "can't reach" cue instead of moving.
4. WHEN Kami stands on a flap that folds THEN Kami SHALL ride the flap.
5. Reachable tiles SHALL be hinted with a subtle highlight while Kami is idle.

## R3. Puzzle elements
1. Bridges: flaps unfolding across gaps.
2. Walls and ledges: 90° folds linking islands at different heights.
3. Secrets: paper cranes printed on the back of flaps, visible only once folded face up.
4. Seals: stepping on a wax seal unlocks the flap with the matching color.
5. Goal: a paper lantern; reaching it completes the level.

## R4. Progression
1. 3 chapters with 5 levels each (15 levels), each chapter with its own environment and ambience.
2. Levels unlock in order; chapters unlock when the previous chapter is cleared.
3. Each level SHALL have a par (minimum folds) computed by the automated solver. Stars: 3 at par, 2 within par+2,
   1 otherwise.
4. 13 achievements tracked locally with an unlock toast.

## R5. Save/load
1. Progress, stars, cranes, achievements, settings and statistics SHALL persist via `OVSaveStore`.
2. WHEN the app is paused or closed mid-level THEN the level state SHALL be saved and offered as "Continue".
3. Undo (unlimited within a level) and restart SHALL be available.

## R6. Presentation
1. Paper rendering via the core paper shader with per-chapter presets; low-poly props from the Blender pipeline.
2. Synthesized paper SFX and ambience (core `OVPaperAudio`), haptics on fold snap, settings for music/SFX/haptics.
3. Portrait-first touch UI, readable at 5.5" to tablet sizes; one-finger orbit, pinch zoom, double-tap recenter.

## R7. Quality
1. Every level SHALL be proven solvable by `FSSolver` in automated tests, with all cranes collectible and par matching
   the value stored in the level file.
2. 60 FPS target, 30 FPS floor on the Redmi Note 11.
3. Fully offline; no data collection.
