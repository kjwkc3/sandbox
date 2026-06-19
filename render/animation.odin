package render

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

import "../math3d"

MAX_JOINTS :: 64
WALK_STRIDE_SAMPLES :: 48
MIN_WALK_SPEED :: f32(0.1)
// KayKit rig bones are short; skinned Knight mesh bind height is ~2.36 world units.
REFERENCE_CHARACTER_HEIGHT :: f32(2.36)

AnimPath :: enum {
	Translation,
	Rotation,
	Scale,
}

AnimChannel :: struct {
	node_index:    int,
	path:          AnimPath,
	key_times:     []f32,
	key_values:    []f32,
	interpolation: cgltf_interpolation,
}

cgltf_interpolation :: enum {
	Linear,
	Step,
	Cubic,
}

AnimationClip :: struct {
	name:     string,
	duration: f32,
	channels: []AnimChannel,
}

NodePose :: struct {
	translation:     [3]f32,
	rotation:        [4]f32,
	scale:           [3]f32,
	has_translation: bool,
	has_rotation:    bool,
	has_scale:       bool,
	parent_index:    int,
}

SkinRig :: struct {
	joint_count:           int,
	joint_node_indices:    []int,
	inverse_bind_matrices: []math3d.Mat4,
}

find_clip_by_name :: proc(clips: []AnimationClip, name: string) -> int {
	lower := strings.to_lower(name, context.temp_allocator)
	for clip, i in clips {
		if strings.to_lower(clip.name, context.temp_allocator) == lower {
			return i
		}
	}
	return -1
}

find_idle_clip_index :: proc(clips: []AnimationClip) -> int {
	for clip, i in clips {
		if strings.to_lower(clip.name, context.temp_allocator) == "idle" {
			return i
		}
	}
	if len(clips) > 0 {
		return 0
	}
	return -1
}

// KayKit Knight GLB exposes Walking_A/B/C; Walking_A is the default forward walk cycle.
find_walk_clip_index :: proc(clips: []AnimationClip) -> int {
	if idx := find_clip_by_name(clips, "Walking_A"); idx >= 0 {
		return idx
	}
	if idx := find_clip_by_name(clips, "Walk"); idx >= 0 {
		return idx
	}
	for clip, i in clips {
		lower := strings.to_lower(clip.name, context.temp_allocator)
		if strings.contains(lower, "walking") {
			return i
		}
	}
	return find_idle_clip_index(clips)
}

find_jump_start_clip_index :: proc(clips: []AnimationClip) -> int {
	if idx := find_clip_by_name(clips, "Jump_Start"); idx >= 0 {
		return idx
	}
	return -1
}

find_jump_idle_clip_index :: proc(clips: []AnimationClip) -> int {
	if idx := find_clip_by_name(clips, "Jump_Idle"); idx >= 0 {
		return idx
	}
	return -1
}

find_jump_land_clip_index :: proc(clips: []AnimationClip) -> int {
	if idx := find_clip_by_name(clips, "Jump_Land"); idx >= 0 {
		return idx
	}
	return -1
}

sample_channel :: proc(channel: AnimChannel, time: f32, pose: ^NodePose) {
	if len(channel.key_times) == 0 {
		return
	}

	key_count := len(channel.key_times)
	if key_count == 1 {
		apply_channel_value(channel, 0, pose)
		return
	}

	if time <= channel.key_times[0] {
		apply_channel_value(channel, 0, pose)
		return
	}
	last := key_count - 1
	if time >= channel.key_times[last] {
		apply_channel_value(channel, last, pose)
		return
	}

	key_index := 0
	for i in 0 ..< last {
		if time >= channel.key_times[i] && time < channel.key_times[i + 1] {
			key_index = i
			break
		}
	}

	t0 := channel.key_times[key_index]
	t1 := channel.key_times[key_index + 1]
	alpha: f32 = 0
	if t1 > t0 {
		alpha = (time - t0) / (t1 - t0)
	}

	if channel.interpolation == .Step {
		apply_channel_value(channel, key_index, pose)
		return
	}

	apply_channel_lerp(channel, key_index, key_index + 1, alpha, pose)
}

