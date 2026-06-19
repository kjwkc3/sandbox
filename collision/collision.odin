package collision

import "core:math"

import "../math3d"

AABB :: struct {
	min: math3d.Vec3,
	max: math3d.Vec3,
}

Capsule :: struct {
	// Vertical capsule for character collision; base sits on floor (y=0).
	base:   math3d.Vec3,
	radius: f32,
	height: f32,
}

CAPSULE_RADIUS :: f32(0.5)
CAPSULE_HEIGHT :: f32(1.9)

make_capsule_at :: proc(x, z: f32) -> Capsule {
	return Capsule{
		base   = {x, 0, z},
		radius = CAPSULE_RADIUS,
		height = CAPSULE_HEIGHT,
	}
}

@(private="file")
closest_point_on_aabb_xz :: proc(box: AABB, p: math3d.Vec3) -> math3d.Vec3 {
	return {
		math.clamp(p.x, box.min.x, box.max.x),
		p.y,
		math.clamp(p.z, box.min.z, box.max.z),
	}
}

// Circle (capsule XZ footprint) vs axis-aligned box on the XZ plane.
capsule_xz_overlaps_aabb :: proc(capsule: Capsule, box: AABB) -> bool {
	center := math3d.Vec3{capsule.base.x, 0, capsule.base.z}
	closest := closest_point_on_aabb_xz(box, center)
	dx := center.x - closest.x
	dz := center.z - closest.z
	return dx * dx + dz * dz < capsule.radius * capsule.radius
}

@(private="file")
push_out_circle_xz_shallowest :: proc(center: ^math3d.Vec3, radius: f32, box: AABB) {
	to_min_x := center.x - box.min.x
	to_max_x := box.max.x - center.x
	to_min_z := center.z - box.min.z
	to_max_z := box.max.z - center.z

	min_push := to_min_x
	axis := 0 // 0=-x, 1=+x, 2=-z, 3=+z
	if to_max_x < min_push {min_push = to_max_x; axis = 1}
	if to_min_z < min_push {min_push = to_min_z; axis = 2}
	if to_max_z < min_push {min_push = to_max_z; axis = 3}

	push := min_push + radius
	switch axis {
	case 0:
		center.x = box.min.x - push
	case 1:
		center.x = box.max.x + push
	case 2:
		center.z = box.min.z - push
	case:
		center.z = box.max.z + push
	}
}

// Push a circle center out of an AABB on XZ. When the center lands inside the box
// footprint, exit through the face the player approached from (not the shallowest face).
@(private="file")
push_out_circle_xz :: proc(center: ^math3d.Vec3, from: math3d.Vec3, radius: f32, box: AABB) {
	closest := closest_point_on_aabb_xz(box, center^)
	dx := center.x - closest.x
	dz := center.z - closest.z
	dist_sq := dx * dx + dz * dz
	if dist_sq >= radius * radius {
		return
	}

	if dist_sq > 1e-8 {
		inv_dist := 1.0 / math.sqrt(dist_sq)
		penetration := radius - math.sqrt(dist_sq)
		center.x += dx * inv_dist * penetration
		center.z += dz * inv_dist * penetration
		return
	}

	// Circle center inside box footprint — exit via the approached face.
	if from.x < box.min.x {
		center.x = box.min.x - radius
	} else if from.x > box.max.x {
		center.x = box.max.x + radius
	} else if from.z < box.min.z {
		center.z = box.min.z - radius
	} else if from.z > box.max.z {
		center.z = box.max.z + radius
	} else {
		push_out_circle_xz_shallowest(center, radius, box)
	}
}

@(private="file")
capsule_at_center :: proc(center: math3d.Vec3, radius, height: f32) -> Capsule {
	return Capsule{base = {center.x, 0, center.z}, radius = radius, height = height}
}

