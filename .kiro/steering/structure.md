# Repository structure

```
.kiro/
  specs/origamiverse-core/   requirements.md, design.md, tasks.md
  specs/foldshift/           requirements.md, design.md, tasks.md
  specs/paperverse/          requirements.md, design.md, tasks.md
  steering/                  product.md, tech.md, structure.md
  hooks/                     Kiro agent hooks (core sync + tests)
shared-core/                 Godot project that hosts and tests OrigamiVerse Core
  addons/origamiverse_core/  THE shared engine (source of truth)
  tests/                     headless unit tests for the core
apps/foldshift/              Godot project: FoldShift puzzle game
apps/paperverse/             Godot project: PaperVerse studio
pipeline/blender/            Blender Python scripts -> GLB assets for the apps
promo/remotion/              Remotion project for demo, trailer, vertical promos
store/<app>/                 Google Play listing text, icon, feature graphic, screenshots
docs/                        kiro-usage.md, reusability.md, architecture, privacy policies, devpost
tools/                       sync_core.py, build scripts
```

`.kiro/` is part of the product deliverable and must never be gitignored.