apply_channel_value :: proc(channel: AnimChannel, key_index: int, pose: ^NodePose) {
	#partial switch channel.path {
	case .Translation:
		base := key_index * 3
		if base + 2 < len(channel.key_values) {
			pose.translation = {
				channel.key_values[base + 0],
				channel.key_values[base + 1],
				channel.key_values[base + 2],
			}
			pose.has_translation = true
		}
	case .Rotation:
		base := key_index * 4
		if base + 3 < len(channel.key_values) {
			pose.rotation = {
				channel.key_values[base + 0],
				channel.key_values[base + 1],
				channel.key_values[base + 2],
				channel.key_values[base + 3],
			}
			pose.has_rotation = true
		}
	case .Scale:
		base := key_index * 3
		if base + 2 < len(channel.key_values) {
			pose.scale = {
				channel.key_values[base + 0],
				channel.key_values[base + 1],
				channel.key_values[base + 2],
			}
			pose.has_scale = true
		}
	}
}

apply_channel_lerp :: proc(
	channel: AnimChannel,
	a_index, b_index: int,
	alpha: f32,
	pose: ^NodePose,
) {
	#partial switch channel.path {
	case .Translation:
		a_base := a_index * 3
		b_base := b_index * 3
		if b_base + 2 < len(channel.key_values) {
			pose.translation = {
				math.lerp(channel.key_values[a_base + 0], channel.key_values[b_base + 0], alpha),
				math.lerp(channel.key_values[a_base + 1], channel.key_values[b_base + 1], alpha),
				math.lerp(channel.key_values[a_base + 2], channel.key_values[b_base + 2], alpha),
			}
			pose.has_translation = true
		}
	case .Rotation:
		a_base := a_index * 4
		b_base := b_index * 4
		if b_base + 3 < len(channel.key_values) {
			qa: math3d.Quat
			qb: math3d.Quat
			qa.x = channel.key_values[a_base + 0]
			qa.y = channel.key_values[a_base + 1]
			qa.z = channel.key_values[a_base + 2]
			qa.w = channel.key_values[a_base + 3]
			qb.x = channel.key_values[b_base + 0]
			qb.y = channel.key_values[b_base + 1]
			qb.z = channel.key_values[b_base + 2]
			qb.w = channel.key_values[b_base + 3]
			q := linalg.quaternion_nlerp_f32(qa, qb, alpha)
			pose.rotation = {q.x, q.y, q.z, q.w}
			pose.has_rotation = true
		}
	case .Scale:
		a_base := a_index * 3
		b_base := b_index * 3
		if b_base + 2 < len(channel.key_values) {
			pose.scale = {
				math.lerp(channel.key_values[a_base + 0], channel.key_values[b_base + 0], alpha),
				math.lerp(channel.key_values[a_base + 1], channel.key_values[b_base + 1], alpha),
				math.lerp(channel.key_values[a_base + 2], channel.key_values[b_base + 2], alpha),
			}
			pose.has_scale = true
		}
	}
}

sample_clip :: proc(clip: AnimationClip, time: f32, poses: []NodePose) {
	clip_time := time
	if clip.duration > 0 {
		clip_time = time - math.floor(time / clip.duration) * clip.duration
	}

	for channel in clip.channels {
		if channel.node_index < 0 || channel.node_index >= len(poses) {
			continue
		}
		sample_channel(channel, clip_time, &poses[channel.node_index])
	}
}

