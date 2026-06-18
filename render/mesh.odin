package render

import "core:math"

import gl "vendor:OpenGL"

Mesh :: struct {
	vao, vbo, ebo: u32,
	vertex_count:  i32,
	index_count:   i32,
	has_indices:   bool,
}

compute_flat_normals :: proc(
	positions: []f32,
	indices: []u32,
	allocator := context.temp_allocator,
) -> []f32 {
	vertex_count := len(positions) / 3
	normals := make([]f32, vertex_count * 3, allocator)

	if len(indices) >= 3 {
		for t in 0 ..< len(indices) / 3 {
			i0 := int(indices[t * 3 + 0])
			i1 := int(indices[t * 3 + 1])
			i2 := int(indices[t * 3 + 2])

			ax := positions[i1 * 3 + 0] - positions[i0 * 3 + 0]
			ay := positions[i1 * 3 + 1] - positions[i0 * 3 + 1]
			az := positions[i1 * 3 + 2] - positions[i0 * 3 + 2]
			bx := positions[i2 * 3 + 0] - positions[i0 * 3 + 0]
			by := positions[i2 * 3 + 1] - positions[i0 * 3 + 1]
			bz := positions[i2 * 3 + 2] - positions[i0 * 3 + 2]

			nx := ay * bz - az * by
			ny := az * bx - ax * bz
			nz := ax * by - ay * bx

			normals[i0 * 3 + 0] += nx
			normals[i0 * 3 + 1] += ny
			normals[i0 * 3 + 2] += nz
			normals[i1 * 3 + 0] += nx
			normals[i1 * 3 + 1] += ny
			normals[i1 * 3 + 2] += nz
			normals[i2 * 3 + 0] += nx
			normals[i2 * 3 + 1] += ny
			normals[i2 * 3 + 2] += nz
		}

		for i in 0 ..< vertex_count {
			x := normals[i * 3 + 0]
			y := normals[i * 3 + 1]
			z := normals[i * 3 + 2]
			length := math.sqrt(x * x + y * y + z * z)
			if length == 0 {
				length = 1
			}
			normals[i * 3 + 0] = x / length
			normals[i * 3 + 1] = y / length
			normals[i * 3 + 2] = z / length
		}
	} else {
		for i in 0 ..< vertex_count {
			normals[i * 3 + 1] = 1
		}
	}

	return normals
}

create_mesh :: proc(
	positions: []f32,
	normals: []f32,
	texcoords: []f32,
	indices: []u32,
) -> Mesh {
	mesh: Mesh

	gl.GenVertexArrays(1, &mesh.vao)
	gl.GenBuffers(1, &mesh.vbo)

	gl.BindVertexArray(mesh.vao)

	vertex_count := i32(len(positions) / 3)
	mesh.vertex_count = vertex_count

	normals_to_use := normals
	if len(normals_to_use) == 0 && vertex_count > 0 {
		normals_to_use = compute_flat_normals(positions, indices)
	}

	stride := 8 * size_of(f32)
	interleaved := make([]f32, vertex_count * 8, context.temp_allocator)

	for i in 0 ..< vertex_count {
		base_v := i * 3
		off := i * 8
		interleaved[off + 0] = positions[base_v + 0]
		interleaved[off + 1] = positions[base_v + 1]
		interleaved[off + 2] = positions[base_v + 2]
		interleaved[off + 3] = normals_to_use[base_v + 0]
		interleaved[off + 4] = normals_to_use[base_v + 1]
		interleaved[off + 5] = normals_to_use[base_v + 2]
		if len(texcoords) >= int(vertex_count) * 2 {
			uv := i * 2
			interleaved[off + 6] = texcoords[uv + 0]
			interleaved[off + 7] = texcoords[uv + 1]
		}
	}

	data_size := int(len(interleaved) * size_of(f32))
	gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, data_size, raw_data(interleaved), gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, i32(stride), uintptr(0))
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(1, 3, gl.FLOAT, false, i32(stride), uintptr(3 * size_of(f32)))
	gl.EnableVertexAttribArray(1)

	gl.VertexAttribPointer(2, 2, gl.FLOAT, false, i32(stride), uintptr(6 * size_of(f32)))
	gl.EnableVertexAttribArray(2)

	if len(indices) > 0 {
		mesh.has_indices = true
		mesh.index_count = i32(len(indices))
		gl.GenBuffers(1, &mesh.ebo)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ebo)
		gl.BufferData(
			gl.ELEMENT_ARRAY_BUFFER,
			int(len(indices) * size_of(u32)),
			raw_data(indices),
			gl.STATIC_DRAW,
		)
	}

	gl.BindVertexArray(0)
	return mesh
}

