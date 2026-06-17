#!/usr/bin/env bash
set -euo pipefail

# Linux / WSL build helper (Windows native: use ./build.ps1).
# Prerequisites: odin on PATH, SDL2 dev libs (sudo apt install libsdl2-dev)

RUN=false
RELEASE=false

usage() {
	echo "Usage: $0 [--run] [--release]" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--run) RUN=true; shift ;;
		--release) RELEASE=true; shift ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

if ! command -v odin >/dev/null 2>&1; then
	echo "odin not found on PATH. Install from https://github.com/odin-lang/Odin" >&2
	exit 1
fi

if command -v pkg-config >/dev/null 2>&1; then
	if ! pkg-config --exists sdl2; then
		echo "SDL2 not found. Install with: sudo apt install libsdl2-dev" >&2
		exit 1
	fi
elif ! ldconfig -p 2>/dev/null | grep -q 'libSDL2-2\.0\.so'; then
	echo "SDL2 not found. Install with: sudo apt install libsdl2-dev" >&2
	exit 1
fi

OUT_DIR=build
mkdir -p "$OUT_DIR"

FLOOR_GLB="assets/dungeon/floor_tile_large.glb"
FLOOR_OBJ="assets/dungeon/floor_tile_large.obj"
if [[ ! -f "$FLOOR_GLB" ]]; then
	python3 scripts/obj_to_glb.py "$FLOOR_OBJ" "$FLOOR_GLB"
fi

if $RELEASE; then
	OUT="$OUT_DIR/sandbox-release"
	odin build . -out:"$OUT" -o:speed -vet
else
	OUT="$OUT_DIR/sandbox-debug"
	odin build . -out:"$OUT" -debug -vet
fi

echo "Built: $OUT"

if $RUN; then
	exec "./$OUT"
fi
