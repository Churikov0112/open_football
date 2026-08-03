extends SceneTree
# ДИАГНОСТИЧЕСКИЙ зонд (не тест — вердикта не выносит, печатает таблицу для глаз).
# Отвечает на два вопроса приёмки фазы 4: (1) редеют ли касания со временем, (2) дотягивается ли
# нога до мяча и куда смотрит применённый смаггл. Замеры, снятые им, — в docs/wiki/открытые-вопросы.md.
#
# Запуск: & "<godot exe>" --path "<repo>" --headless -s "res://tests/_probe_touches.gd"
#
# ВАЖНО: get_bone_global_pose() в -s-прогоне НЕ пересчитывается (кадров нет) — считаем FK сами.
# Именно на этом первый замер дал ложные 34 м вместо 0.4.

const BALL_R := 0.11

var _skel: Skeleton3D
var _parent_of := {}

func _fk(idx: int) -> Transform3D:
	var t: Transform3D = _skel.get_bone_pose(idx)
	var p: int = _skel.get_bone_parent(idx)
	while p >= 0:
		t = _skel.get_bone_pose(p) * t
		p = _skel.get_bone_parent(p)
	return t

func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _run(vel_id: float, ticks: int, tag: String) -> void:
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	var AP = load("res://src/gpf/AnimationApplier.cs")
	var builder = SB.new()
	_skel = builder.BuildUtilitySkeleton()
	get_root().add_child(_skel)
	var c = AC.new()
	c.Load("res://assets/gpf/animations", _skel)
	var sel = load("res://src/gpf/AnimSelector.cs").new()
	sel.Setup(c)
	var applier = AP.new()

	var h = HB.new()
	h.Setup(c, sel)
	h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new()
	ball.WoodworkEnabled = false
	ball.ResetSituation(Vector3(0, -2.0, 0))
	var rng = RNG.new(); rng.Reseed(20260731)
	h.SetBall(ball)
	h.SetRng(rng)

	var pairs := [["left_knee", "left_ankle"], ["right_knee", "right_ankle"],
		["left_thigh", "left_knee"], ["right_thigh", "right_knee"]]
	var idx := {}
	for p in pairs:
		idx[p[0]] = _skel.find_bone(p[0])
		idx[p[1]] = _skel.find_bone(p[1])

	print("\n=== ", tag, " (желаемая скорость ", vel_id, " м/с) ===")
	print("tick\tdt\tlead\tnearest\tbone_d\tsurf_gap\t|aSmug|\t|mSmug|\tv_pl\tv_ball\tdv_ball")
	var last_touch := -1
	var n := 0
	for i in ticks:
		h.TickBridge(Vector3(0, -1, 0), vel_id, true)
		var tf: int = h.GetCurrentTouchFrame()
		var is_touch: bool = tf >= 0 and h.GetCurrentFrameNum() == tf
		var mom_before: Vector3 = ball.GetMovement()
		if is_touch:
			var bpos: Vector3 = ball.Predict(0)
			var anim = c.GetAnim(h.GetCurrentAnimId())
			applier.Apply(_skel, anim, h.GetApplyFrameNum(), 0.0, h.GetApplyNoPos(),
				h.GetApplyOrientation(), h.GetApplyPosition(), h.GetApplySmooth(),
				h.GetSmoothFactor(), 10)
			var best := 1e9
			var best_name := "?"
			for p in pairs:
				var a: Vector3 = _fk(idx[p[0]]).origin
				var b: Vector3 = _fk(idx[p[1]]).origin
				var d := _seg_dist(bpos, a, b)
				if d < best:
					best = d
					best_name = p[1]
			var dt := -1 if last_touch < 0 else i - last_touch
			last_touch = i
			n += 1
			var lead: float = (bpos - h.GetSpatialPosition()).length()
			ball.Process()
			var dv: float = (ball.GetMovement() - mom_before).length()
			# знак применённого смаггла: он тянет К мячу или ОТ мяча?
			var full: Vector3 = h.GetFullActionSmuggle()
			var app: Vector3 = h.GetActionSmuggle()
			var to_ball := Vector2(bpos.x - h.GetSpatialPosition().x, bpos.y - h.GetSpatialPosition().y)
			var app2 := Vector2(app.x, app.y)
			var full2 := Vector2(full.x, full.y)
			var dot_app := 0.0 if app2.length() < 1e-6 else app2.normalized().dot(to_ball.normalized())
			var dot_full := 0.0 if full2.length() < 1e-6 else full2.normalized().dot(to_ball.normalized())
			print("    СМАГГЛ: |full|=%.3f dot(full,к_мячу)=%+.2f | применён |a|=%.3f dot=%+.2f -> %s" % [
				full.length(), dot_full, app.length(), dot_app,
				"К МЯЧУ" if dot_app > 0.5 else ("ОТ МЯЧА" if dot_app < -0.5 else "боком")])
			print("%d\t%d\t%.2f\t%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.2f\t%.2f\t%.2f" % [
				i, dt, lead, best_name, best, best - BALL_R,
				h.GetActionSmuggle().length(), h.GetMovementSmuggle().length(),
				h.GetSpatialFloatVelocity(), mom_before.length(), dv])
			continue
		ball.Process()
	print("касаний: ", n, "  lead в конце: %.2f" % (ball.Predict(0) - h.GetSpatialPosition()).length())
	_skel.queue_free()

func _initialize() -> void:
	_run(3.5, 2500, "ДРИБЛИНГ")
	_run(8.0, 2500, "СПРИНТ")
	quit(0)
