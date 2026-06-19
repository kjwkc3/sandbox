package character

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../collision"
import "../math3d"
import "../render"

KNIGHT_MESH :: "assets/character/meshes/Knight.glb"

// KayKit origin sits below the floor plane; lift so boots rest on y=0 tiles.
FOOT_OFFSET_Y :: f32(1.12)
CHARACTER_YAW :: f32(0)
CHARACTER_SCALE :: f32(1.0)
TURN_STIFFNESS :: f32(12.0)
MOVE_EPSILON :: f32(0.001)

JUMP_VELOCITY :: f32(6.5)
GRAVITY :: f32(-24.0)
JUMP_START_DURATION :: f32(0.6)
JUMP_LAND_DURATION :: f32(0.67)

Jump_Phase :: enum {
	Grounded,
	Jump_Start,
	Jump_Idle,
	Jump_Land,
}

Character :: struct {
	model:              render.SkinnedModel,
	position:           math3d.Vec3,
	yaw:                f32,
	move_speed:         f32,
	derived_walk_speed: f32,
	velocity_y:         f32,
	jump_phase:         Jump_Phase,
	jump_phase_time:    f32,
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

	derived_speed: f32 = 1.0
	if model.walk_clip_index >= 0 && model.walk_clip_index < len(model.clips) {
		walk_clip := model.clips[model.walk_clip_index]
		derived_speed = render.derive_walk_speed(
			walk_clip,
			model.rest_poses,
			model.node_names,
			CHARACTER_SCALE,
		)
	} else {
		fmt.println("Warning: walk clip not found; using default move speed")
	}

	return Character{
		model = model,
		position = {8, FOOT_OFFSET_Y, 8},
		yaw = CHARACTER_YAW,
		move_speed = derived_speed,
		derived_walk_speed = derived_speed,
		jump_phase = .Grounded,
	}, true
}

walk_anim_speed_scale :: proc(c: Character) -> f32 {
	if c.derived_walk_speed <= MOVE_EPSILON {
		return 1.0
	}
	return c.move_speed / c.derived_walk_speed
}

character_transform :: proc(c: Character) -> render.Transform {
	return render.transform_with_yaw(c.position, c.yaw)
}

@(private="file")
smooth_yaw_toward :: proc(c: ^Character, target_yaw: f32, dt: f32) {
	diff := target_yaw - c.yaw
	for diff > 180 {
		diff -= 360
	}
	for diff < -180 {
		diff += 360
	}
	turn_factor := 1.0 - math.exp(-TURN_STIFFNESS * dt)
	c.yaw += diff * turn_factor
}

@(private="file")
is_airborne :: proc(c: Character) -> bool {
	return c.position.y > FOOT_OFFSET_Y + MOVE_EPSILON
}

@(private="file")
can_jump :: proc(c: Character) -> bool {
	if c.jump_phase == .Jump_Start || c.jump_phase == .Jump_Idle {
		return false
	}
	if c.jump_phase == .Jump_Land {
		return false
	}
	return c.velocity_y <= MOVE_EPSILON && !is_airborne(c)
}

try_jump :: proc(c: ^Character) {
	if !can_jump(c^) {
		return
	}
	c.velocity_y = JUMP_VELOCITY
	c.jump_phase = .Jump_Start
	c.jump_phase_time = 0
}

@(private="file")
advance_jump_phase :: proc(c: ^Character, dt: f32) {
	c.jump_phase_time += dt

	switch c.jump_phase {
	case .Jump_Start:
		if c.jump_phase_time >= JUMP_START_DURATION {
			if is_airborne(c^) {
				c.jump_phase = .Jump_Idle
			} else if c.jump_phase == .Jump_Start {
				c.jump_phase = .Grounded
			}
			c.jump_phase_time = 0
		}
	case .Jump_Land:
		if c.jump_phase_time >= JUMP_LAND_DURATION {
			c.jump_phase = .Grounded
			c.jump_phase_time = 0
		}
	case .Grounded, .Jump_Idle:
		break
	}
}