pose_local_matrix :: proc(pose: NodePose) -> math3d.Mat4 {
	t := pose.has_translation ? pose.translation : math3d.Vec3{0, 0, 0}
	q: math3d.Quat
	if pose.has_rotation {
		q.x = pose.rotation[0]
		q.y = pose.rotation[1]
		q.z = pose.rotation[2]
		q.w = pose.rotation[3]
	} else {
		q = linalg.QUATERNIONF32_IDENTITY
	}
	s := pose.has_scale ? pose.scale : math3d.Vec3{1, 1, 1}

	T := math3d.translate(t)
	R := math3d.quat_to_matrix(q)
	S := math3d.scale(s)
	return math3d.mul(math3d.mul(T, R), S)
}

compute_global_transform :: proc(
	index: int,
	poses: []NodePose,
	locals: []math3d.Mat4,
	globals: []math3d.Mat4,
	visited: []bool,
) {
	if visited[index] {
		return
	}
	parent := poses[index].parent_index
	if parent >= 0 && parent < len(poses) {
		if !visited[parent] {
			compute_global_transform(parent, poses, locals, globals, visited)
		}
		globals[index] = math3d.mul(globals[parent], locals[index])
	} else {
		globals[index] = locals[index]
	}
	visited[index] = true
}

compute_joint_matrices :: proc(
	rest_poses: []NodePose,
	rig: SkinRig,
	clip: AnimationClip,
	time: f32,
	out: ^[MAX_JOINTS]math3d.Mat4,
) -> int {
	poses := make([]NodePose, len(rest_poses), context.temp_allocator)
	copy(poses, rest_poses)
	sample_clip(clip, time, poses)

	locals := make([]math3d.Mat4, len(poses), context.temp_allocator)
	for i in 0 ..< len(poses) {
		locals[i] = pose_local_matrix(poses[i])
	}

	globals := make([]math3d.Mat4, len(poses), context.temp_allocator)
	visited := make([]bool, len(poses), context.temp_allocator)
	for i in 0 ..< len(poses) {
		compute_global_transform(i, poses, locals, globals, visited)
	}

	count := min(rig.joint_count, MAX_JOINTS)
	for i in 0 ..< count {
		node_idx := rig.joint_node_indices[i]
		global := math3d.identity()
		if node_idx >= 0 && node_idx < len(globals) {
			global = globals[node_idx]
		}
		out[i] = math3d.mul(global, rig.inverse_bind_matrices[i])
	}
	return count
}

find_node_index_by_name :: proc(node_names: []string, name: string) -> int {
	lower := strings.to_lower(name, context.temp_allocator)
	for node_name, i in node_names {
		if strings.to_lower(node_name, context.temp_allocator) == lower {
			return i
		}
	}
	return -1
}

@(private="file")
matrix_translation :: proc(m: math3d.Mat4) -> math3d.Vec3 {
	return {m[3][0], m[3][1], m[3][2]}
}

@(private="file")
sample_rest_global_position :: proc(
	rest_poses: []NodePose,
	node_index: int,
) -> (math3d.Vec3, bool) {
	if node_index < 0 || node_index >= len(rest_poses) {
		return {}, false
	}

	locals := make([]math3d.Mat4, len(rest_poses), context.temp_allocator)
	for i in 0 ..< len(rest_poses) {
		locals[i] = pose_local_matrix(rest_poses[i])
	}

	globals := make([]math3d.Mat4, len(rest_poses), context.temp_allocator)
	visited := make([]bool, len(rest_poses), context.temp_allocator)
	for i in 0 ..< len(rest_poses) {
		compute_global_transform(i, rest_poses, locals, globals, visited)
	}

	global := globals[node_index]
	return matrix_translation(global), true
}

@(private="file")
sample_global_position :: proc(
	rest_poses: []NodePose,
	node_index: int,
	clip: AnimationClip,
	time: f32,
) -> (math3d.Vec3, bool) {
	if node_index < 0 || node_index >= len(rest_poses) {
		return {}, false
	}

	poses := make([]NodePose, len(rest_poses), context.temp_allocator)
	copy(poses, rest_poses)
	sample_clip(clip, time, poses)

	locals := make([]math3d.Mat4, len(poses), context.temp_allocator)
	for i in 0 ..< len(poses) {
		locals[i] = pose_local_matrix(poses[i])
	}

	globals := make([]math3d.Mat4, len(poses), context.temp_allocator)
	visited := make([]bool, len(poses), context.temp_allocator)
	for i in 0 ..< len(poses) {
		compute_global_transform(i, poses, locals, globals, visited)
	}

	global := globals[node_index]
	return matrix_translation(global), true
}

