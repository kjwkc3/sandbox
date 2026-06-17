"""Minimal OBJ to GLB converter for KayKit floor tiles (no external deps)."""
import json
import struct
import sys
from pathlib import Path


def parse_obj(path: Path):
    vertices = []
    faces = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            vertices.extend(float(x) for x in parts[1:4])
        elif parts[0] == "f":
            face = []
            for token in parts[1:]:
                face.append(int(token.split("/")[0]) - 1)
            for i in range(1, len(face) - 1):
                faces.extend((face[0], face[i], face[i + 1]))
    return vertices, faces


def compute_normals(vertices, indices):
    normals = [0.0] * len(vertices)
    for i in range(0, len(indices), 3):
        i0, i1, i2 = indices[i], indices[i + 1], indices[i + 2]
        ax, ay, az = (
            vertices[i1 * 3] - vertices[i0 * 3],
            vertices[i1 * 3 + 1] - vertices[i0 * 3 + 1],
            vertices[i1 * 3 + 2] - vertices[i0 * 3 + 2],
        )
        bx, by, bz = (
            vertices[i2 * 3] - vertices[i0 * 3],
            vertices[i2 * 3 + 1] - vertices[i0 * 3 + 1],
            vertices[i2 * 3 + 2] - vertices[i0 * 3 + 2],
        )
        nx = ay * bz - az * by
        ny = az * bx - ax * bz
        nz = ax * by - ay * bx
        for idx in (i0, i1, i2):
            normals[idx * 3] += nx
            normals[idx * 3 + 1] += ny
            normals[idx * 3 + 2] += nz
    for i in range(0, len(normals), 3):
        x, y, z = normals[i], normals[i + 1], normals[i + 2]
        length = (x * x + y * y + z * z) ** 0.5 or 1.0
        normals[i] = x / length
        normals[i + 1] = y / length
        normals[i + 2] = z / length
    return normals


def pack_f32(values):
    return struct.pack(f"<{len(values)}f", *values)


def pack_u32(values):
    return struct.pack(f"<{len(values)}I", *values)


def write_glb(out_path: Path, vertices, normals, indices):
    pos_bytes = pack_f32(vertices)
    norm_bytes = pack_f32(normals)
    idx_bytes = pack_u32(indices)
    bin_data = pos_bytes + norm_bytes + idx_bytes

    pos_offset = 0
    norm_offset = len(pos_bytes)
    idx_offset = norm_offset + len(norm_bytes)

    vertex_count = len(vertices) // 3
    index_count = len(indices)

    gltf = {
        "asset": {"version": "2.0", "generator": "sandbox obj2glb"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [
            {
                "primitives": [
                    {
                        "attributes": {"POSITION": 0, "NORMAL": 1},
                        "indices": 2,
                        "material": 0,
                    }
                ]
            }
        ],
        "materials": [
            {
                "name": "floor",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.72, 0.68, 0.58, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.85,
                },
            }
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": vertex_count,
                "type": "VEC3",
                "max": [
                    max(vertices[i] for i in range(0, len(vertices), 3)),
                    max(vertices[i + 1] for i in range(0, len(vertices), 3)),
                    max(vertices[i + 2] for i in range(0, len(vertices), 3)),
                ],
                "min": [
                    min(vertices[i] for i in range(0, len(vertices), 3)),
                    min(vertices[i + 1] for i in range(0, len(vertices), 3)),
                    min(vertices[i + 2] for i in range(0, len(vertices), 3)),
                ],
            },
            {
                "bufferView": 1,
                "componentType": 5126,
                "count": vertex_count,
                "type": "VEC3",
            },
            {
                "bufferView": 2,
                "componentType": 5125,
                "count": index_count,
                "type": "SCALAR",
            },
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": pos_offset, "byteLength": len(pos_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": norm_offset, "byteLength": len(norm_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": idx_offset, "byteLength": len(idx_bytes), "target": 34963},
        ],
        "buffers": [{"byteLength": len(bin_data)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_pad = (4 - (len(json_bytes) % 4)) % 4
    json_bytes += b" " * json_pad

    bin_pad = (4 - (len(bin_data) % 4)) % 4
    bin_data += b"\x00" * bin_pad

    total_length = 12 + 8 + len(json_bytes) + 8 + len(bin_data)

    with out_path.open("wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total_length))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942))
        f.write(bin_data)


def main():
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    vertices, indices = parse_obj(src)
    normals = compute_normals(vertices, indices)
    write_glb(dst, vertices, normals, indices)
    print(f"Wrote {dst} ({len(vertices)//3} verts, {len(indices)//3} tris)")


if __name__ == "__main__":
    main()
