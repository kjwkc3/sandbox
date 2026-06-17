# KayKit Dungeon Remastered assets

Vendored glTF meshes and shared texture atlas for the sandbox 3D dungeon room demo.

## Layout

```
assets/dungeon/
  README.md
  License.txt
  texture/
    dungeon_texture.png          # shared atlas (all meshes reference this)
  meshes/
    floor_tile_large.gltf + .bin
    wall.gltf + .bin
    wall_corner.gltf + .bin
    ...                          # full KayKit glTF pack (211 meshes)
```

Meshes load natively via cgltf (`.gltf` + sidecar `.bin`). Each glTF JSON references the atlas at `../texture/dungeon_texture.png`.

This directory is **glTF-only** — copy meshes and the shared atlas from the KayKit pack; do not add OBJ/MTL or other interchange formats here.

## Source

[KayKit Dungeon Remastered 1.1 (FREE)](https://kaylousberg.itch.io/kaykit-dungeon-remastered)

Download the pack from itch.io and copy the `gltf/` meshes plus `dungeon_texture.png` into `meshes/` and `texture/` respectively.

## License

KayKit assets are free for personal and commercial use. See `License.txt`.

## Usage

Run from the project root (or from `build/` after `./build.sh`) so asset paths resolve. The demo loads `floor_tile_large`, `wall`, and `wall_corner` from `meshes/` to build a 5×5 closed room.
