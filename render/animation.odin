package render

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

import "../math3d"

MAX_JOINTS :: 64
WALK_STRIDE_SAMPLES :: 48
MIN_WALK_SPEED :: f32(0.1)

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
sample_global_xz :: proc(
	rest_poses: []NodePose,
	node_index: int,
	clip: AnimationClip,
	time: f32,
) -> (f32, f32, bool) {
	if node_index < 0 || node_index >= len(rest_poses) {
		return 0, 0, false
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
	x := global[0][3]
	z := global[2][3]
	if x == 0 && z == 0 && (global[3][0] != 0 || global[3][2] != 0) {
		x = global[3][0]
		z = global[3][2]
	}
	return x, z, true
}

@(private="file")
root_translation_stride_xz :: proc(clip: AnimationClip) -> f32 {
	best: f32 = 0
	for channel in clip.channels {
		if channel.path != .Translation {
			continue
		}
		key_count := len(channel.key_times)
		if key_count < 2 {
			continue
		}
		base := 0
		end := key_count - 1
		if base * 3 + 2 >= len(channel.key_values) || end * 3 + 2 >= len(channel.key_values) {
			continue
		}
		dx := channel.key_values[end * 3 + 0] - channel.key_values[base * 3 + 0]
		dz := channel.key_values[end * 3 + 2] - channel.key_values[base * 3 + 2]
		dist := math.sqrt(dx * dx + dz * dz)
		if dist > best {
			best = dist
		}
	}
	return best
}

@(private="file")
foot_forward_stride :: proc(
	rest_poses: []NodePose,
	node_names: []string,
	clip: AnimationClip,
	foot_name: string,
	hips_index: int,
) -> f32 {
	foot_index := find_node_index_by_name(node_names, foot_name)
	if foot_index < 0 || hips_index < 0 || clip.duration <= 0 {
		return 0
	}

	min_offset: f32 = 0
	max_offset: f32 = 0
	found := false

	for i in 0 ..= WALK_STRIDE_SAMPLES {
		t := clip.duration * f32(i) / f32(WALK_STRIDE_SAMPLES)
		foot_x, foot_z, foot_ok := sample_global_xz(rest_poses, foot_index, clip, t)
		hip_x, hip_z, hip_ok := sample_global_xz(rest_poses, hips_index, clip, t)
		if !foot_ok || !hip_ok {
			continue
		}

		// Model forward is +Z; measure foot excursion relative to hips.
		offset := foot_z - hip_z
		if !found {
			min_offset = offset
			max_offset = offset
			found = true
		} else {
			min_offset = min(min_offset, offset)
			max_offset = max(max_offset, offset)
		}
		_ = foot_x
		_ = hip_x
		_ = hip_z
	}

	if !found {
		return 0
	}
	result := max_offset - min_offset
	return result
}

// Stride per walk cycle from foot/hip joint sampling; speed = stride / clip.duration.
derive_walk_speed :: proc(
	clip: AnimationClip,
	rest_poses: []NodePose,
	node_names: []string,
) -> f32 {
	if clip.duration <= 0 {
		return MIN_WALK_SPEED
	}

	stride := root_translation_stride_xz(clip)
	if stride <= 0.001 {
		hips_index := find_node_index_by_name(node_names, "hips")
		if hips_index < 0 {
			hips_index = find_node_index_by_name(node_names, "root")
		}
		stride = foot_forward_stride(rest_poses, node_names, clip, "foot.l", hips_index)
		stride += foot_forward_stride(rest_poses, node_names, clip, "foot.r", hips_index)
	}

	if stride <= 0.001 {
		return MIN_WALK_SPEED
	}

	speed := stride / clip.duration
	fmt.println(fmt.tprintf(
		"Derived walk speed from %s: stride=%.3f duration=%.3f speed=%.3f u/s",
		clip.name,
		stride,
		clip.duration,
		speed,
	))
	return speed
}
