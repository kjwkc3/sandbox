package render

import "core:c"
import gl "vendor:OpenGL"

Mesh :: struct {
	vao, vbo, ebo: u32,
	vertex_count:  u32,
	index_count:   u32,
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

	vertex_count := u32(len(positions) / 3)
	mesh.vertex_count = vertex_count

	if len(normals) > 0 {
		stride := 6 * size_of(f32)
		data_size := c.size_t(vertex_count * stride)
		data := make([]u8, data_size, context.temp_allocator)

		for i in 0 ..< vertex_count {
			off := i * 6
			base_v := i * 3
			data[off + 0] = raw_bits(positions[base_v + 0])
			data[off + 1] = raw_bits(positions[base_v + 1])
			data[off + 2] = raw_bits(positions[base_v + 2])
			data[off + 3] = raw_bits(normals[base_v + 0])
			data[off + 4] = raw_bits(normals[base_v + 1])
			data[off + 5] = raw_bits(normals[base_v + 2])
		}

		gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
		gl.BufferData(gl.ARRAY_BUFFER, data_size, raw_data(data), gl.STATIC_DRAW)

		gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 6 * size_of(f32), uintptr(0))
		gl.EnableVertexAttribArray(0)

		gl.VertexAttribPointer(1, 3, gl.FLOAT, false, 6 * size_of(f32), uintptr(3 * size_of(f32)))
		gl.EnableVertexAttribArray(1)
	} else {
		data_size := c.size_t(vertex_count * 3 * size_of(f32))
		gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
		gl.BufferData(gl.ARRAY_BUFFER, data_size, raw_data(positions), gl.STATIC_DRAW)

		gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 3 * size_of(f32), uintptr(0))
		gl.EnableVertexAttribArray(0)
	}

	if len(indices) > 0 {
		mesh.has_indices = true
		mesh.index_count = u32(len(indices))
		gl.GenBuffers(1, &mesh.ebo)
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ebo)
		gl.BufferData(
			gl.ELEMENT_ARRAY_BUFFER,
			c.size_t(len(indices) * size_of(u32)),
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
	gl.DeleteVertexArrays(1, &mesh.vao)
	gl.DeleteBuffers(1, &mesh.vbo)
	if mesh.has_indices {
		gl.DeleteBuffers(1, &mesh.ebo)
	}
}
