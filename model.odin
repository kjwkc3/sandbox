package render

import "core:c"
import "core:fmt"
import "core:os"
import "core:mem"
import cgltf "vendor:cgltf"

Model :: struct {
	meshes:     []Mesh,
	materials:  []Material,
	transforms: []Transform,
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

load_model :: proc(path: cstring, allocator := context.allocator) -> (Model, bool) {
	options := cgltf.options{
		memory = cgltf.memory_options{
			alloc_func = proc(user: rawptr, size: uint) -> rawptr {
				return mem_alloc(size, allocator)
			},
			free_func = proc(user: rawptr, ptr: rawptr) {
				mem_free(ptr, allocator)
			},
			user_data = nil,
		},
	}

	var data: ^cgltf.data
	result := cgltf.parse_file(options, path, &data)
	if result != .SUCCESS {
		fmt.printf("cgltf: failed to parse %s\n", path)
		return {}, false
	}
	defer cgltf.free(data)

	result = cgltf.load_buffers(options, data, path)
	if result != .SUCCESS {
		fmt.printf("cgltf: failed to load buffers for %s\n", path)
		return {}, false
	}

	model := Model{
		meshes     = make([]Mesh, data.meshes_count, allocator),
		materials  = make([]Material, data.materials_count, allocator),
		transforms = make([]Transform, data.meshes_count, allocator),
	}

	for i in 0 ..< data.materials_count {
		mat := data.materials[i]
		model.materials[i] = Material{
			base_color = {1, 1, 1, 1},
		}
		if mat.has_pbr_metallic_roughness != 0 {
			model.materials[i].base_color = mat.pbr_metallic_roughness.base_color_factor
		}
	}

	for i in 0 ..< data.meshes_count {
		mesh_data := data.meshes[i]
		model.transforms[i] = default_transform()

		if mesh_data.primitives_count == 0 { continue }
		prim := mesh_data.primitives[0]

		positions := extract_accessor_f32(data, prim.attributes, .POSITION)
		if positions == nil {
			fmt.printf("cgltf: mesh %d has no positions\n", i)
			continue
		}

		normals := extract_accessor_f32(data, prim.attributes, .NORMAL)

		indices: []u32
		if prim.indices != nil {
			idx_count := prim.indices.count
			indices = make([]u32, idx_count, allocator)
			for j in 0 ..< idx_count {
				indices[j] = u32(cgltf.accessor_read_index(prim.indices, j))
			}
		}

		model.meshes[i] = create_mesh(positions, normals, indices)
	}

	return model, true
}

extract_accessor_f32 :: proc(
	data: ^cgltf.data,
	attributes: [^]cgltf.attribute,
	attribute_type: cgltf.attribute_type,
) -> []f32 {
	for i in 0 ..< int(attributes.len) {
		attr := attributes[i]
		if attr.type == attribute_type {
			acc := attr.data
			float_count := acc.count * cgltf.calc_size(acc.type) / cgltf.component_size(acc.component_type)
			result := make([]f32, float_count, context.temp_allocator)
			cgltf.accessor_unpack_floats(acc, raw_data(result), u32(float_count))
			return result
		}
	}
	return nil
}

draw_model :: proc(model: Model) {
	for mesh in model.meshes {
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
}
