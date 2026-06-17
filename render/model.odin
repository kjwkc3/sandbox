package render

import "core:fmt"
import "core:math/linalg"
import cgltf "vendor:cgltf"

import "../math3d"

Model :: struct {
	meshes:           []Mesh,
	materials:        []Material,
	transforms:       []Transform,
	material_indices: []int,
}

Material :: struct {
	base_color: [4]f32,
}

Transform :: struct {
	position: [3]f32,
	rotation: [4]f32,
	scale:    [3]f32,
}

default_transform :: proc() -> Transform {
	return Transform{
		position = {0, 0, 0},
		rotation = {0, 0, 0, 1},
		scale    = {1, 1, 1},
	}
}

transform_matrix :: proc(t: Transform) -> math3d.Mat4 {
	T := math3d.translate(t.position)
	S := math3d.scale(t.scale)
	return math3d.mul(T, S)
}

mat4_to_array :: proc(m: math3d.Mat4) -> [16]f32 {
	return transmute([16]f32)m
}

mat3_to_array :: proc(m: linalg.Matrix3f32) -> [9]f32 {
	return transmute([9]f32)m
}

load_model :: proc(path: cstring, allocator := context.allocator) -> (Model, bool) {
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

	model := Model{
		meshes            = make([]Mesh, len(data.meshes), allocator),
		materials         = make([]Material, len(data.materials), allocator),
		transforms        = make([]Transform, len(data.meshes), allocator),
		material_indices  = make([]int, len(data.meshes), allocator),
	}

	for i in 0 ..< len(data.materials) {
		mat := &data.materials[i]
		model.materials[i] = Material{
			base_color = {1, 1, 1, 1},
		}
		if mat.has_pbr_metallic_roughness {
			model.materials[i].base_color = mat.pbr_metallic_roughness.base_color_factor
		}
	}

	for i in 0 ..< len(data.meshes) {
		mesh_data := &data.meshes[i]
		model.transforms[i] = default_transform()
		model.material_indices[i] = 0

		if len(mesh_data.primitives) == 0 {
			continue
		}
		prim := mesh_data.primitives[0]

		positions := extract_accessor_f32(prim.attributes, .position)
		if positions == nil {
			fmt.printf("cgltf: mesh %d has no positions\n", i)
			continue
		}

		normals := extract_accessor_f32(prim.attributes, .normal)

		indices: []u32
		if prim.indices != nil {
			idx_count := prim.indices.count
			indices = make([]u32, idx_count, allocator)
			for j in 0 ..< idx_count {
				indices[j] = u32(cgltf.accessor_read_index(prim.indices, j))
			}
		}

		if prim.material != nil {
			model.material_indices[i] = int(cgltf.material_index(data, prim.material))
		}

		model.meshes[i] = create_mesh(positions, normals, indices)
	}

	return model, true
}

extract_accessor_f32 :: proc(
	attributes: []cgltf.attribute,
	attribute_type: cgltf.attribute_type,
) -> []f32 {
	for attr in attributes {
		if attr.type == attribute_type {
			acc := attr.data
			float_count := acc.count * cgltf.num_components(acc.type)
			result := make([]f32, float_count, context.temp_allocator)
			_ = cgltf.accessor_unpack_floats(acc, raw_data(result), float_count)
			return result
		}
	}
	return nil
}

draw_model :: proc(model: Model, shader: ShaderProgram, cam: Camera) {
	view := view_matrix(cam)
	proj := projection_matrix(cam)

	set_mat4(shader, "view", mat4_to_array(view))
	set_mat4(shader, "projection", mat4_to_array(proj))
	set_vec3(shader, "viewPos", cam.position)
	// Direction light travels (toward scene); shader uses -lightDir for surface→light.
	set_vec3(shader, "lightDir", {0.35, -1.0, 0.45})
	set_vec3(shader, "lightColor", {1.0, 0.98, 0.92})

	for i in 0 ..< len(model.meshes) {
		mesh := model.meshes[i]
		if mesh.vertex_count <= 0 && !mesh.has_indices {
			continue
		}

		model_mat := transform_matrix(model.transforms[i])
		normal_mat := math3d.normal_matrix(model_mat)

		set_mat4(shader, "model", mat4_to_array(model_mat))
		set_mat3(shader, "normalMat", mat3_to_array(normal_mat))

		mat_idx := model.material_indices[i]
		if mat_idx < 0 || mat_idx >= len(model.materials) {
			mat_idx = 0
		}
		color := model.materials[mat_idx].base_color
		// KayKit stone tint when textures are not loaded yet.
		object_color := [3]f32{color[0], color[1], color[2]}
		luma := object_color[0] * 0.299 + object_color[1] * 0.587 + object_color[2] * 0.114
		if luma < 0.25 {
			object_color = {0.78, 0.74, 0.66}
		}
		set_vec3(shader, "objectColor", object_color)

		draw_mesh(mesh)
	}
}

delete_model :: proc(model: Model) {
	for mesh in model.meshes {
		delete_mesh(mesh)
	}
	delete(model.meshes)
	delete(model.materials)
	delete(model.transforms)
	delete(model.material_indices)
}
