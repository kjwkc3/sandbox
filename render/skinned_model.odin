package render

import "core:c"
import "core:fmt"

import cgltf "vendor:cgltf"

import "../math3d"

SkinnedModel :: struct {
	meshes:           []SkinnedMesh,
	materials:        []Material,
	material_indices: []int,
	rig:              SkinRig,
	rest_poses:       []NodePose,
	clips:            []AnimationClip,
	idle_clip_index:  int,
}

has_skinned_attributes :: proc(attributes: []cgltf.attribute) -> bool {
	has_joints := false
	has_weights := false
	for attr in attributes {
		if attr.type == .joints {
			has_joints = true
		}
		if attr.type == .weights {
			has_weights = true
		}
	}
	return has_joints && has_weights
}

extract_accessor_u32 :: proc(
	attributes: []cgltf.attribute,
	attribute_type: cgltf.attribute_type,
	allocator := context.temp_allocator,
) -> []u32 {
	for attr in attributes {
		if attr.type == attribute_type {
			acc := attr.data
			component_count := cgltf.num_components(acc.type)
			result := make([]u32, acc.count * component_count, allocator)
			for i in 0 ..< acc.count {
				values: [4]c.uint
				_ = cgltf.accessor_read_uint(
					acc,
					uint(i),
					raw_data(values[:]),
					size_of(c.uint),
				)
				for j in 0 ..< component_count {
					result[i * component_count + j] = u32(values[j])
				}
			}
			return result
		}
	}
	return nil
}

load_image_texture :: proc(
	data: ^cgltf.data,
	gltf_path: string,
	tex: ^cgltf.texture,
	cache: ^TextureCache,
	allocator := context.allocator,
) -> u32 {
	if tex == nil || tex.image_ == nil {
		return 0
	}

	image := tex.image_
	if image.uri != nil {
		image_path := resolve_image_uri(gltf_path, image.uri)
		if image_path != "" {
			return load_texture(cache, image_path, allocator)
		}
	}

	if image.buffer_view != nil && image.buffer_view.buffer != nil {
		buffer := image.buffer_view.buffer
		if buffer.data == nil {
			return 0
		}
		offset := image.buffer_view.offset
		size := image.buffer_view.size
		bytes := make([]u8, size, context.temp_allocator)
		base_addr := uintptr(buffer.data) + uintptr(offset)
		for k in 0 ..< int(size) {
			bytes[k] = (^u8)(base_addr + uintptr(k))^
		}

		image_index := cgltf.image_index(data, image)
		key := fmt.tprintf("embedded:%s:%d", gltf_path, image_index)
		return load_texture_from_file_bytes(cache, key, bytes, allocator)
	}

	return 0
}

load_skinned_material_textures :: proc(
	data: ^cgltf.data,
	gltf_path: string,
	cache: ^TextureCache,
	model: ^SkinnedModel,
) {
	for i in 0 ..< len(data.materials) {
		mat := &data.materials[i]
		model.materials[i] = Material{
			base_color = {1, 1, 1, 1},
		}
		if mat.has_pbr_metallic_roughness {
			model.materials[i].base_color = mat.pbr_metallic_roughness.base_color_factor
			tex := mat.pbr_metallic_roughness.base_color_texture.texture
			if tex != nil {
				tex_id := load_image_texture(data, gltf_path, tex, cache)
				if tex_id != 0 {
					model.materials[i].base_color_tex = tex_id
					model.materials[i].has_texture = true
				}
			}
		}
	}
}

parse_node_poses :: proc(data: ^cgltf.data, allocator := context.allocator) -> []NodePose {
	poses := make([]NodePose, len(data.nodes), allocator)
	for i in 0 ..< len(data.nodes) {
		node := &data.nodes[i]
		pose := NodePose{parent_index = -1, scale = {1, 1, 1}, rotation = {0, 0, 0, 1}}

		if node.parent != nil {
			pose.parent_index = int(cgltf.node_index(data, node.parent))
		}
		if node.has_translation {
			pose.translation = node.translation
			pose.has_translation = true
		}
		if node.has_rotation {
			pose.rotation = node.rotation
			pose.has_rotation = true
		}
		if node.has_scale {
			pose.scale = node.scale
			pose.has_scale = true
		}
		if node.has_matrix && !node.has_translation && !node.has_rotation && !node.has_scale {
			m := transmute(math3d.Mat4)node.matrix_
			pose.translation = {m[3][0], m[3][1], m[3][2]}
			pose.has_translation = true
			pose.rotation = {0, 0, 0, 1}
			pose.has_rotation = true
			pose.scale = {1, 1, 1}
			pose.has_scale = true
		}

		poses[i] = pose
	}
	return poses
}

