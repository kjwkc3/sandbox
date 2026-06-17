# KayKit Dungeon Remastered assets

Floor tile mesh used by the sandbox 3D rendering demo (`main.odin`).

## Source

Copied from [KayKit Dungeon Remastered 1.1 (FREE)](https://kaylousberg.itch.io/kaykit-dungeon-remastered):

- `floor_tile_large.obj` — closest match to a standard dungeon floor tile (no `.glb` in the free pack)
- Converted to `floor_tile_large.glb` for cgltf loading

## OBJ → GLB conversion

The free KayKit pack ships `.obj` only. Generate the glTF binary before building or running:

```bash
python3 scripts/obj_to_glb.py assets/dungeon/floor_tile_large.obj assets/dungeon/floor_tile_large.glb
```

`make debug` / `./build.sh` run this automatically when the `.glb` is missing.

## License

KayKit assets are free for personal and commercial use. See `License.txt` in the original download.

## Usage

Run from the project root so the loader finds `assets/dungeon/floor_tile_large.glb`, or build with `build.ps1` / `make debug` and run from `build/`.
