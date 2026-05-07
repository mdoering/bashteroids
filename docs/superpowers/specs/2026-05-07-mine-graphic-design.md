# Mine Graphic — Design

Date: 2026-05-07

## Goal

Restyle the mine's vector graphic to read as a classic sea mine — a central body with small contact-horn balls protruding around its perimeter — instead of the current spike-line look.

## Scope

A single function: `Shapes.mine()` in `Bashteroids/Render/Shapes.swift`. No other code changes; collision radius (`Mine.collisionRadius = 14`) unchanged; visual footprint unchanged.

## Geometry

- Central body: stroked circle at radius `Mine.collisionRadius = 14`, white, lineWidth 1.5 (unchanged from current).
- Six horns at angles `a = i / 6 * 2π`, each composed of:
  - **Stub line** from `(14·cos a, 14·sin a)` to `(17·cos a, 17·sin a)` — replaces the old radial spike line, but shorter.
  - **Horn ball** — stroked circle of radius 2.5 centered at `(19·cos a, 19·sin a)`, white, lineWidth 1.5.

Visual extent ≈ radius 21 (was 20), no collision impact.

## Stroke + style

All elements share the existing white stroke + clear fill + lineWidth 1.5 + antialiasing on. Matches the rest of the procedural vector aesthetic.

## Out of scope

- Animation. Mine still flashes via the existing alpha-cycling logic in `Mine.update(dt:)`.
- Color. Stays white.
- Differentiation between spawner-placed and player-laid mines. Both use the same graphic.
