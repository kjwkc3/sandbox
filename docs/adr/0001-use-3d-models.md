# Use 3D models instead of 2D sprites

We chose 3D models (low-poly) over 2D sprites for all game entities — characters, enemies, tiles, and props.

## Context

The game is a top-down isometric roguelite ARPG. We need Z-sorting for objects rendering on top of each other (cups on tables on floors). We also need characters that can face any direction during movement.

## Decision

Use 3D models loaded via OpenGL. Kay Lousberg's free Dungeon Pack Remastered provides tiles, walls, doors, and props. Character Packs provide rigged and animated character models.

## Why

- **Z-sorting is automatic** via GPU depth buffer — no manual sorting needed
- **No sprite direction problem** — one model works from any camera angle
- **Free high-quality assets** — Kay's packs match our aesthetic needs
- **We're already using OpenGL** — just need to add a model loader

## Tradeoffs

- More complex rendering pipeline (model loading, shaders, animations)
- Larger file sizes than sprites
- But: we'd spend *more* time on manual Z-sorting and sprite management with 2D
