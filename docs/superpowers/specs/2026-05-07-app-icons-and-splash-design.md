# App Icons + Splash Screen — Design

Date: 2026-05-07

## Goal

1. Replace the existing iPad/Mac app icon set with the new artwork at `graphics/AppIcons/Assets.xcassets/AppIcon.appiconset/`.
2. Add a poster splash screen as the first scene shown on app launch. Any keyboard key, any controller button, or any Siri Remote input dismisses to the title screen.

## Scope

- Asset catalog: replace `AppIcon.appiconset` contents; add `Splash.imageset`.
- New file: `Bashteroids/Scenes/PosterScene.swift`.
- Modify: `Bashteroids/App/GameContainerView.swift` initial-scene constructor.
- tvOS layered icon (`AppIcon.brandassets/`) is unchanged — the new graphics don't include a tvOS layered set.

## App icons

`graphics/AppIcons/Assets.xcassets/AppIcon.appiconset/` ships 23 PNGs covering iPad (20/29/40/50/72/76/80/100/144/152/167/512 px) and Mac (16/32/64/128/256/512/1024 px) idioms, plus a `Contents.json` mapping each PNG to its `(size, idiom, scale)` slot.

Wholesale replacement of `Bashteroids/Assets.xcassets/AppIcon.appiconset/*` with these files. The build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` already points at this set; tvOS continues to find `AppIcon.brandassets`.

## Splash screen

### `Splash.imageset` in the asset catalog

```
Bashteroids/Assets.xcassets/Splash.imageset/
├── Contents.json
└── poster.png         # 1786 × 2526, copied from graphics/poster.png
```

`Contents.json`:
```json
{
  "images" : [
    { "filename" : "poster.png", "idiom" : "universal", "scale" : "1x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Universal idiom works on iOS, macOS Catalyst, and tvOS.

### `PosterScene`

New `SKScene` shown as the initial scene. Renders an `SKSpriteNode` with the `Splash` texture, sized to fit the screen height while preserving aspect ratio (letterbox on left/right since the poster is portrait and the screen is landscape). After ~1 s, a "PRESS ANY KEY" prompt fades in at the bottom in subtle gray.

Input → dismiss → `TitleScene` via 0.4 s fade transition:
- Keyboard: any keydown (via `KeyboardManager.shared.onKeyDown`)
- Controller: any pressed button on any connected `extendedGamepad` or `microGamepad` (polled per frame, edge-triggered)

### Initial scene wiring

`GameContainerView.makeScene(size:)` switches to `PosterScene(size:)`. `PosterScene` constructs and presents a fresh `TitleScene` on dismiss.

## Out of scope

- Splash skipping on first launch only (always shown).
- Audio cue on splash (no music; matches existing silent title).
- tvOS layered icon update.
- Animations beyond the prompt fade.
