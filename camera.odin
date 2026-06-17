package render

import "core:math"

import "math3d"

Camera :: struct {
	position:    math3d.Vec3,
	target:      math3d.Vec3,
	up:          math3d.Vec3,
	fov_deg:     f32,
	near:        f32,
	far:         f32,
	aspect:      f32,
}

default_camera :: proc(width, height: u32) -> Camera {
	return Camera{
		position = {10, 10, 10},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
		fov_deg  = 45,
		near     = 0.1,
		far      = 100,
		aspect   = f32(width) / f32(height),
	}
}

view_matrix :: proc(cam: Camera) -> math3d.Mat4 {
	return math3d.look_at(cam.position, cam.target, cam.up)
}

projection_matrix :: proc(cam: Camera) -> math3d.Mat4 {
	return math3d.perspective(cam.fov_deg, cam.aspect, cam.near, cam.far)
}

isometric_camera :: proc(distance: f32, height: f32) -> Camera {
	pos := math3d.Vec3{distance, height, distance}
	return Camera{
		position = pos,
		target   = {0, 0, 0},
		up       = {0, 1, 0},
		fov_deg  = 45,
		near     = 0.1,
		far      = 200,
		aspect   = 800.0 / 600.0,
	}
}

rotate_around_target :: proc(cam: Camera, angle_deg: f32) -> Camera {
	rad := angle_deg * math3d.RAD_PER_DEG
	offset := cam.position - cam.target
	dist := math.sqrt(offset[0] * offset[0] + offset[2] * offset[2])

	new_x := f32(math.cos(f64(rad))) * dist
	new_z := f32(math.sin(f64(rad))) * dist

	cam.position = cam.target + math3d.Vec3{new_x, offset[1], new_z}
	return cam
}
