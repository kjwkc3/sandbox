package render

import "core:fmt"
import "core:math/linalg"
import "core:path/filepath"

import cgltf "vendor:cgltf"

import "../math3d"

Model :: struct {
	meshes:           []Mesh,
	materials:        []Material,
	material_indices: []int,
}

Material :: struct {
	base_color:     [4]f32,
	base_color_tex: u32,
	has_texture:    bool,
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

transform_with_yaw :: proc(position: [3]f32, yaw_deg: f32) -> Transform {
	q := math3d.quat_from_yaw(yaw_deg)
	return Transform{
		position = position,
		rotation = {q.x, q.y, q.z, q.w},
		scale    = {1, 1, 1},
	}
}

transform_matrix :: proc(t: Transform) -> math3d.Mat4 {
	T := math3d.translate(t.position)
	q: math3d.Quat
	q.x = t.rotation[0]
	q.y = t.rotation[1]
	q.z = t.rotation[2]
	q.w = t.rotation[3]
	R := math3d.quat_to_matrix(q)
	S := math3d.scale(t.scale)
	return math3d.mul(math3d.mul(T, R), S)
}

mat4_to_array :: proc(m: math3d.Mat4) -> [16]f32 {
	return transmute([16]f32)m
}

mat3_to_array :: proc(m: linalg.Matrix3f32) -> [9]f32 {
	return transmute([9]f32)m
}

resolve_image_uri :: proc(gltf_path: string, uri: cstring) -> string {
	if uri == nil {
		return ""
	}
	dir := filepath.dir(gltf_path)
	joined := filepath.join({dir, string(uri)}, context.temp_allocator) or_else string(uri)
	if abs_path, err := filepath.abs(joined, context.temp_allocator); err == nil {
		return abs_path
	}
	return joined
}

load_material_textures :: proc(
	data: ^cgltf.data,
	gltf_path: string,
	cache: ^TextureCache,
	model: ^Model,
) {
	for i in 0 ..< len(data.materials) {
		mat := &data.materials[i]
		model.materials[i] = Material{
			base_color = {1, 1, 1, 1},
		}
		if mat.has_pbr_metallic_roughness {
			model.materials[i].base_color = mat.pbr_metallic_roughness.base_color_factor
			tex := mat.pbr_metallic_roughness.base_color_texture.texture
			if tex != nil && tex.image_ != nil && tex.image_.uri != nil {
				image_path := resolve_image_uri(gltf_path, tex.image_.uri)
				if image_path != "" {
					tex_id := load_texture(cache, image_path)
					if tex_id != 0 {
						model.materials[i].base_color_tex = tex_id
						model.materials[i].has_texture = true
					}
				}
			}
		}
	}
}

load_model :: proc(
	path: cstring,
	cache: ^TextureCache,
	allocator := context.allocator,
) -> (
	Model,
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

	model := Model{
		meshes           = make([]Mesh, len(data.meshes), allocator),
		materials        = make([]Material, len(data.materials), allocator),
		material_indices = make([]int, len(data.meshes), allocator),
	}

	load_material_textures(data, gltf_path, cache, &model)

	loaded_count := 0
	for i in 0 ..< len(data.meshes) {
		mesh_data := &data.meshes[i]
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
		texcoords := extract_accessor_f32(prim.attributes, .texcoord)

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

		model.meshes[i] = create_mesh(positions, normals, texcoords, indices)
		if len(indices) > 0 {
			delete(indices)
		}

		m := model.meshes[i]
		if m.vertex_count > 0 || m.has_indices {
			loaded_count += 1
		}
	}

	if loaded_count == 0 {
		fmt.printf("cgltf: no meshes loaded from %s\n", path)
		delete(model.meshes)
		delete(model.materials)
		delete(model.material_indices)
		return {}, false
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

bind_frame :: proc(shader: ShaderProgram, cam: Camera) {
	view := view_matrix(cam)
	proj := projection_matrix(cam)

	set_mat4(shader, "view", mat4_to_array(view))
	set_mat4(shader, "projection", mat4_to_array(proj))
	set_vec3(shader, "viewPos", cam.position)
	set_vec3(shader, "lightDir", {0.35, -1.0, 0.45})
	set_vec3(shader, "lightColor", {1.0, 0.98, 0.92})
}

draw_model_at :: proc(model: Model, shader: ShaderProgram, transform: Transform) {
	for i in 0 ..< len(model.meshes) {
		mesh := model.meshes[i]
		if mesh.vertex_count <= 0 && !mesh.has_indices {
			continue
		}

		model_mat := transform_matrix(transform)
		normal_mat := math3d.normal_matrix(model_mat)
		mat_arr := mat4_to_array(model_mat)

		set_mat4(shader, "model", mat_arr)
		set_mat3(shader, "normalMat", mat3_to_array(normal_mat))

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
			luma := object_color[0] * 0.299 + object_color[1] * 0.587 + object_color[2] * 0.114
			if luma < 0.25 {
				object_color = {0.78, 0.74, 0.66}
			}
			set_vec3(shader, "objectColor", object_color)
		}

		draw_mesh(mesh)
	}
}

draw_model :: proc(model: Model, shader: ShaderProgram, cam: Camera) {
	bind_frame(shader, cam)
	draw_model_at(model, shader, default_transform())
}

delete_model :: proc(model: Model) {
	for mesh in model.meshes {
		delete_mesh(mesh)
	}
	delete(model.meshes)
	delete(model.materials)
	delete(model.material_indices)
}
