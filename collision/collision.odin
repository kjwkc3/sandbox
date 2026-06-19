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
push_out_circle_xz :: proc(center: ^math3d.Vec3, radius: f32, box: AABB) {
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

	// Circle center inside box — push out along shallowest face.
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

@(private="file")
capsule_at_center :: proc(center: math3d.Vec3, radius, height: f32) -> Capsule {
	return Capsule{base = {center.x, 0, center.z}, radius = radius, height = height}
}

// Resolve movement with per-axis slide against wall AABBs.
resolve_capsule_xz_move :: proc(
	capsule: Capsule,
	walls: []AABB,
	delta_x, delta_z: f32,
) -> math3d.Vec3 {
	center := math3d.Vec3{capsule.base.x + delta_x, 0, capsule.base.z + delta_z}

	// X axis then Z axis (slide along walls).
	center.x = capsule.base.x + delta_x
	for _ in 0 ..< 4 {
		changed := false
		test_capsule := capsule_at_center(center, capsule.radius, capsule.height)
		for wall in walls {
			if capsule_xz_overlaps_aabb(test_capsule, wall) {
				push_out_circle_xz(&center, capsule.radius, wall)
				changed = true
			}
		}
		if !changed do break
	}

	center.z = capsule.base.z + delta_z
	for _ in 0 ..< 4 {
		changed := false
		test_capsule := capsule_at_center(center, capsule.radius, capsule.height)
		for wall in walls {
			if capsule_xz_overlaps_aabb(test_capsule, wall) {
				push_out_circle_xz(&center, capsule.radius, wall)
				changed = true
			}
		}
		if !changed do break
	}

	// Final combined correction if corner wedging left us inside a wall.
	for _ in 0 ..< 4 {
		changed := false
		test_capsule := capsule_at_center(center, capsule.radius, capsule.height)
		for wall in walls {
			if capsule_xz_overlaps_aabb(test_capsule, wall) {
				push_out_circle_xz(&center, capsule.radius, wall)
				changed = true
			}
		}
		if !changed do break
	}

	return center
}