parse_skin_rig :: proc(
	data: ^cgltf.data,
	skin: ^cgltf.skin,
	allocator := context.allocator,
) -> SkinRig {
	joint_count := len(skin.joints)
	rig := SkinRig{
		joint_count        = joint_count,
		joint_node_indices = make([]int, joint_count, allocator),
		inverse_bind_matrices = make([]math3d.Mat4, joint_count, allocator),
	}

	for i in 0 ..< joint_count {
		rig.joint_node_indices[i] = int(cgltf.node_index(data, skin.joints[i]))
	}

	if skin.inverse_bind_matrices != nil {
		acc := skin.inverse_bind_matrices
		float_count := acc.count * 16
		floats := make([]f32, float_count, context.temp_allocator)
		_ = cgltf.accessor_unpack_floats(acc, raw_data(floats), float_count)
		for i in 0 ..< joint_count {
			base := i * 16
			mat_arr: [16]f32
			copy(mat_arr[:], floats[base:base + 16])
			rig.inverse_bind_matrices[i] = transmute(math3d.Mat4)mat_arr
		}
	} else {
		for i in 0 ..< joint_count {
			rig.inverse_bind_matrices[i] = math3d.identity()
		}
	}

	return rig
}

map_interpolation :: proc(value: cgltf.interpolation_type) -> cgltf_interpolation {
	#partial switch value {
	case .step:
		return .Step
	case .cubic_spline:
		return .Cubic
	case:
		return .Linear
	}
}

map_anim_path :: proc(value: cgltf.animation_path_type) -> (AnimPath, bool) {
	#partial switch value {
	case .translation:
		return .Translation, true
	case .rotation:
		return .Rotation, true
	case .scale:
		return .Scale, true
	case:
		return .Translation, false
	}
}

parse_animations :: proc(data: ^cgltf.data, allocator := context.allocator) -> []AnimationClip {
	clips := make([]AnimationClip, len(data.animations), allocator)

	for anim_i in 0 ..< len(data.animations) {
		anim := &data.animations[anim_i]
		clip := AnimationClip{
			name = anim.name != nil ? string(anim.name) : fmt.tprintf("anim_%d", anim_i),
		}

		channels := make([dynamic]AnimChannel, allocator)

		for channel in anim.channels {
			path, ok := map_anim_path(channel.target_path)
			if !ok || channel.target_node == nil || channel.sampler == nil {
				continue
			}

			sampler := channel.sampler
			if sampler.input == nil || sampler.output == nil {
				continue
			}

			time_count := sampler.input.count
			times := make([]f32, time_count, allocator)
			_ = cgltf.accessor_unpack_floats(sampler.input, raw_data(times), time_count)

			value_count := sampler.output.count * cgltf.num_components(sampler.output.type)
			values := make([]f32, value_count, allocator)
			_ = cgltf.accessor_unpack_floats(sampler.output, raw_data(values), value_count)

			if time_count > 0 {
				last_time := times[time_count - 1]
				if last_time > clip.duration {
					clip.duration = last_time
				}
			}

			append(
				&channels,
				AnimChannel{
					node_index = int(cgltf.node_index(data, channel.target_node)),
					path = path,
					key_times = times,
					key_values = values,
					interpolation = map_interpolation(sampler.interpolation),
				},
			)
		}

		clip.channels = channels[:]
		clips[anim_i] = clip
	}

	return clips
}

