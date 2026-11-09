# Product steering: OrigamiVerse — Fold Reality

Studio brand: **F7 Developer**. Hackathon: **Kiroween 2026, Skeleton Crew category**.
Skeleton Crew = one reusable skeleton (OrigamiVerse Core) powering two distinct apps.

## Products

| App | Package | Purpose |
| --- | --- | --- |
| FoldShift: Origami Puzzle | `com.f7developer.foldshift` | 3D puzzle adventure. Fold paper islands to build bridges, raise walls you can walk on, reveal secrets. |
| PaperVerse: 3D Origami Studio | `com.f7developer.paperverse` | Creative tool. Draw crease patterns, simulate folding live, animate, export FOLD / GLB / OBJ. |

## Non-negotiables

- Offline-first. No mandatory server, account, paid API, ads SDK or external hardware.
- Folding is computed in real time in Godot by OrigamiVerse Core. Never ship prerecorded fold animations as gameplay.
- No Blender, Remotion or Three.js code or runtime inside the APKs. Those are offline pipeline tools only.
- Every shipped feature is finished and reachable from the UI. No dummy buttons, "coming soon" screens or placeholder levels.
- Every FoldShift level is proven solvable by the automated level solver, and its par is computed, not guessed.
- English-first UI and store copy.
- Collect no personal data. Saves stay in `user://` on the device.

## Future monetization (design only, not implemented)

`OVFeatureGate` in core exposes entitlement checks (`is_unlocked(feature_id)`). Today every feature returns
unlocked. A later release can map chapters, templates or export formats to a one-time "Pro" purchase without
touching gameplay code.