draw_mesh :: proc(mesh: Mesh) {
	gl.BindVertexArray(mesh.vao)
	if mesh.has_indices {
		gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, nil)
	} else {
		gl.DrawArrays(gl.TRIANGLES, 0, mesh.vertex_count)
	}
	gl.BindVertexArray(0)
}

delete_mesh :: proc(mesh: Mesh) {
	vao := mesh.vao
	vbo := mesh.vbo
	gl.DeleteVertexArrays(1, &vao)
	gl.DeleteBuffers(1, &vbo)
	if mesh.has_indices {
		ebo := mesh.ebo
		gl.DeleteBuffers(1, &ebo)
	}
}

SkinnedMesh :: struct {
	vao, vbo, ebo: u32,
	vertex_count:  i32,
	index_count:   i32,
	has_indices:   bool,
}

create_skinned_mesh :: proc(
	positions: []f32,
	normals: []f32,
	texcoords: []f32,
	joints: []u32,
	weights: []f32,
	indices: []u32,
) -> SkinnedMesh {
	mesh: SkinnedMesh

	gl.GenVertexArrays(1, &mesh.vao)
	gl.GenBuffers(1, &mesh.vbo)

	gl.BindVertexArray(mesh.vao)

	vertex_count := i32(len(positions) / 3)
	mesh.vertex_count = vertex_count

	normals_to_use := normals
	if len(normals_to_use) == 0 && vertex_count > 0 {
		normals_to_use = compute_flat_normals(positions, indices)
	}

	stride_floats := 16
	stride := stride_floats * size_of(f32)
	interleaved := make([]f32, int(vertex_count) * stride_floats, context.temp_allocator)

	for i in 0 ..< int(vertex_count) {
		base_v := i * 3
		base_uv := i * 2
		base_j := i * 4
		off := i * stride_floats

		interleaved[off + 0] = positions[base_v + 0]
		interleaved[off + 1] = positions[base_v + 1]
		interleaved[off + 2] = positions[base_v + 2]
		interleaved[off + 3] = normals_to_use[base_v + 0]
		interleaved[off + 4] = normals_to_use[base_v + 1]
		interleaved[off + 5] = normals_to_use[base_v + 2]
		if len(texcoords) >= int(vertex_count) * 2 {
			interleaved[off + 6] = texcoords[base_uv + 0]
			interleaved[off + 7] = texcoords[base_uv + 1]
		}
		for j in 0 ..< 4 {
			joint_val: f32 = 0
			weight_val: f32 = 0
			if base_j + j < len(joints) {
				joint_val = f32(joints[base_j + j])
			}
			if base_j + j < len(weights) {
				weight_val = weights[base_j + j]
			}
			interleaved[off + 8 + j] = joint_val
			interleaved[off + 12 + j] = weight_val
		}
	}

	data_size := int(len(interleaved) * size_of(f32))
	gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, data_size, raw_data(interleaved), gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, i32(stride), uintptr(0))
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(1, 3, gl.FLOAT, false, i32(stride), uintptr(3 * size_of(f32)))
	gl.EnableVertexAttribArray(1)

	gl.VertexAttribPointer(2, 2, gl.FLOAT, false, i32(stride), uintptr(6 * size_of(f32)))
	gl.EnableVertexAttribArray(2)

	gl.VertexAttribPointer(3, 4, gl.FLOAT, false, i32(stride), uintptr(8 * size_of(f32)))
	gl.EnableVertexAttribArray(3)

	gl.VertexAttribPointer(4, 4, gl.FLOAT, false, i32(stride), uintptr(12 * size_of(f32)))
	gl.EnableVertexAttribArray(4)

	if len(indices) > 0 {
		mesh.has_indices = true
		mesh.index_count = i32(len(indices))
		gl.GenBuffers(1, &mesh.ebo)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ebo)
		gl.BufferData(
			gl.ELEMENT_ARRAY_BUFFER,
			int(len(indices) * size_of(u32)),
			raw_data(indices),
			gl.STATIC_DRAW,
		)
	}

	gl.BindVertexArray(0)
	return mesh
}

draw_skinned_mesh :: proc(mesh: SkinnedMesh) {
	gl.BindVertexArray(mesh.vao)
	if mesh.has_indices {
		gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, nil)
	} else {
		gl.DrawArrays(gl.TRIANGLES, 0, mesh.vertex_count)
	}
	gl.BindVertexArray(0)
}

delete_skinned_mesh :: proc(mesh: SkinnedMesh) {
	vao := mesh.vao
	vbo := mesh.vbo
	gl.DeleteVertexArrays(1, &vao)
	gl.DeleteBuffers(1, &vbo)
	if mesh.has_indices {
		ebo := mesh.ebo
		gl.DeleteBuffers(1, &ebo)
	}
}