load_skinned_model :: proc(
	path: cstring,
	cache: ^TextureCache,
	allocator := context.allocator,
) -> (
	SkinnedModel,
	bool,
) {
	gltf_path := string(path)

	data, parse_result := cgltf.parse_file({}, path)
	if parse_result != .success || data == nil {
		fmt.printf("cgltf: failed to parse %s\n", path)
		return {}, false
	}
	defer cgltf.free(data)

	load_result := cgltf.load_buffers({}, data, path)
	if load_result != .success {
		fmt.printf("cgltf: failed to load buffers for %s\n", path)
		return {}, false
	}

	model := SkinnedModel{
		materials = make([]Material, len(data.materials), allocator),
		idle_clip_index = 0,
	}

	load_skinned_material_textures(data, gltf_path, cache, &model)
	model.rest_poses = parse_node_poses(data, allocator)
	model.clips = parse_animations(data, allocator)
	model.idle_clip_index = find_idle_clip_index(model.clips)

	skin: ^cgltf.skin
	if len(data.skins) > 0 {
		skin = &data.skins[0]
		model.rig = parse_skin_rig(data, skin, allocator)
	}

	meshes := make([dynamic]SkinnedMesh, allocator)
	material_indices := make([dynamic]int, allocator)

	for mesh_i in 0 ..< len(data.meshes) {
		mesh_data := &data.meshes[mesh_i]
		for prim in mesh_data.primitives {
			if !has_skinned_attributes(prim.attributes) {
				continue
			}

			positions := extract_accessor_f32(prim.attributes, .position)
			if positions == nil {
				continue
			}

			normals := extract_accessor_f32(prim.attributes, .normal)
			texcoords := extract_accessor_f32(prim.attributes, .texcoord)
			joints := extract_accessor_u32(prim.attributes, .joints)
			weights := extract_accessor_f32(prim.attributes, .weights)

			indices: []u32
			if prim.indices != nil {
				idx_count := prim.indices.count
				indices = make([]u32, idx_count, allocator)
				for j in 0 ..< idx_count {
					indices[j] = u32(cgltf.accessor_read_index(prim.indices, j))
				}
			}

			skinned_mesh := create_skinned_mesh(
				positions,
				normals,
				texcoords,
				joints,
				weights,
				indices,
			)
			append(&meshes, skinned_mesh)

			mat_idx := 0
			if prim.material != nil {
				mat_idx = int(cgltf.material_index(data, prim.material))
			}
			append(&material_indices, mat_idx)

			if len(indices) > 0 {
				delete(indices)
			}
		}
	}

	if len(meshes) == 0 {
		fmt.printf("cgltf: no skinned meshes loaded from %s\n", path)
		delete(model.materials)
		delete(model.rig.joint_node_indices)
		delete(model.rig.inverse_bind_matrices)
		delete(model.rest_poses)
		for clip in model.clips {
			for channel in clip.channels {
				delete(channel.key_times)
				delete(channel.key_values)
			}
			delete(clip.channels)
		}
		delete(model.clips)
		return {}, false
	}

	model.meshes = meshes[:]
	model.material_indices = material_indices[:]
	return model, true
}

draw_skinned_model_at :: proc(
	model: SkinnedModel,
	shader: ShaderProgram,
	transform: Transform,
	joint_matrices: ^[MAX_JOINTS]math3d.Mat4,
	joint_count: int,
) {
	joint_array: [MAX_JOINTS * 16]f32
	for i in 0 ..< joint_count {
		mat := mat4_to_array(joint_matrices[i])
		copy(joint_array[i * 16:(i + 1) * 16], mat[:])
	}
	set_mat4_array(shader, "jointMatrices", joint_array[:joint_count * 16], joint_count)

	model_mat := transform_matrix(transform)
	normal_mat := math3d.normal_matrix(model_mat)
	mat_arr := mat4_to_array(model_mat)

	set_mat4(shader, "model", mat_arr)
	set_mat3(shader, "normalMat", mat3_to_array(normal_mat))

	for i in 0 ..< len(model.meshes) {
		mesh := model.meshes[i]
		if mesh.vertex_count <= 0 && !mesh.has_indices {
			continue
		}

		mat_idx := model.material_indices[i]
		if mat_idx < 0 || mat_idx >= len(model.materials) {
			mat_idx = 0
		}
		material := model.materials[mat_idx]

		if material.has_texture {
			set_bool(shader, "useTexture", true)
			set_texture(shader, "baseColorMap", 0, material.base_color_tex)
			set_vec3(shader, "objectColor", {1, 1, 1})
		} else {
			set_bool(shader, "useTexture", false)
			color := material.base_color
			object_color := [3]f32{color[0], color[1], color[2]}
			set_vec3(shader, "objectColor", object_color)
		}

		draw_skinned_mesh(mesh)
	}
}

draw_skinned_model :: proc(
	model: SkinnedModel,
	shader: ShaderProgram,
	cam: Camera,
	anim_time: f32,
) {
	bind_frame(shader, cam)

	clip_index := model.idle_clip_index
	if clip_index < 0 || clip_index >= len(model.clips) {
		return
	}

	joint_matrices: [MAX_JOINTS]math3d.Mat4
	joint_count := compute_joint_matrices(
		model.rest_poses,
		model.rig,
		model.clips[clip_index],
		anim_time,
		&joint_matrices,
	)
	draw_skinned_model_at(model, shader, default_transform(), &joint_matrices, joint_count)
}

delete_skinned_model :: proc(model: SkinnedModel) {
	for mesh in model.meshes {
		delete_skinned_mesh(mesh)
	}
	delete(model.meshes)
	delete(model.materials)
	delete(model.material_indices)
	delete(model.rig.joint_node_indices)
	delete(model.rig.inverse_bind_matrices)
	delete(model.rest_poses)
	for clip in model.clips {
		for channel in clip.channels {
			delete(channel.key_times)
			delete(channel.key_values)
		}
		delete(clip.channels)
	}
	delete(model.clips)
}