// First contact along a swept circle (expanded AABB slab test on XZ).
@(private="file")
sweep_circle_xz_enter_t :: proc(
	from: math3d.Vec3,
	delta_x, delta_z: f32,
	radius: f32,
	box: AABB,
) -> f32 {
	ex_min_x := box.min.x - radius
	ex_max_x := box.max.x + radius
	ex_min_z := box.min.z - radius
	ex_max_z := box.max.z + radius

	t_min: f32 = 0.0
	t_max: f32 = 1.0
	eps := f32(1e-8)

	if math.abs(delta_x) < eps {
		if from.x < ex_min_x || from.x > ex_max_x {
			return 1.0
		}
	} else {
		inv_dx := 1.0 / delta_x
		t1 := (ex_min_x - from.x) * inv_dx
		t2 := (ex_max_x - from.x) * inv_dx
		t_enter := min(t1, t2)
		t_exit := max(t1, t2)
		t_min = max(t_min, t_enter)
		t_max = min(t_max, t_exit)
	}

	if math.abs(delta_z) < eps {
		if from.z < ex_min_z || from.z > ex_max_z {
			return 1.0
		}
	} else {
		inv_dz := 1.0 / delta_z
		t1 := (ex_min_z - from.z) * inv_dz
		t2 := (ex_max_z - from.z) * inv_dz
		t_enter := min(t1, t2)
		t_exit := max(t1, t2)
		t_min = max(t_min, t_enter)
		t_max = min(t_max, t_exit)
	}

	if t_min > t_max || t_min > 1.0 || t_max < 0.0 {
		return 1.0
	}
	return max(0.0, t_min)
}

@(private="file")
clip_circle_xz_delta :: proc(
	from: math3d.Vec3,
	delta_x, delta_z: f32,
	radius: f32,
	walls: []AABB,
) -> (f32, f32) {
	t_clip: f32 = 1.0
	for wall in walls {
		test_capsule := capsule_at_center(from, radius, CAPSULE_HEIGHT)
		if capsule_xz_overlaps_aabb(test_capsule, wall) {
			continue
		}
		t := sweep_circle_xz_enter_t(from, delta_x, delta_z, radius, wall)
		if t < t_clip {
			t_clip = t
		}
	}

	if t_clip < 1.0 {
		backoff := f32(0.001)
		t_clip = max(0.0, t_clip - backoff)
		return delta_x * t_clip, delta_z * t_clip
	}
	return delta_x, delta_z
}

@(private="file")
resolve_circle_xz_overlaps :: proc(
	center: ^math3d.Vec3,
	from: math3d.Vec3,
	radius, height: f32,
	walls: []AABB,
) {
	for _ in 0 ..< 4 {
		changed := false
		test_capsule := capsule_at_center(center^, radius, height)
		for wall in walls {
			if capsule_xz_overlaps_aabb(test_capsule, wall) {
				push_out_circle_xz(center, from, radius, wall)
				changed = true
			}
		}
		if !changed do break
	}
}

// Resolve movement with per-axis slide against wall AABBs.
resolve_capsule_xz_move :: proc(
	capsule: Capsule,
	walls: []AABB,
	delta_x, delta_z: f32,
) -> math3d.Vec3 {
	start := math3d.Vec3{capsule.base.x, 0, capsule.base.z}
	center := start

	resolve_circle_xz_overlaps(&center, start, capsule.radius, capsule.height, walls)

	clipped_x, clipped_z := clip_circle_xz_delta(center, delta_x, delta_z, capsule.radius, walls)

	// X axis then Z axis (slide along walls).
	center.x = start.x + clipped_x
	resolve_circle_xz_overlaps(&center, start, capsule.radius, capsule.height, walls)

	z_from := math3d.Vec3{center.x, 0, start.z}
	center.z = start.z + clipped_z
	resolve_circle_xz_overlaps(&center, z_from, capsule.radius, capsule.height, walls)

	// Final combined correction if corner wedging left us inside a wall.
	resolve_circle_xz_overlaps(&center, start, capsule.radius, capsule.height, walls)

	return center
}
