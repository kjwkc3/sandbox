package main

import "core:c"
import "core:fmt"
import gl "vendor:OpenGL"
import sdl2 "vendor:sdl2"
import stbiw "vendor:stb/image"

WINDOW_WIDTH    :: 800
WINDOW_HEIGHT   :: 600
SCREENSHOT_FILE :: "screenshot.png"

VERT_SRC :: `
#version 330 core
layout (location = 0) in vec2 pos;
void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
}
`

FRAG_SRC :: `
#version 330 core
out vec4 color;
void main() {
    color = vec4(1.0, 0.5, 0.2, 1.0);
}
`

main :: proc() {
	if sdl2.Init(sdl2.INIT_VIDEO) != 0 {
		panic(sdl2.GetErrorString())
	}
	defer sdl2.Quit()

	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, c.int(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.DOUBLEBUFFER, 1)

	flags := sdl2.WINDOW_OPENGL | sdl2.WINDOW_HIDDEN
	window := sdl2.CreateWindow(
		"Hello Triangle",
		sdl2.WINDOWPOS_CENTERED, sdl2.WINDOWPOS_CENTERED,
		WINDOW_WIDTH, WINDOW_HEIGHT,
		flags,
	)
	if window == nil {
		panic(sdl2.GetErrorString())
	}
	defer sdl2.DestroyWindow(window)

	gl_context := sdl2.GL_CreateContext(window)
	if gl_context == nil {
		panic(sdl2.GetErrorString())
	}
	defer sdl2.GL_DeleteContext(gl_context)

	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	program := create_shader_program(VERT_SRC, FRAG_SRC)
	gl.UseProgram(program)

	vao: u32
	vbo: u32
	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)

	vertex_data := [6]f32{-0.5, -0.5, 0.5, -0.5, 0.0, 0.5}

	gl.BindVertexArray(vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertex_data), &vertex_data[0], gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 2 * size_of(f32), uintptr(0))
	gl.EnableVertexAttribArray(0)

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	fbo: u32
	rbo_color: u32
	rbo_depth: u32
	gl.GenFramebuffers(1, &fbo)
	gl.GenRenderbuffers(1, &rbo_color)
	gl.GenRenderbuffers(1, &rbo_depth)

	gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)

	gl.BindRenderbuffer(gl.RENDERBUFFER, rbo_color)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.RGBA8, WINDOW_WIDTH, WINDOW_HEIGHT)
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, rbo_color)

	gl.BindRenderbuffer(gl.RENDERBUFFER, rbo_depth)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, WINDOW_WIDTH, WINDOW_HEIGHT)
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, rbo_depth)

	status := gl.CheckFramebufferStatus(gl.FRAMEBUFFER)
	if status != gl.FRAMEBUFFER_COMPLETE {
		fmt.println("Framebuffer not complete: ", status)
		return
	}

	gl.Viewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
	gl.ClearColor(0.1, 0.1, 0.15, 1.0)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

	gl.UseProgram(program)
	gl.BindVertexArray(vao)
	gl.DrawArrays(gl.TRIANGLES, 0, 3)

	pixels := make([]u8, WINDOW_WIDTH * WINDOW_HEIGHT * 4)
	defer delete(pixels)

	gl.ReadPixels(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

	flipped := make([]u8, len(pixels))
	defer delete(flipped)

	for y in 0 ..< WINDOW_HEIGHT {
		src_row := y * WINDOW_WIDTH * 4
		dst_row := (WINDOW_HEIGHT - 1 - y) * WINDOW_WIDTH * 4
		for x in 0 ..< WINDOW_WIDTH * 4 {
			flipped[dst_row + x] = pixels[src_row + x]
		}
	}

	result := stbiw.write_png(
		SCREENSHOT_FILE,
		WINDOW_WIDTH, WINDOW_HEIGHT, 4,
		raw_data(flipped),
		WINDOW_WIDTH * 4,
	)

	if result != 0 {
		fmt.println("Screenshot saved: ", SCREENSHOT_FILE)
	} else {
		fmt.println("Failed to save screenshot")
	}

	gl.DeleteVertexArrays(1, &vao)
	gl.DeleteBuffers(1, &vbo)
	gl.DeleteRenderbuffers(1, &rbo_color)
	gl.DeleteRenderbuffers(1, &rbo_depth)
	gl.DeleteFramebuffers(1, &fbo)
	gl.DeleteProgram(program)
}

compile_shader :: proc(source: cstring, shader_type: u32) -> u32 {
	shader := gl.CreateShader(shader_type)
	src := source
	gl.ShaderSource(shader, 1, &src, nil)
	gl.CompileShader(shader)

	success: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		log_buf: [512]u8
		gl.GetShaderInfoLog(shader, 512, nil, &log_buf[0])
		msg := fmt.aprintf("Shader compilation failed: %s", string(log_buf[:]))
		panic(msg)
	}
	return shader
}

create_shader_program :: proc(vertex_src, fragment_src: cstring) -> u32 {
	vs := compile_shader(vertex_src, gl.VERTEX_SHADER)
	defer gl.DeleteShader(vs)

	fs := compile_shader(fragment_src, gl.FRAGMENT_SHADER)
	defer gl.DeleteShader(fs)

	program := gl.CreateProgram()
	gl.AttachShader(program, vs)
	gl.AttachShader(program, fs)
	gl.LinkProgram(program)

	success: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success == 0 {
		log_buf: [512]u8
		gl.GetProgramInfoLog(program, 512, nil, &log_buf[0])
		msg := fmt.aprintf("Shader link failed: %s", string(log_buf[:]))
		panic(msg)
	}
	return program
}
