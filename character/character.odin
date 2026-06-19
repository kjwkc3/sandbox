package character

import "core:fmt"
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

Character :: struct {
	model: render.SkinnedModel,
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
	return Character{model = model}, true
}

character_transform :: proc() -> render.Transform {
	return render.transform_with_yaw({8, FOOT_OFFSET_Y, 8}, CHARACTER_YAW)
}

draw_character :: proc(
	character: Character,
	shader: render.ShaderProgram,
	cam: render.Camera,
	anim_time: f32,
) {
	render.bind_frame(shader, cam)

	clip_index := character.model.idle_clip_index
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

	transform := character_transform()
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
