# Title Screen Layout — Design

Date: 2026-05-07

## Goal

Restyle `TitleScene` to use the new poster artwork as the centerpiece. Move UI to the perimeter so the poster reads cleanly:

- Poster (fit-to-height, letterboxed) is the centered background.
- Mode + Level selectors move from center to top-right corner, stacked vertically.
- "PRESS A TO JOIN..." hint moves to the bottom.
- The redundant "BASHTEROIDS" text title and the small upper-right logo are removed (the poster contains both).
- Highscores keep their top-left position but get a new color palette.

## Layout

All positions are proportional to scene size, so the layout adapts to iPad / Mac / tvOS displays without hardcoding pixel values.

| Element | Position | Notes |
| --- | --- | --- |
| Poster background | center, `width × aspect` × `height` | Fit-to-height, letterboxed |
| Highscores heading | `(30, height − safeTopInset − 80)` | Unchanged |
| Highscore rows | `(30, headingY − 24·(i+1))` | Unchanged geometry |
| Mode row label | `(width × 0.93, height × 0.92)` | Top-right anchor |
| Mode row arrows | `mode.x ± 40` | |
| Mode caption "MODE" | `(mode.x, mode.y − 24)` | |
| Level row label | `(width × 0.93, height × 0.84)` | Below mode |
| Level row arrows | `level.x ± 40` | |
| Level caption "LEVEL" | `(level.x, level.y − 24)` | |
| Battle hint | `(width × 0.93, height × 0.78)` | Below level |
| Player slot tiles | `y = height × 0.46` | Unchanged (overlays poster center) |
| "PRESS A TO JOIN..." hint | `(width / 2, height × 0.04)` | Bottom center |

## Removals

- `makeIconNode()` upper-right composite (rock + ships)
- "BASHTEROIDS" SKLabelNode at `height × 0.72`

Both functions / properties stay in the file only as long as they have callers; once unwired, they're removed.

## Highscore color palette

| Element | Color |
| --- | --- |
| Heading "HIGHSCORES" | `RGB(245, 194, 66)` (gold) |
| First entry | `RGB(231, 63, 150)` (magenta) |
| Other entries | `RGB(98, 212, 214)` (cyan) |

Replaces the current heading=playerColor[0] (red) / rows=playerColor[1] (blue) palette.

## Splash scene removal

`PosterScene` (added earlier as a tap-to-dismiss splash) is now redundant — the poster is the title screen background. Changes:

- Delete `Bashteroids/Scenes/PosterScene.swift`.
- `GameContainerView.makeScene(size:)` returns `TitleScene(size:)` directly (instead of `PosterScene(size:)`).
- `Splash.imageset` stays — now used by TitleScene's background sprite.

## Out of scope

- Player slot tile relocation. They stay at `y = height × 0.46` even though they overlay the poster's central ships+mine. Can revisit in playtest.
- Highscore typography or layout (only colors change).
- Battle-mode-availability snap-back logic is unchanged.
