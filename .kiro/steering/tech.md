# Tech steering

## Toolchain on this machine

- Godot `4.7.2.stable` at `C:\dev\godot\Godot_v4.7.2-stable_win64_console.exe` (use the console build for CLI).
- Android SDK `C:\Android\Sdk` (configured in Godot editor settings), JDK 17, build-tools 35/36.
- Test device: Xiaomi Redmi Note 11 (`2201117TY`, Snapdragon 680 / Adreno 610) over ADB. Treat it as the
  low-end performance target: 60 FPS goal, 30 FPS floor.
- Blender `4.5 LTS` at `C:\Program Files\Blender Foundation\Blender 4.5\blender.exe` for the asset pipeline.
- Node 26 for Remotion promo videos in `promo/remotion`.

## Engine rules

- GDScript 2 with static types everywhere (`var x: float`, typed arrays, typed returns). Typed code is
  measurably faster on mobile and catches errors at parse time.
- Renderer: `mobile` with automatic fallback to OpenGL ES 3 (`rendering_device/fallback_to_opengl3=true`).
  Shaders must compile on both, so avoid compute shaders and screen-texture tricks.
- Hot loops in solvers use `PackedFloat32Array`/`PackedVector3Array`/`PackedInt32Array` and precomputed index
  buffers. No `Dictionary` lookups or `Array` keys inside per-frame loops.
- Core classes are prefixed `OV` (`OVFoldDocument`, `OVHingeSolver`, ...) to avoid collisions with app code.
- Core never references app scripts. Apps depend on core, never the reverse.

## Shared core distribution

- Source of truth: `shared-core/addons/origamiverse_core/`.
- `python tools/sync_core.py` copies it into `apps/*/addons/origamiverse_core/`. Copies are committed so each app
  opens standalone in Godot, and `python tools/sync_core.py --check` fails if any copy drifts.
- Never edit the app copies directly.

## Testing

- Core unit tests: `godot --headless --path shared-core -s res://tests/run_tests.gd` (exit code = failures).
- FoldShift level proofs: `godot --headless --path apps/foldshift -s res://tests/run_tests.gd`.
- PaperVerse tests: `godot --headless --path apps/paperverse -s res://tests/run_tests.gd`.
- Device QA via `adb` (install, launch, logcat filtered to `godot`, `screencap`, `screenrecord`).

## Secrets

- Release keystore lives outside the repo (`C:\dev\keys\f7developer-release.keystore`). Credentials come from the
  environment variables Godot reads: `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `_USER`, `_PASSWORD`.
  Never commit keystores or passwords.
