package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import gl "vendor:OpenGL"
import sdl2 "vendor:sdl2"

import "render"

WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 600
TARGET_FPS    :: 60
FRAME_MS      :: 1000 / TARGET_FPS

MODEL_PATH :: "assets/dungeon/floor_tile_large.glb"

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
		"Sandbox — Dungeon Floor",
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

	gl.Enable(gl.DEPTH_TEST)
	gl.Viewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
	gl.ClearColor(0.18, 0.18, 0.22, 1.0)

	model_path := resolve_model_path()
	model, ok := render.load_model(model_path)
	if !ok {
		panic("Failed to load model")
	}
	defer render.delete_model(model)

	shader := render.create_shader(render.MODEL_VERT, render.MODEL_FRAG)
	defer render.delete_shader(shader)

	camera := render.isometric_camera(12, 10)

	fmt.println("F1 for FPS, ESC to quit")

	show_fps := false
	last_ticks := sdl2.GetTicks()
	fps_frame_count := 0
	fps_display: f32 = 0
	last_frame_ticks := sdl2.GetTicks()

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
				}
			}
		}

		now := sdl2.GetTicks()
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

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		render.use_shader(shader)
		render.draw_model(model, shader, camera)

		sdl2.GL_SwapWindow(window)

		elapsed_frame := sdl2.GetTicks() - last_frame_ticks
		if elapsed_frame < FRAME_MS {
			sdl2.Delay(FRAME_MS - elapsed_frame)
		}
		last_frame_ticks = sdl2.GetTicks()
	}
}

resolve_model_path :: proc() -> cstring {
	if os.exists(MODEL_PATH) {
		return MODEL_PATH
	}

	if exe_dir, err := os.get_executable_directory(context.temp_allocator); err == nil {
		candidate := filepath.join({exe_dir, MODEL_PATH}, context.temp_allocator) or_else ""
		if candidate != "" && os.exists(candidate) {
			return strings.clone_to_cstring(candidate, context.temp_allocator)
		}
		if filepath.base(exe_dir) == "build" {
			candidate = filepath.join({exe_dir, "..", MODEL_PATH}, context.temp_allocator) or_else ""
			if candidate != "" && os.exists(candidate) {
				return strings.clone_to_cstring(candidate, context.temp_allocator)
			}
		}
	}

	panic(fmt.tprintf("Model not found: %s", MODEL_PATH))
}
