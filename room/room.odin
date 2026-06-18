package room

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../render"
import "../math3d"

FLOOR_MESH :: "assets/dungeon/meshes/floor_tile_large.gltf"
WALL_MESH :: "assets/dungeon/meshes/wall.gltf"
WALL_CORNER_MESH :: "assets/dungeon/meshes/wall_corner.gltf"

TILE_SIZE :: 4
PERIM_MIN :: -2
PERIM_MAX :: 18

ModelKind :: enum {
	Floor,
	Wall,
	WallCorner,
}

Placement :: struct {
	kind:      ModelKind,
	transform: render.Transform,
}

Room :: struct {
	floor:       render.Model,
	wall:        render.Model,
	wall_corner: render.Model,
	placements:  []Placement,
}

build_placements :: proc(allocator := context.allocator) -> []Placement {
	placements := make([dynamic]Placement, allocator)
	defer delete(placements)

	for r in 0 ..< 5 {
		for c in 0 ..< 5 {
			append(
				&placements,
				Placement{
					.Floor,
					render.transform_with_yaw({f32(c * 4), 0, f32(r * 4)}, 0),
				},
			)
		}
	}

	append(&placements, Placement{.WallCorner, render.transform_with_yaw({PERIM_MIN, 0, PERIM_MIN}, 90)})
	append(&placements, Placement{.WallCorner, render.transform_with_yaw({PERIM_MAX, 0, PERIM_MIN}, 0)})
	append(&placements, Placement{.WallCorner, render.transform_with_yaw({PERIM_MAX, 0, PERIM_MAX}, 270)})
	append(&placements, Placement{.WallCorner, render.transform_with_yaw({PERIM_MIN, 0, PERIM_MAX}, 180)})

	for x in 1 ..< 5 {
		append(&placements, Placement{.Wall, render.transform_with_yaw({PERIM_MIN + f32(x * TILE_SIZE), 0, PERIM_MIN}, 180)})
	}
	for x in 1 ..< 5 {
		append(&placements, Placement{.Wall, render.transform_with_yaw({PERIM_MIN + f32(x * TILE_SIZE), 0, PERIM_MAX}, 0)})
	}
	for z in 1 ..< 5 {
		append(&placements, Placement{.Wall, render.transform_with_yaw({PERIM_MIN, 0, PERIM_MIN + f32(z * TILE_SIZE)}, 90)})
	}
	for z in 1 ..< 5 {
		append(&placements, Placement{.Wall, render.transform_with_yaw({PERIM_MAX, 0, PERIM_MIN + f32(z * TILE_SIZE)}, 270)})
	}

	result := make([]Placement, len(placements), allocator)
	copy(result, placements[:])
	return result
}

resolve_asset_path :: proc(relative: string, allocator := context.temp_allocator) -> cstring {
	if os.exists(relative) {
		return strings.clone_to_cstring(relative, allocator)
	}

	if exe_dir, err := os.get_executable_directory(allocator); err == nil {
		candidate := filepath.join({exe_dir, relative}, allocator) or_else ""
		if candidate != "" && os.exists(candidate) {
			return strings.clone_to_cstring(candidate, allocator)
		}
		if filepath.base(exe_dir) == "build" {
			candidate = filepath.join({exe_dir, "..", relative}, allocator) or_else ""
			if candidate != "" && os.exists(candidate) {
				return strings.clone_to_cstring(candidate, allocator)
			}
		}
	}

	panic(fmt.tprintf("Asset not found: %s", relative))
}

load_room :: proc(cache: ^render.TextureCache, allocator := context.allocator) -> (Room, bool) {
	floor_path := resolve_asset_path(FLOOR_MESH)
	wall_path := resolve_asset_path(WALL_MESH)
	corner_path := resolve_asset_path(WALL_CORNER_MESH)

	floor, floor_ok := render.load_model(floor_path, cache, allocator)
	if !floor_ok {
		fmt.println("Failed to load floor mesh")
		return {}, false
	}

	wall, wall_ok := render.load_model(wall_path, cache, allocator)
	if !wall_ok {
		render.delete_model(floor)
		fmt.println("Failed to load wall mesh")
		return {}, false
	}

	wall_corner, corner_ok := render.load_model(corner_path, cache, allocator)
	if !corner_ok {
		render.delete_model(floor)
		render.delete_model(wall)
		fmt.println("Failed to load wall corner mesh")
		return {}, false
	}

	return Room{
		floor       = floor,
		wall        = wall,
		wall_corner = wall_corner,
		placements  = build_placements(allocator),
	}, true
}

draw_room :: proc(room: Room, shader: render.ShaderProgram, cam: render.Camera) {
	render.bind_frame(shader, cam)
	for placement in room.placements {
		model: render.Model
		switch placement.kind {
		case .Floor:
			model = room.floor
		case .Wall:
			model = room.wall
		case .WallCorner:
			model = room.wall_corner
		}
		render.draw_model_at(model, shader, placement.transform)
	}
}

delete_room :: proc(room: Room) {
	render.delete_model(room.floor)
	render.delete_model(room.wall)
	render.delete_model(room.wall_corner)
	delete(room.placements)
}

room_camera :: proc(width, height: u32) -> render.Camera {
	target := math3d.Vec3{8, 0, 8}
	distance: f32 = 18
	elevation: f32 = 16
	return render.Camera{
		position = target + math3d.Vec3{distance, elevation, distance},
		target   = target,
		up       = {0, 1, 0},
		fov_deg  = 38,
		near     = 0.1,
		far      = 200,
		aspect   = f32(width) / f32(height),
	}
}
