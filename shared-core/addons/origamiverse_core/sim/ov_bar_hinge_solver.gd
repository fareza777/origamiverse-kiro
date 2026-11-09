class_name OVBarHingeSolver
extends RefCounted
## Compliant origami simulation (bar-and-hinge model, after Ghassaei et al. 2018) solved with XPBD.
## Works for any triangulated crease pattern, including non-rigid-foldable ones (bird base, twists).

var doc: OVFoldDocument
var fold_percent: float = 0.0
var substeps: int = 10
var damping: float = 0.92          ## velocity kept per substep
var crease_compliance: float = 30.0   ## soft relative to bars so facets stay unstretched
var facet_compliance: float = 0.6
var bar_compliance: float = 0.0
var max_step: float = 0.05         ## max displacement per substep (stability guard)

var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var inv_mass: PackedFloat32Array = PackedFloat32Array()
var pinned_face: int = 0

# Bars
var bar_a: PackedInt32Array = PackedInt32Array()
var bar_b: PackedInt32Array = PackedInt32Array()
var bar_rest: PackedFloat32Array = PackedFloat32Array()
# Hinges: edge (a, b), wings c (left triangle) and d (right triangle)
var hinge_a: PackedInt32Array = PackedInt32Array()
var hinge_b: PackedInt32Array = PackedInt32Array()
var hinge_c: PackedInt32Array = PackedInt32Array()
var hinge_d: PackedInt32Array = PackedInt32Array()
var hinge_full: PackedFloat32Array = PackedFloat32Array()   ## radians at 100 %
var hinge_alpha: PackedFloat32Array = PackedFloat32Array()
var hinge_is_crease: PackedByteArray = PackedByteArray()
var hinge_edge: PackedInt32Array = PackedInt32Array()
var hinge_last: PackedFloat32Array = PackedFloat32Array()
## Optional per-edge multiplier on fold_percent (PaperVerse uses it for staged folding). Indexed by hinge.
var hinge_scale: PackedFloat32Array = PackedFloat32Array()

var strain: float = 0.0
var _prev: PackedVector3Array = PackedVector3Array()


func setup(document: OVFoldDocument, pin_face: int = -1) -> Dictionary:
	doc = document
	if doc.face_count() == 0:
		return OVCore.fail(PackedStringArray(["Nothing to simulate: the pattern has no faces."]))
	for f in doc.faces:
		if f.size() != 3:
			return OVCore.fail(PackedStringArray(["Simulation needs a triangulated document."]))
	positions = doc.vertices.duplicate()
	var n: int = positions.size()
	velocities = PackedVector3Array()
	velocities.resize(n)
	inv_mass = PackedFloat32Array()
	inv_mass.resize(n)
	inv_mass.fill(1.0)

	bar_a = PackedInt32Array(); bar_b = PackedInt32Array(); bar_rest = PackedFloat32Array()
	for e in doc.edge_count():
		var u: int = doc.edges[e * 2]
		var v: int = doc.edges[e * 2 + 1]
		bar_a.append(u); bar_b.append(v)
		bar_rest.append(positions[u].distance_to(positions[v]))

	# Directed edge (u -> v) -> wing vertex of the triangle that contains it in CCW order.
	var wing: Dictionary = {}
	for f in doc.faces:
		for i in 3:
			wing[Vector2i(f[i], f[(i + 1) % 3])] = f[(i + 2) % 3]
	hinge_a = PackedInt32Array(); hinge_b = PackedInt32Array(); hinge_c = PackedInt32Array(); hinge_d = PackedInt32Array()
	hinge_full = PackedFloat32Array(); hinge_alpha = PackedFloat32Array(); hinge_is_crease = PackedByteArray()
	hinge_edge = PackedInt32Array(); hinge_last = PackedFloat32Array(); hinge_scale = PackedFloat32Array()
	for e in doc.edge_count():
		var a_type: int = doc.assignments[e]
		if a_type == OVCore.Assign.BOUNDARY or a_type == OVCore.Assign.CUT:
			continue
		var u: int = doc.edges[e * 2]
		var v: int = doc.edges[e * 2 + 1]
		var k1: Vector2i = Vector2i(u, v)
		var k2: Vector2i = Vector2i(v, u)
		if not wing.has(k1) or not wing.has(k2):
			continue
		hinge_a.append(u); hinge_b.append(v)
		hinge_c.append(wing[k1]); hinge_d.append(wing[k2])
		var crease: bool = OVCore.is_crease(a_type)
		hinge_is_crease.append(1 if crease else 0)
		hinge_full.append(deg_to_rad(doc.fold_angles[e]) if crease else 0.0)
		hinge_alpha.append(crease_compliance if crease else facet_compliance)
		hinge_edge.append(e)
		hinge_last.append(0.0)
		hinge_scale.append(1.0)
	set_pinned_face(clampi(pin_face if pin_face >= 0 else _central_face(), 0, doc.face_count() - 1))
	return OVCore.ok(self)


func set_pinned_face(fi: int) -> void:
	pinned_face = fi
	inv_mass.fill(1.0)
	for vi in doc.faces[fi]:
		inv_mass[vi] = 0.0


func _central_face() -> int:
	var c: Vector3 = Vector3.ZERO
	for p in positions:
		c += p
	c /= float(maxi(positions.size(), 1))
	var best: int = 0
	var best_d: float = INF
	for fi in doc.face_count():
		var f: PackedInt32Array = doc.faces[fi]
		var fc: Vector3 = (positions[f[0]] + positions[f[1]] + positions[f[2]]) / 3.0
		var d: float = fc.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = fi
	return best


## Resets to the flat rest state.
func reset() -> void:
	positions = doc.vertices.duplicate()
	velocities.fill(Vector3.ZERO)
	hinge_last.fill(0.0)


