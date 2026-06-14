package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import gl "vendor:OpenGL"
import sdl2 "vendor:sdl2"
import "png"

WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 600
TARGET_FPS    :: 60
FRAME_MS      :: 1000 / TARGET_FPS

VERT_SRC :: `
#version 330 core
layout (location = 0) in vec2 pos;
layout (location = 1) in vec3 color;
uniform mat4 rotation;
out vec3 vColor;
void main() {
    gl_Position = rotation * vec4(pos, 0.0, 1.0);
    vColor = color;
}
`

FRAG_SRC :: `
#version 330 core
in vec3 vColor;
out vec4 fragColor;
void main() {
    fragColor = vec4(vColor, 1.0);
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

	window := sdl2.CreateWindow(
		"Spinning Triangle",
		sdl2.WINDOWPOS_CENTERED, sdl2.WINDOWPOS_CENTERED,
		WINDOW_WIDTH, WINDOW_HEIGHT,
		sdl2.WINDOW_OPENGL,
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

	rot_loc := gl.GetUniformLocation(program, "rotation")

	vao: u32
	vbo: u32
	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)

	vertex_data := [15]f32{
		-0.5, -0.2887, 1.0, 0.0, 0.0,
		 0.5, -0.2887, 0.0, 1.0, 0.0,
		 0.0,  0.5774, 0.0, 0.0, 1.0,
	}

	stride: i32 = 5 * size_of(f32)

	gl.BindVertexArray(vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertex_data), &vertex_data[0], gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, stride, uintptr(0))
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(1, 3, gl.FLOAT, false, stride, uintptr(2 * size_of(f32)))
	gl.EnableVertexAttribArray(1)

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	gl.Viewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
	gl.ClearColor(0.1, 0.1, 0.15, 1.0)

	pixels := make([]u8, WINDOW_WIDTH * WINDOW_HEIGHT * 4)
	defer delete(pixels)

	flipped := make([]u8, len(pixels))
	defer delete(flipped)

	recording := false
	frame_count := 0
	tick: f32 = 0

	show_fps := false
	last_ticks := sdl2.GetTicks()
	fps_frame_count := 0
	fps_display: f32 = 0
	last_frame_ticks := sdl2.GetTicks()

	frame_dir := "debug/frames"
	if exe_dir, err := os.get_executable_directory(context.allocator); err == nil {
		if filepath.base(exe_dir) == "build" {
			frame_dir = filepath.join({exe_dir, "..", "debug", "frames"}, context.allocator) or_else "debug/frames"
		} else {
			frame_dir = filepath.join({exe_dir, "debug", "frames"}, context.allocator) or_else "debug/frames"
		}
	}

	fmt.println("F1 for metrics, F2 to start/stop recording, ESC to quit")

	running := true
	for running {
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEYDOWN:
				key := event.key.keysym.scancode
				if key == .ESCAPE {
					running = false
				} else if key == .F1 {
					show_fps = !show_fps
					if show_fps {
						fmt.println("FPS: enabled")
					} else {
						fmt.println("FPS: disabled")
					}
				} else if key == .F2 {
					recording = !recording
					if recording {
						frame_count = 0
						_ = os.remove_all(frame_dir)
						_ = os.make_directory_all(frame_dir)
						fmt.println("Recording started")
					} else {
						fmt.printf("Recording stopped: %d frames\n", frame_count)
					}
				}
			}
		}

		now := sdl2.GetTicks()
		dt := f32(now - last_frame_ticks) / 1000.0
		last_frame_ticks = now

		if show_fps {
			fps_frame_count += 1
			elapsed := now - last_ticks
			if elapsed >= 1000 {
				fps_display = f32(fps_frame_count) * 1000.0 / f32(elapsed)
				fmt.printf("\rFPS: %.1f  ", fps_display)
				last_ticks = now
				fps_frame_count = 0
			}
		}

		tick += dt * 2.0
		angle := tick
		cos_a := math.cos(angle)
		sin_a := math.sin(angle)

		rot := [16]f32{
			cos_a, -sin_a, 0, 0,
			sin_a,  cos_a, 0, 0,
			0,      0,     1, 0,
			0,      0,     0, 1,
		}

		gl.UseProgram(program)
		gl.UniformMatrix4fv(rot_loc, 1, false, &rot[0])

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		gl.BindVertexArray(vao)
		gl.DrawArrays(gl.TRIANGLES, 0, 3)

		if recording {
			gl.Flush()
			gl.ReadPixels(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

			for y in 0 ..< WINDOW_HEIGHT {
				src := y * WINDOW_WIDTH * 4
				dst := (WINDOW_HEIGHT - 1 - y) * WINDOW_WIDTH * 4
				for x in 0 ..< WINDOW_WIDTH * 4 {
					flipped[dst + x] = pixels[src + x]
				}
			}

			frame_path := fmt.tprintf("%s/frame_%03d.png", frame_dir, frame_count)
			if png.write_png(frame_path, flipped, WINDOW_WIDTH, WINDOW_HEIGHT) {
				fmt.printf("Frame %d: %s\n", frame_count, frame_path)
			}
			frame_count += 1
		}

		sdl2.GL_SwapWindow(window)

		elapsed := sdl2.GetTicks() - last_frame_ticks
		if elapsed < FRAME_MS {
			sdl2.Delay(FRAME_MS - elapsed)
		}
	}

	gl.DeleteVertexArrays(1, &vao)
	gl.DeleteBuffers(1, &vbo)
	gl.DeleteProgram(program)

	if frame_count > 0 {
		fmt.printf("Captured %d frames to %s/\n", frame_count, frame_dir)
	}
}

compile_shader :: proc(source: cstring, shader_type: u32) -> u32 {
	shader := gl.CreateShader(shader_type)
	src := source
	gl.ShaderSource(shader, 1, &src, nil)
	gl.CompileShader(shader)

	success: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		panic("Shader compile failed")
	}
	return shader
}

create_shader_program :: proc(vs_src, fs_src: cstring) -> u32 {
	vs := compile_shader(vs_src, gl.VERTEX_SHADER)
	defer gl.DeleteShader(vs)

	fs := compile_shader(fs_src, gl.FRAGMENT_SHADER)
	defer gl.DeleteShader(fs)

	program := gl.CreateProgram()
	gl.AttachShader(program, vs)
	gl.AttachShader(program, fs)
	gl.LinkProgram(program)

	success: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success == 0 {
		panic("Shader link failed")
	}
	return program
}
