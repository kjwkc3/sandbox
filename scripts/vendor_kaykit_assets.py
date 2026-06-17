"""Copy KayKit glTF pack into assets/dungeon/ and fix texture URIs."""
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SRC_GLTF = Path(
    r"C:\Users\kjwkc\Downloads\KayKit_DungeonRemastered_1.1_FREE"
    r"\KayKit_DungeonRemastered_1.1_FREE\Assets\gltf"
)
SRC_OBJ = Path(
    r"C:\Users\kjwkc\Downloads\KayKit_DungeonRemastered_1.1_FREE"
    r"\KayKit_DungeonRemastered_1.1_FREE\Assets\obj"
)
SRC_LICENSE = Path(
    r"C:\Users\kjwkc\Downloads\KayKit_DungeonRemastered_1.1_FREE"
    r"\KayKit_DungeonRemastered_1.1_FREE\License.txt"
)
DST = REPO / "assets" / "dungeon"
MESHES = DST / "meshes"
TEXTURE = DST / "texture"
CATALOG = DST / "catalog" / "obj"
TEXTURE_URI = "../texture/dungeon_texture.png"


def fix_gltf_texture_uri(gltf_path: Path) -> None:
    data = json.loads(gltf_path.read_text(encoding="utf-8"))
    changed = False
    for image in data.get("images", []):
        if "uri" in image and image["uri"] != TEXTURE_URI:
            image["uri"] = TEXTURE_URI
            changed = True
    if changed:
        gltf_path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")


def main() -> int:
    if not SRC_GLTF.is_dir():
        print(f"Source glTF folder not found: {SRC_GLTF}", file=sys.stderr)
        return 1

    MESHES.mkdir(parents=True, exist_ok=True)
    TEXTURE.mkdir(parents=True, exist_ok=True)
    CATALOG.mkdir(parents=True, exist_ok=True)

    texture_src = SRC_GLTF / "dungeon_texture.png"
    if not texture_src.is_file():
        print(f"Missing texture: {texture_src}", file=sys.stderr)
        return 1
    shutil.copy2(texture_src, TEXTURE / "dungeon_texture.png")

    if SRC_LICENSE.is_file():
        shutil.copy2(SRC_LICENSE, DST / "License.txt")

    gltf_count = 0
    for gltf in sorted(SRC_GLTF.glob("*.gltf")):
        stem = gltf.stem
        bin_src = SRC_GLTF / f"{stem}.bin"
        if not bin_src.is_file():
            print(f"Warning: missing bin for {gltf.name}")
            continue
        shutil.copy2(gltf, MESHES / gltf.name)
        shutil.copy2(bin_src, MESHES / bin_src.name)
        fix_gltf_texture_uri(MESHES / gltf.name)
        gltf_count += 1

    if SRC_OBJ.is_dir():
        for obj in SRC_OBJ.glob("*.obj"):
            shutil.copy2(obj, CATALOG / obj.name)
        for mtl in SRC_OBJ.glob("*.mtl"):
            shutil.copy2(mtl, CATALOG / mtl.name)

    print(f"Vendored {gltf_count} glTF meshes -> {MESHES}")
    print(f"Texture -> {TEXTURE / 'dungeon_texture.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