## Advances the simulation by one frame.
func step(frame_dt: float = 1.0 / 60.0) -> void:
	var n: int = positions.size()
	var dt: float = clampf(frame_dt, 1.0 / 240.0, 1.0 / 20.0) / float(substeps)
	var pct: float = clampf(fold_percent, -1.0, 1.0)
	var limit: float = PI * 0.995
	var hc: int = hinge_a.size()
	var bc: int = bar_a.size()
	for _s in substeps:
		_prev = positions.duplicate()
		for i in n:
			if inv_mass[i] > 0.0:
				var dv: Vector3 = velocities[i] * dt
				if dv.length_squared() > max_step * max_step:
					dv = dv.normalized() * max_step
				positions[i] += dv
		# Bars.
		for k in bc:
			var ia: int = bar_a[k]
			var ib: int = bar_b[k]
			var wa: float = inv_mass[ia]
			var wb: float = inv_mass[ib]
			var wsum: float = wa + wb
			if wsum <= 0.0:
				continue
			var delta: Vector3 = positions[ib] - positions[ia]
			var len: float = delta.length()
			if len < 1e-9:
				continue
			var c: float = len - bar_rest[k]
			var corr: Vector3 = delta * (c / (len * (wsum + bar_compliance)))
			positions[ia] += corr * wa
			positions[ib] -= corr * wb
		# Hinges.
		for k in hc:
			var ia: int = hinge_a[k]
			var ib: int = hinge_b[k]
			var ic: int = hinge_c[k]
			var id: int = hinge_d[k]
			var pa: Vector3 = positions[ia]
			var pb: Vector3 = positions[ib]
			var pc: Vector3 = positions[ic]
			var pd: Vector3 = positions[id]
			var e: Vector3 = pb - pa
			var el2: float = e.length_squared()
			if el2 < 1e-12:
				continue
			var el: float = sqrt(el2)
			var m1: Vector3 = e.cross(pc - pa)
			var m2: Vector3 = (pa - pb).cross(pd - pb)
			var l1: float = m1.length()
			var l2: float = m2.length()
			if l1 < 1e-10 or l2 < 1e-10:
				continue
			var n1: Vector3 = m1 / l1
			var n2: Vector3 = m2 / l2
			var theta: float = atan2(n2.cross(n1).dot(e / el), clampf(n1.dot(n2), -1.0, 1.0))
			var last: float = hinge_last[k]
			while theta - last > PI:
				theta -= TAU
			while theta - last < -PI:
				theta += TAU
			var target: float = clampf(hinge_full[k] * pct * hinge_scale[k], -limit, limit)
			var cval: float = theta - target
			var gc: Vector3 = n1 * (el / l1)      # n1 / h1 with h1 = l1 / el
			var gd: Vector3 = n2 * (el / l2)
			var s1: float = (pc - pa).dot(e) / el2
			var s2: float = (pd - pa).dot(e) / el2
			var ga: Vector3 = -gc * (1.0 - s1) - gd * (1.0 - s2)
			var gb: Vector3 = -gc * s1 - gd * s2
			var wa: float = inv_mass[ia]
			var wb: float = inv_mass[ib]
			var wc: float = inv_mass[ic]
			var wd: float = inv_mass[id]
			var denom: float = wa * ga.length_squared() + wb * gb.length_squared() \
				+ wc * gc.length_squared() + wd * gd.length_squared() + hinge_alpha[k]
			if denom < 1e-12:
				continue
			var lam: float = -cval / denom
			positions[ia] += ga * (lam * wa)
			positions[ib] += gb * (lam * wb)
			positions[ic] += gc * (lam * wc)
			positions[id] += gd * (lam * wd)
		# Velocities.
		var inv_dt: float = 1.0 / dt
		for i in n:
			velocities[i] = (positions[i] - _prev[i]) * (inv_dt * damping)
	_record_angles()
	_compute_strain()


func _record_angles() -> void:
	for k in hinge_a.size():
		hinge_last[k] = current_angle(k)


## Current signed dihedral (radians, valley positive), unwrapped near the previous value.
func current_angle(k: int) -> float:
	var pa: Vector3 = positions[hinge_a[k]]
	var pb: Vector3 = positions[hinge_b[k]]
	var e: Vector3 = pb - pa
	var n1: Vector3 = e.cross(positions[hinge_c[k]] - pa).normalized()
	var n2: Vector3 = (pa - pb).cross(positions[hinge_d[k]] - pb).normalized()
	var theta: float = atan2(n2.cross(n1).dot(e.normalized()), clampf(n1.dot(n2), -1.0, 1.0))
	var last: float = hinge_last[k]
	while theta - last > PI:
		theta -= TAU
	while theta - last < -PI:
		theta += TAU
	return theta


func _compute_strain() -> void:
	var total: float = 0.0
	for k in bar_a.size():
		var l0: float = bar_rest[k]
		if l0 > 0.0:
			total += absf(positions[bar_a[k]].distance_to(positions[bar_b[k]]) - l0) / l0
	strain = total / float(maxi(bar_a.size(), 1))


func is_finite_state() -> bool:
	for p in positions:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return false
	return true


## Max |current - target| over creases, in degrees. Useful to know when the pose has settled.
func crease_error_degrees() -> float:
	var worst: float = 0.0
	var limit: float = PI * 0.995
	for k in hinge_a.size():
		if hinge_is_crease[k] == 0:
			continue
		var target: float = clampf(hinge_full[k] * fold_percent * hinge_scale[k], -limit, limit)
		worst = maxf(worst, absf(current_angle(k) - target))
	return rad_to_deg(worst)