@(private="file")
sample_global_xz :: proc(
	rest_poses: []NodePose,
	node_index: int,
	clip: AnimationClip,
	time: f32,
) -> (f32, f32, bool) {
	pos, ok := sample_global_position(rest_poses, node_index, clip, time)
	return pos.x, pos.z, ok
}

@(private="file")
find_foot_node_index :: proc(node_names: []string, side: rune) -> int {
	toe_name := side == 'l' ? "toes.l" : "toes.r"
	foot_name := side == 'l' ? "foot.l" : "foot.r"
	if idx := find_node_index_by_name(node_names, toe_name); idx >= 0 {
		return idx
	}
	return find_node_index_by_name(node_names, foot_name)
}

// Map rig bone units to world units via standing height vs skeleton leg length.
@(private="file")
derive_rig_to_world_scale :: proc(
	rest_poses: []NodePose,
	node_names: []string,
	reference_height: f32,
) -> f32 {
	hips_index := find_node_index_by_name(node_names, "hips")
	foot_index := find_node_index_by_name(node_names, "foot.l")
	if foot_index < 0 {
		foot_index = find_node_index_by_name(node_names, "foot.r")
	}
	if hips_index < 0 || foot_index < 0 {
		return 1.0
	}

	hip_pos, hip_ok := sample_rest_global_position(rest_poses, hips_index)
	foot_pos, foot_ok := sample_rest_global_position(rest_poses, foot_index)
	if !hip_ok || !foot_ok {
		return 1.0
	}

	dx := hip_pos.x - foot_pos.x
	dy := hip_pos.y - foot_pos.y
	dz := hip_pos.z - foot_pos.z
	leg_length := math.abs(dy)
	if leg_length <= 0.001 {
		leg_length = math.sqrt(dx * dx + dy * dy + dz * dz)
	}
	if leg_length <= 0.001 {
		return 1.0
	}
	return reference_height / leg_length
}

// Forward (Z) swing relative to hips during one cycle — one step length per foot.
@(private="file")
foot_forward_step_z :: proc(
	rest_poses: []NodePose,
	node_names: []string,
	foot_index: int,
	hips_index: int,
	clip: AnimationClip,
) -> f32 {
	if foot_index < 0 || hips_index < 0 || clip.duration <= 0 {
		return 0
	}

	min_offset: f32 = 0
	max_offset: f32 = 0
	found := false

	for i in 0 ..= WALK_STRIDE_SAMPLES {
		t := clip.duration * f32(i) / f32(WALK_STRIDE_SAMPLES)
		foot_pos, foot_ok := sample_global_position(rest_poses, foot_index, clip, t)
		hip_pos, hip_ok := sample_global_position(rest_poses, hips_index, clip, t)
		if !foot_ok || !hip_ok {
			continue
		}

		offset := foot_pos.z - hip_pos.z
		if !found {
			min_offset = offset
			max_offset = offset
			found = true
		} else {
			min_offset = min(min_offset, offset)
			max_offset = max(max_offset, offset)
		}
	}

	if !found {
		return 0
	}
	return max_offset - min_offset
}

