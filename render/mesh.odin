package render

import gl "vendor:OpenGL"

Mesh :: struct {
	vao, vbo, ebo: u32,
	vertex_count:  i32,
	index_count:   i32,
	has_indices:   bool,
}

create_mesh :: proc(
	positions: []f32,
	normals: []f32,
	indices: []u32,
) -> Mesh {
	mesh: Mesh

	gl.GenVertexArrays(1, &mesh.vao)
	gl.GenBuffers(1, &mesh.vbo)

	gl.BindVertexArray(mesh.vao)

	vertex_count := i32(len(positions) / 3)
	mesh.vertex_count = vertex_count

	if len(normals) > 0 {
		stride := 6 * size_of(f32)
		interleaved := make([]f32, vertex_count * 6, context.temp_allocator)

		for i in 0 ..< vertex_count {
			base_v := i * 3
			off := i * 6
			interleaved[off + 0] = positions[base_v + 0]
			interleaved[off + 1] = positions[base_v + 1]
			interleaved[off + 2] = positions[base_v + 2]
			interleaved[off + 3] = normals[base_v + 0]
			interleaved[off + 4] = normals[base_v + 1]
			interleaved[off + 5] = normals[base_v + 2]
		}

		data_size := int(len(interleaved) * size_of(f32))
		gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
		gl.BufferData(gl.ARRAY_BUFFER, data_size, raw_data(interleaved), gl.STATIC_DRAW)

		gl.VertexAttribPointer(0, 3, gl.FLOAT, false, i32(stride), uintptr(0))
		gl.EnableVertexAttribArray(0)

		gl.VertexAttribPointer(1, 3, gl.FLOAT, false, i32(stride), uintptr(3 * size_of(f32)))
		gl.EnableVertexAttribArray(1)
	} else {
		data_size := int(vertex_count * 3 * size_of(f32))
		gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
		gl.BufferData(gl.ARRAY_BUFFER, data_size, raw_data(positions), gl.STATIC_DRAW)

		gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 3 * size_of(f32), uintptr(0))
		gl.EnableVertexAttribArray(0)
	}

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
