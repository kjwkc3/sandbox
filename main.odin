package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import gl "vendor:OpenGL"
import sdl2 "vendor:sdl2"

import "character"
import "math3d"
import "png"
import "render"
import "room"

WINDOW_WIDTH  :: 800
WINDOW_HEIGHT :: 600
TARGET_FPS    :: 60
FRAME_MS      :: 1000 / TARGET_FPS
FRAME_DIR     :: "debug/frames"
CAPTURE_DT    :: f32(1.0 / 24.0)
DEFAULT_CAPTURE_FRAMES :: 24
CAMERA_OFFSET :: math3d.Vec3{18, 16, 18}

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

	knight, knight_ok := character.load_character(&texture_cache)
	if !knight_ok {
		panic("Failed to load knight character")
	}
	defer character.delete_character(knight)

	wall_colliders := room.room_wall_colliders()
	defer delete(wall_colliders)

	room_shader := render.create_shader(render.MODEL_VERT, render.MODEL_FRAG)
	defer render.delete_shader(room_shader)

	skinned_shader := render.create_shader(render.SKINNED_VERT, render.MODEL_FRAG)
	defer render.delete_shader(skinned_shader)

	camera := room.room_camera(u32(draw_w), u32(draw_h))

	pixel_count := int(draw_w) * int(draw_h) * 4
	pixels := make([]u8, pixel_count)
	defer delete(pixels)
	flipped := make([]u8, pixel_count)
	defer delete(flipped)

	capture_on_startup := os.get_env_alloc("SANDBOX_CAPTURE", context.temp_allocator) == "1"
	capture_frame_target := DEFAULT_CAPTURE_FRAMES
	if capture_on_startup {
		if frames_env := os.get_env_alloc("SANDBOX_CAPTURE_FRAMES", context.temp_allocator); frames_env != "" {
			if n, parsed := strconv.parse_int(frames_env); parsed && n > 0 {
				capture_frame_target = n
			}
		}
	}
	captured_frames := 0
	manual_frame_count := 0
	anim_time: f32 = 0

	fmt.println("WASD to move, SPACE to jump, mouse to aim, F1 for FPS, F2 to capture PNG, ESC to quit")

	show_fps := false
	last_ticks := sdl2.GetTicks()
	fps_frame_count := 0
	fps_display: f32 = 0
	last_frame_ticks := sdl2.GetTicks()

	running := true
	for running {
		frame_start := sdl2.GetTicks()
		dt: f32
		if capture_on_startup {
			dt = CAPTURE_DT
		} else {
			// dt spans previous frame_start → this frame_start (includes pacing delay).
			elapsed_frame := frame_start - last_frame_ticks
			if elapsed_frame <= 0 {
				elapsed_frame = FRAME_MS
			}
			dt = f32(elapsed_frame) / 1000.0
			if dt > 0.1 {
				dt = 0.1
			}
			last_frame_ticks = frame_start
		}

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
					if capture_frame(pixels, flipped, draw_w, draw_h, frame_dir, manual_frame_count) {
						fmt.printf("Captured frame_%03d.png\n", manual_frame_count)
						manual_frame_count += 1
					}
				}
			}
		}

		move_dir := math3d.Vec3{0, 0, 0}
		if capture_on_startup {
			angle := f32(captured_frames) * 0.35
			move_dir = {math.cos(angle), 0, math.sin(angle)}
		} else {
			keyboard := sdl2.GetKeyboardStateAsSlice()
			cam_forward := camera.target - camera.position
			cam_forward.y = 0
			forward_len_sq := cam_forward.x * cam_forward.x + cam_forward.z * cam_forward.z
			if forward_len_sq > 0.0001 {
				inv_len := 1.0 / math.sqrt(forward_len_sq)
				cam_forward.x *= inv_len
				cam_forward.z *= inv_len
			}
			cam_right := math3d.Vec3{-cam_forward.z, 0, cam_forward.x}

			if keyboard[sdl2.Scancode.W] != 0 {
				move_dir.x += cam_forward.x
				move_dir.z += cam_forward.z
			}
			if keyboard[sdl2.Scancode.S] != 0 {
				move_dir.x -= cam_forward.x
				move_dir.z -= cam_forward.z
			}
			if keyboard[sdl2.Scancode.D] != 0 {
				move_dir.x += cam_right.x
				move_dir.z += cam_right.z
			}
			if keyboard[sdl2.Scancode.A] != 0 {
				move_dir.x -= cam_right.x
				move_dir.z -= cam_right.z
			}
			if keyboard[sdl2.Scancode.SPACE] != 0 {
				character.try_jump(&knight)
			}
		}

		is_moving := character.move_character(&knight, move_dir, dt, wall_colliders)
		character.update_character_physics(&knight, dt)

		if capture_on_startup {
			character.face_toward_dir(&knight, move_dir, dt)
		} else {
			mouse_x, mouse_y: i32
			_ = sdl2.GetMouseState(&mouse_x, &mouse_y)
			if aim_point, aim_ok := render.screen_to_ground(
				camera,
				f32(mouse_x),
				f32(mouse_y),
				u32(draw_w),
				u32(draw_h),
				0,
			); aim_ok {
				character.face_toward_point(&knight, aim_point, dt)
			}
		}

		focus := math3d.Vec3{knight.position.x, 0, knight.position.z}
		render.camera_follow(&camera, focus, CAMERA_OFFSET, dt, render.CAM_FOLLOW_STIFFNESS)

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

		render.use_shader(room_shader)
		room.draw_room(dungeon_room, room_shader, camera)

		render.use_shader(skinned_shader)
		character.draw_character(knight, skinned_shader, camera, anim_time, is_moving)

		if capture_on_startup {
			frame_dir := resolve_frame_dir()
			_ = os.make_directory_all(frame_dir)
			if capture_frame(pixels, flipped, draw_w, draw_h, frame_dir, captured_frames) {
				fmt.printf("Startup capture: %s/frame_%03d.png\n", frame_dir, captured_frames)
				captured_frames += 1
				if captured_frames >= capture_frame_target {
					running = false
				}
			} else {
				fmt.eprintf("Startup capture: failed to write %s/frame_%03d.png\n", frame_dir, captured_frames)
				capture_on_startup = false
				running = false
			}
		}

		sdl2.GL_SwapWindow(window)

		anim_time += dt
		if !capture_on_startup {
			frame_elapsed := sdl2.GetTicks() - frame_start
			if frame_elapsed < FRAME_MS {
				sdl2.Delay(FRAME_MS - frame_elapsed)
			}
		}
	}
}

capture_frame :: proc(pixels, flipped: []u8, width, height: i32, frame_dir: string, index: int) -> bool {
	w := int(width)
	h := int(height)
	row_bytes := w * 4

	gl.ReadBuffer(gl.BACK)
	gl.Flush()
	gl.ReadPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))

	for y in 0 ..< h {
		src := y * row_bytes
		dst := (h - 1 - y) * row_bytes
		copy(flipped[dst:dst + row_bytes], pixels[src:src + row_bytes])
	}

	path := fmt.tprintf("%s/frame_%03d.png", frame_dir, index)
	return png.write_png(path, flipped, w, h)
}

resolve_frame_dir :: proc() -> string {
	if exe_dir, err := os.get_executable_directory(context.temp_allocator); err == nil {
		if filepath.base(exe_dir) == "build" {
			project_dir := filepath.join({exe_dir, "..", "debug", "frames"}, context.temp_allocator) or_else ""
			if project_dir != "" {
				return project_dir
			}
		}
		dir := filepath.join({exe_dir, "debug", "frames"}, context.temp_allocator) or_else ""
		if dir != "" {
			return dir
		}
	}
	return FRAME_DIR
}
