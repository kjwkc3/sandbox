package character

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../math3d"
import "../render"

KNIGHT_MESH :: "assets/character/meshes/Knight.glb"

// KayKit origin sits below the floor plane; lift so boots rest on y=0 tiles.
FOOT_OFFSET_Y :: f32(1.12)
CHARACTER_YAW :: f32(0)
CHARACTER_SCALE :: f32(1.0)
MOVE_SPEED :: f32(6.0)
TURN_STIFFNESS :: f32(12.0)
MOVE_EPSILON :: f32(0.001)

Character :: struct {
	model:    render.SkinnedModel,
	position: math3d.Vec3,
	yaw:      f32,
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

load_character :: proc(cache: ^render.TextureCache, allocator := context.allocator) -> (Character, bool) {
	path := resolve_asset_path(KNIGHT_MESH)
	model, ok := render.load_skinned_model(path, cache, allocator)
	if !ok {
		fmt.println("Failed to load knight character")
		return {}, false
	}
	return Character{
		model = model,
		position = {8, FOOT_OFFSET_Y, 8},
		yaw = CHARACTER_YAW,
	}, true
}

character_transform :: proc(c: Character) -> render.Transform {
	return render.transform_with_yaw(c.position, c.yaw)
}

move_character :: proc(c: ^Character, move_dir: math3d.Vec3, dt: f32) -> bool {
	dir := move_dir
	dir.y = 0

	len_sq := dir.x * dir.x + dir.z * dir.z
	if len_sq > MOVE_EPSILON * MOVE_EPSILON {
		inv_len := 1.0 / math.sqrt(len_sq)
		dir.x *= inv_len
		dir.z *= inv_len

		old_x, old_z := c.position.x, c.position.z

		c.position.x += dir.x * MOVE_SPEED * dt
		c.position.z += dir.z * MOVE_SPEED * dt

		c.position.x = math.clamp(c.position.x, -1, 17)
		c.position.z = math.clamp(c.position.z, -1, 17)

		target_yaw := math.atan2(dir.x, dir.z) / math3d.RAD_PER_DEG
		diff := target_yaw - c.yaw
		for diff > 180 {
			diff -= 360
		}
		for diff < -180 {
			diff += 360
		}
		turn_factor := 1.0 - math.exp(-TURN_STIFFNESS * dt)
		c.yaw += diff * turn_factor

		dx := c.position.x - old_x
		dz := c.position.z - old_z
		c.position.y = FOOT_OFFSET_Y
		return dx * dx + dz * dz > MOVE_EPSILON * MOVE_EPSILON
	}

	c.position.y = FOOT_OFFSET_Y
	return false
}

draw_character :: proc(
	character: Character,
	shader: render.ShaderProgram,
	cam: render.Camera,
	anim_time: f32,
	is_moving: bool,
) {
	render.bind_frame(shader, cam)

	clip_index := character.model.idle_clip_index
	if is_moving {
		walk_index := character.model.walk_clip_index
		if walk_index >= 0 {
			clip_index = walk_index
		}
	}
	if clip_index < 0 || clip_index >= len(character.model.clips) {
		return
	}

	joint_matrices: [render.MAX_JOINTS]math3d.Mat4
	joint_count := render.compute_joint_matrices(
		character.model.rest_poses,
		character.model.rig,
		character.model.clips[clip_index],
		anim_time,
		&joint_matrices,
	)

	transform := character_transform(character)
	transform.scale = {CHARACTER_SCALE, CHARACTER_SCALE, CHARACTER_SCALE}
	render.draw_skinned_model_at(
		character.model,
		shader,
		transform,
		&joint_matrices,
		joint_count,
	)
}

delete_character :: proc(character: Character) {
	render.delete_skinned_model(character.model)
}
