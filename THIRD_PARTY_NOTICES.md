# Third-party notices

OrigamiVerse is MIT-licensed (see `LICENSE`). It builds on the work below.

## Reference projects (MIT)

No source code from these projects is included. The FOLD parser and both solvers are original GDScript. They are
credited because their formats and models shaped the design.

| Project | Copyright | Used for |
| --- | --- | --- |
| [edemaine/fold](https://github.com/edemaine/fold) | Copyright (c) 2016 Erik Demaine, Jason Ku, Robert Lang | FOLD 1.2 file format and data model |
| [amandaghassaei/OrigamiSimulator](https://github.com/amandaghassaei/OrigamiSimulator) | Copyright (c) 2018 Amanda Ghassaei | Bar-and-hinge simulation model, reformulated as XPBD |
| [ELF32bit/godot-folder](https://github.com/ELF32bit/godot-folder) | Copyright 2025 ELF32bit | Idea of a FOLD graph class that builds meshes in Godot |

## Converted data (MIT)

The classic crease patterns in `apps/paperverse/templates/` (bird, frog, waterbomb, square and pinwheel bases,
square twist, simple vertex, map fold, brochure) were converted from the example SVGs of
[Origami Simulator](https://github.com/amandaghassaei/OrigamiSimulator) by `tools/svg_to_templates.py`.

```
MIT License

Copyright (c) 2018 Amanda Ghassaei

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Font (SIL OFL 1.1)

The UI typeface is [Outfit](https://github.com/Outfitio/Outfit-Fonts), Copyright 2021 The Outfit Project Authors,
licensed under the SIL Open Font License 1.1. The full license ships next to the font at
`shared-core/addons/origamiverse_core/ui/fonts/OFL.txt`.

## Engine

Built with [Godot Engine](https://godotengine.org) (MIT). Godot's own license and third-party notices apply to the
exported apps.
