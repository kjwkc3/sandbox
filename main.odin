package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import gl "vendor:OpenGL"
import sdl2 "vendor:sdl2"

import "png"
import "render"
import "room"

WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 600
TARGET_FPS    :: 60
FRAME_MS      :: 1000 / TARGET_FPS
FRAME_DIR     :: "debug/frames"

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
		"Sandbox — Dungeon Room",
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

	draw_w, draw_h: i32
	sdl2.GL_GetDrawableSize(window, &draw_w, &draw_h)
	if draw_w <= 0 {
		draw_w = i32(WINDOW_WIDTH)
	}
	if draw_h <= 0 {
		draw_h = i32(WINDOW_HEIGHT)
	}
	gl.Enable(gl.DEPTH_TEST)
	gl.Viewport(0, 0, draw_w, draw_h)
	gl.ClearColor(0.18, 0.18, 0.22, 1.0)

	texture_cache: render.TextureCache
	render.init_texture_cache(&texture_cache)
	defer render.delete_texture_cache(&texture_cache)

	dungeon_room, ok := room.load_room(&texture_cache)
	if !ok {
		panic("Failed to load dungeon room")
	}
	defer room.delete_room(dungeon_room)

	shader := render.create_shader(render.MODEL_VERT, render.MODEL_FRAG)
	defer render.delete_shader(shader)

	camera := room.room_camera(u32(draw_w), u32(draw_h))

	pixels := make([]u8, WINDOW_WIDTH * WINDOW_HEIGHT * 4)
	defer delete(pixels)
	flipped := make([]u8, len(pixels))
	defer delete(flipped)

	capture_on_startup := os.get_env_alloc("SANDBOX_CAPTURE", context.temp_allocator) == "1"
	captured_startup := false
	frame_count := 0

	fmt.println("F1 for FPS, F2 to capture PNG, ESC to quit")

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
				} else if key == .F2 {
					frame_dir := resolve_frame_dir()
					_ = os.make_directory_all(frame_dir)
					if capture_frame(pixels, flipped, frame_dir, frame_count) {
						fmt.printf("Captured frame_%03d.png\n", frame_count)
						frame_count += 1
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
		room.draw_room(dungeon_room, shader, camera)

		if capture_on_startup && !captured_startup {
			frame_dir := resolve_frame_dir()
			_ = os.make_directory_all(frame_dir)
			if capture_frame(pixels, flipped, frame_dir, 0) {
				fmt.println("Startup capture: debug/frames/frame_000.png")
				captured_startup = true
				running = false
			}
		}

		sdl2.GL_SwapWindow(window)

		elapsed_frame := sdl2.GetTicks() - last_frame_ticks
		if elapsed_frame < FRAME_MS {
			sdl2.Delay(FRAME_MS - elapsed_frame)
		}
		last_frame_ticks = sdl2.GetTicks()
	}
}

capture_frame :: proc(pixels, flipped: []u8, frame_dir: string, index: int) -> bool {
	gl.ReadBuffer(gl.BACK)
	gl.Flush()
	gl.ReadPixels(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

	for y in 0 ..< WINDOW_HEIGHT {
		src := y * WINDOW_WIDTH * 4
		dst := (WINDOW_HEIGHT - 1 - y) * WINDOW_WIDTH * 4
		copy(flipped[dst:dst + WINDOW_WIDTH * 4], pixels[src:src + WINDOW_WIDTH * 4])
	}

	path := fmt.tprintf("%s/frame_%03d.png", frame_dir, index)
	return png.write_png(path, flipped, WINDOW_WIDTH, WINDOW_HEIGHT)
}

resolve_frame_dir :: proc() -> string {
	if exe_dir, err := os.get_executable_directory(context.temp_allocator); err == nil {
		dir := filepath.join({exe_dir, "debug", "frames"}, context.temp_allocator) or_else ""
		if dir != "" {
			return dir
		}
	}
	return FRAME_DIR
}