// Max XZ displacement from bind-pose rest for one foot/toe over the clip.
@(private="file")
foot_xz_excursion :: proc(
	rest_poses: []NodePose,
	foot_index: int,
	clip: AnimationClip,
) -> f32 {
	if foot_index < 0 || clip.duration <= 0 {
		return 0
	}

	rest_pos, rest_ok := sample_rest_global_position(rest_poses, foot_index)
	if !rest_ok {
		return 0
	}
	rest_x := rest_pos.x
	rest_z := rest_pos.z

	max_excursion: f32 = 0
	for i in 0 ..= WALK_STRIDE_SAMPLES {
		t := clip.duration * f32(i) / f32(WALK_STRIDE_SAMPLES)
		pos, ok := sample_global_position(rest_poses, foot_index, clip, t)
		if !ok {
			continue
		}
		dx := pos.x - rest_x
		dz := pos.z - rest_z
		excursion := math.sqrt(dx * dx + dz * dz)
		max_excursion = max(max_excursion, excursion)
	}
	return max_excursion
}

// In-place walk: one cycle advances by both feet's peak forward steps.
@(private="file")
foot_cycle_stride_bone_units :: proc(
	rest_poses: []NodePose,
	node_names: []string,
	clip: AnimationClip,
) -> f32 {
	hips_index := find_node_index_by_name(node_names, "hips")
	if hips_index < 0 {
		hips_index = find_node_index_by_name(node_names, "root")
	}

	left_index := find_foot_node_index(node_names, 'l')
	right_index := find_foot_node_index(node_names, 'r')

	// Prefer toe contact bones; measure forward step relative to hips per foot.
	left_step := foot_forward_step_z(rest_poses, node_names, left_index, hips_index, clip)
	right_step := foot_forward_step_z(rest_poses, node_names, right_index, hips_index, clip)
	stride := left_step + right_step

	if stride > 0.001 {
		return stride
	}

	// Fallback: bind-pose XZ excursion summed for both feet.
	left_excursion := foot_xz_excursion(rest_poses, left_index, clip)
	right_excursion := foot_xz_excursion(rest_poses, right_index, clip)
	if left_excursion <= 0.001 && right_excursion <= 0.001 {
		return 0
	}
	return left_excursion + right_excursion
}

// In-place walk speed from toe/foot XZ excursion scaled to world units.
derive_walk_speed :: proc(
	clip: AnimationClip,
	rest_poses: []NodePose,
	node_names: []string,
	character_scale: f32 = 1.0,
) -> f32 {
	if clip.duration <= 0 {
		return MIN_WALK_SPEED
	}

	stride_bone := foot_cycle_stride_bone_units(rest_poses, node_names, clip)
	if stride_bone <= 0.001 {
		fmt.println(fmt.tprintf(
			"Warning: could not measure walk stride for %s; using minimum speed",
			clip.name,
		))
		return MIN_WALK_SPEED
	}

	rig_to_world := derive_rig_to_world_scale(rest_poses, node_names, REFERENCE_CHARACTER_HEIGHT)
	world_stride := stride_bone * rig_to_world * character_scale
	speed := world_stride / clip.duration

	left_name := "toes.l"
	if find_node_index_by_name(node_names, left_name) < 0 {
		left_name = "foot.l"
	}
	right_name := "toes.r"
	if find_node_index_by_name(node_names, right_name) < 0 {
		right_name = "foot.r"
	}
	left_idx := find_foot_node_index(node_names, 'l')
	right_idx := find_foot_node_index(node_names, 'r')
	hips_idx := find_node_index_by_name(node_names, "hips")
	left_step := foot_forward_step_z(rest_poses, node_names, left_idx, hips_idx, clip)
	right_step := foot_forward_step_z(rest_poses, node_names, right_idx, hips_idx, clip)
	fmt.println(fmt.tprintf(
		"Derived walk speed from %s: left(%s)=%.3f right(%s)=%.3f stride_bone=%.3f rig_scale=%.3f char_scale=%.3f world_stride=%.3f duration=%.3f speed=%.3f u/s",
		clip.name,
		left_name,
		left_step,
		right_name,
		right_step,
		stride_bone,
		rig_to_world,
		character_scale,
		world_stride,
		clip.duration,
		speed,
	))
	return speed
}
