package room

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../collision"
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

// KayKit wall / wall_corner mesh local bounds (from glTF accessors).
WALL_LOCAL_MIN :: math3d.Vec3{-2, 0, -0.5}
WALL_LOCAL_MAX :: math3d.Vec3{2, 4, 0.5}
CORNER_LOCAL_MIN :: math3d.Vec3{-2, 0, -0.5}
CORNER_LOCAL_MAX :: math3d.Vec3{0.5, 4, 2}

@(private="file")
transform_bounds_yaw :: proc(min_pt, max_pt: math3d.Vec3, yaw_deg: f32) -> collision.AABB {
	corners: [8]math3d.Vec3
	corners[0] = {min_pt.x, min_pt.y, min_pt.z}
	corners[1] = {max_pt.x, min_pt.y, min_pt.z}
	corners[2] = {min_pt.x, max_pt.y, min_pt.z}
	corners[3] = {max_pt.x, max_pt.y, min_pt.z}
	corners[4] = {min_pt.x, min_pt.y, max_pt.z}
	corners[5] = {max_pt.x, min_pt.y, max_pt.z}
	corners[6] = {min_pt.x, max_pt.y, max_pt.z}
	corners[7] = {max_pt.x, max_pt.y, max_pt.z}

	yaw_rad := yaw_deg * math3d.RAD_PER_DEG
	cos_y := math.cos(yaw_rad)
	sin_y := math.sin(yaw_rad)

	world_min := math3d.Vec3{1e9, 1e9, 1e9}
	world_max := math3d.Vec3{-1e9, -1e9, -1e9}

	for corner in corners {
		rx := corner.x * cos_y - corner.z * sin_y
		rz := corner.x * sin_y + corner.z * cos_y
		world_min.x = min(world_min.x, rx)
		world_min.y = min(world_min.y, corner.y)
		world_min.z = min(world_min.z, rz)
		world_max.x = max(world_max.x, rx)
		world_max.y = max(world_max.y, corner.y)
		world_max.z = max(world_max.z, rz)
	}

	return collision.AABB{min = world_min, max = world_max}
}

@(private="file")
placement_yaw_deg :: proc(transform: render.Transform) -> f32 {
	q: math3d.Quat
	q.x = transform.rotation[0]
	q.y = transform.rotation[1]
	q.z = transform.rotation[2]
	q.w = transform.rotation[3]
	// Y-up yaw from quaternion: yaw = atan2(2(wy + xz), 1 - 2(y² + z²)) in radians.
	siny_cosp := 2.0 * (q.w * q.y + q.x * q.z)
	cosy_cosp := 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
	return math.atan2(siny_cosp, cosy_cosp) / math3d.RAD_PER_DEG
}

@(private="file")
collider_for_placement :: proc(placement: Placement) -> collision.AABB {
	yaw := placement_yaw_deg(placement.transform)
	local_min, local_max: math3d.Vec3
	switch placement.kind {
	case .Floor:
		return {}
	case .Wall:
		local_min = WALL_LOCAL_MIN
		local_max = WALL_LOCAL_MAX
	case .WallCorner:
		local_min = CORNER_LOCAL_MIN
		local_max = CORNER_LOCAL_MAX
	}

	bounds := transform_bounds_yaw(local_min, local_max, yaw)
	offset := placement.transform.position
	bounds.min.x += offset[0]
	bounds.min.y += offset[1]
	bounds.min.z += offset[2]
	bounds.max.x += offset[0]
	bounds.max.y += offset[1]
	bounds.max.z += offset[2]
	return bounds
}

room_wall_colliders :: proc(allocator := context.allocator) -> []collision.AABB {
	placements := build_placements(context.temp_allocator)
	colliders := make([dynamic]collision.AABB, allocator)
	for placement in placements {
		if placement.kind == .Floor {
			continue
		}
		append(&colliders, collider_for_placement(placement))
	}
	return colliders[:]
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