update_character_physics :: proc(c: ^Character, dt: f32) {
	was_airborne := is_airborne(c^) || c.jump_phase == .Jump_Idle ||
		(c.jump_phase == .Jump_Start && c.velocity_y > MOVE_EPSILON)

	if c.jump_phase == .Jump_Start || c.jump_phase == .Jump_Idle || c.velocity_y != 0 || was_airborne {
		c.velocity_y += GRAVITY * dt
		c.position.y += c.velocity_y * dt
	}

	if c.position.y <= FOOT_OFFSET_Y {
		c.position.y = FOOT_OFFSET_Y
		if c.velocity_y < 0 && was_airborne {
			c.jump_phase = .Jump_Land
			c.jump_phase_time = 0
		}
		c.velocity_y = 0
	}

	advance_jump_phase(c, dt)
}

move_character :: proc(
	c: ^Character,
	move_dir: math3d.Vec3,
	dt: f32,
	walls: []collision.AABB,
) -> bool {
	dir := move_dir
	dir.y = 0

	len_sq := dir.x * dir.x + dir.z * dir.z
	if len_sq > MOVE_EPSILON * MOVE_EPSILON {
		inv_len := 1.0 / math.sqrt(len_sq)
		dir.x *= inv_len
		dir.z *= inv_len

		old_x, old_z := c.position.x, c.position.z

		delta_x := dir.x * c.move_speed * dt
		delta_z := dir.z * c.move_speed * dt

		capsule := collision.make_capsule_at(old_x, old_z)
		resolved := collision.resolve_capsule_xz_move(capsule, walls, delta_x, delta_z)
		c.position.x = resolved.x
		c.position.z = resolved.z

		dx := c.position.x - old_x
		dz := c.position.z - old_z
		return dx * dx + dz * dz > MOVE_EPSILON * MOVE_EPSILON
	}

	return false
}

face_toward_point :: proc(c: ^Character, target: math3d.Vec3, dt: f32) {
	dx := target.x - c.position.x
	dz := target.z - c.position.z
	if dx * dx + dz * dz <= MOVE_EPSILON * MOVE_EPSILON {
		return
	}
	target_yaw := math.atan2(dx, dz) / math3d.RAD_PER_DEG
	smooth_yaw_toward(c, target_yaw, dt)
}

face_toward_dir :: proc(c: ^Character, dir: math3d.Vec3, dt: f32) {
	d := dir
	d.y = 0
	len_sq := d.x * d.x + d.z * d.z
	if len_sq <= MOVE_EPSILON * MOVE_EPSILON {
		return
	}
	target_yaw := math.atan2(d.x, d.z) / math3d.RAD_PER_DEG
	smooth_yaw_toward(c, target_yaw, dt)
}

@(private="file")
select_jump_clip_index :: proc(c: Character) -> int {
	switch c.jump_phase {
	case .Jump_Start:
		return c.model.jump_start_clip_index
	case .Jump_Idle:
		return c.model.jump_idle_clip_index
	case .Jump_Land:
		return c.model.jump_land_clip_index
	case .Grounded:
		return -1
	}
	return -1
}

draw_character :: proc(
	character: Character,
	shader: render.ShaderProgram,
	cam: render.Camera,
	anim_time: f32,
	is_moving: bool,
) {
	render.bind_frame(shader, cam)

	clip_index := -1
	playback_time := anim_time
	use_walk_scale := false

	if jump_clip := select_jump_clip_index(character); jump_clip >= 0 {
		clip_index = jump_clip
		switch character.jump_phase {
		case .Jump_Start, .Jump_Land:
			playback_time = character.jump_phase_time
		case .Jump_Idle:
			playback_time = anim_time
		case .Grounded:
			break
		}
	} else if character.jump_phase == .Grounded {
		clip_index = character.model.idle_clip_index
		if is_moving {
			walk_index := character.model.walk_clip_index
			if walk_index >= 0 {
				clip_index = walk_index
				use_walk_scale = true
			}
		}
	}

	if clip_index < 0 || clip_index >= len(character.model.clips) {
		return
	}

	if use_walk_scale {
		playback_time *= walk_anim_speed_scale(character)
	}

	joint_matrices: [render.MAX_JOINTS]math3d.Mat4
	joint_count := render.compute_joint_matrices(
		character.model.rest_poses,
		character.model.rig,
		character.model.clips[clip_index],
		playback_time,
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
