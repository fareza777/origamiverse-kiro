# How Kiro was used

Kiro drove the whole build, from specs to device QA. `.kiro/` is part of the deliverable and is tracked.

## Specs

Three spec-driven features, each with `requirements.md`, `design.md` and `tasks.md`:

- `.kiro/specs/origamiverse-core/` the shared skeleton
- `.kiro/specs/foldshift/` the puzzle game
- `.kiro/specs/paperverse/` the studio

The core spec was written first so both app specs reference its classes instead of reinventing them.
Requirements use EARS-style acceptance criteria, and tasks cite the requirement they satisfy (for example
"R4.3").

## Steering

`.kiro/steering/` holds always-on context:

- `product.md` non-negotiables (offline-first, real-time folding, no placeholder features, no personal data)
- `tech.md` toolchain, typed GDScript rules, hot-loop rules, core distribution, test commands, secrets handling
- `structure.md` repository layout

Because of these, Kiro kept core free of app dependencies, used packed arrays in solver loops, and never
edited the synced app copies.

## Hooks

`.kiro/hooks/`:

- `sync-core-on-save` runs `tools/sync_core.py` when a core file is saved.
- `core-tests-on-save` runs the headless core test suite after a core or test change.
- `level-proof-on-save` re-runs the level solver proofs when FoldShift levels or level code change.

## Verification loop

Kiro ran the headless suites after each change:

- core: 51 tests
- FoldShift: every level solved by `FSSolver`, par equals the value stored in the level file, and the
  solution replays through `FSPuzzle`
- PaperVerse: every template planarizes and folds within strain limits; project round trip

Device checks used `adb` on a Redmi Note 11.

## Where Kiro helped most

- Designing a solver-proven level format, so levels are generated and checked rather than guessed.
- Keeping one core consistent across two apps through the sync tool and drift check.
- Debugging solver and export problems using headless tests and logs.
