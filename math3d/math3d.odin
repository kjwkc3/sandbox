package math3d

import "core:math/linalg"

Vec3 :: linalg.Vector3f32
Mat4 :: linalg.Matrix4f32
Quat :: linalg.Quaternionf32

RAD_PER_DEG :: linalg.RAD_PER_DEG

perspective :: proc(fovy_deg, aspect, near, far: f32) -> Mat4 {
	return linalg.matrix4_perspective_f32(fovy_deg * RAD_PER_DEG, aspect, near, far)
}

look_at :: proc(eye, center, up: Vec3) -> Mat4 {
	return linalg.matrix4_look_at_f32(eye, center, up)
}

translate :: proc(v: Vec3) -> Mat4 {
	return linalg.matrix4_translate_f32(v)
}

rotate :: proc(angle_deg: f32, axis: Vec3) -> Mat4 {
	return linalg.matrix4_rotate_f32(angle_deg * RAD_PER_DEG, axis)
}

scale :: proc(v: Vec3) -> Mat4 {
	return linalg.matrix4_scale_f32(v)
}

identity :: proc() -> Mat4 {
	return linalg.MATRIX4F32_IDENTITY
}

mul :: proc(a, b: Mat4) -> Mat4 {
	return a * b
}

normal_matrix :: proc(model: Mat4) -> linalg.Matrix3f32 {
	m3 := linalg.Matrix3f32{
		model[0][0], model[0][1], model[0][2],
		model[1][0], model[1][1], model[1][2],
		model[2][0], model[2][1], model[2][2],
	}
	return linalg.matrix3_orthonormalize_f32(m3)
}
