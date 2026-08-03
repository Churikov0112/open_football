extends SceneTree
# ДИАГНОСТИЧЕСКИЙ зонд (не тест — вердикта не выносит, печатает таблицу для глаз).
# Теряется ли мяч при смене направления и от чего это зависит.
# Сценарий: устойчивое ведение прямо → поворот в момент t (перебираем фазу клипа) → держим новое
# направление. Смотрим, случилось ли касание после поворота и что мешало.
# Замеры, снятые им (45° — 8/12 потерь, 90° — 2/12, спринт 45° — 12/12), — в открытых вопросах.
#
# Запуск: & "<godot exe>" --path "<repo>" --headless -s "res://tests/_probe_turn.gd"

var _c
var _sel
var _skel: Skeleton3D

func _setup() -> void:
	var SB = load("res://src/gpf/SkeletonBuilder.cs")
	var AC = load("res://src/gpf/AnimCollection.cs")
	_skel = SB.new().BuildUtilitySkeleton()
	get_root().add_child(_skel)
	_c = AC.new()
	_c.Load("res://assets/gpf/animations", _skel)
	_sel = load("res://src/gpf/AnimSelector.cs").new()
	_sel.Setup(_c)

## один прогон: turn_at — тик поворота, new_dir — новое направление
func _run(turn_at: int, new_dir: Vector3, vel: float) -> Dictionary:
	var HB = load("res://src/gpf/HumanoidBase.cs")
	var B = load("res://src/gpf/Ball.cs")
	var RNG = load("res://src/gpf/GpfRng.cs")
	var h = HB.new(); h.Setup(_c, _sel); h.ResetSituation(Vector3.ZERO, 0.0)
	var ball = B.new(); ball.WoodworkEnabled = false; ball.ResetSituation(Vector3(0, -2.0, 0))
	var rng = RNG.new(); rng.Reseed(20260731)
	h.SetBall(ball); h.SetRng(rng)

	var dir := Vector3(0, -1, 0)
	var touches_after := 0
	var min_dist := 1e9
	var max_dist_after := 0.0
	var fn_after := {}
	var early_out_a := 0   # мяч через 200 мс дальше 10 м
	var early_out_b := 0   # мяч через 80 мс дальше 2 м И удаляется
	var ticks_after := 0
	for i in turn_at + 400:
		if i == turn_at:
			dir = new_dir
		h.TickBridge(dir, vel, true)
		var tf: int = h.GetCurrentTouchFrame()
		var is_touch: bool = tf >= 0 and h.GetCurrentFrameNum() == tf
		var pos: Vector3 = h.GetSpatialPosition()
		var bpos: Vector3 = ball.Predict(0)
		var d: float = (bpos - pos).length()
		if i >= turn_at:
			ticks_after += 1
			min_dist = minf(min_dist, d)
			max_dist_after = maxf(max_dist_after, d)
			var ft: int = h.GetCurrentFunctionType()
			fn_after[ft] = int(fn_after.get(ft, 0)) + 1
			if is_touch:
				touches_after += 1
			# условия ранних выходов SelectAnim для НЕ-movement (humanoid.cpp:1170-1177)
			if (ball.Predict(200) - pos).length() > 10.0:
				early_out_a += 1
			var d80: float = (ball.Predict(80) - pos).length()
			if d80 > 2.0 and d80 > d:
				early_out_b += 1
		ball.Process()
	return {"touches": touches_after, "min": min_dist, "max": max_dist_after,
		"fn": fn_after, "eo_a": early_out_a, "eo_b": early_out_b, "n": ticks_after}

func _series(label: String, new_dir: Vector3, vel: float) -> void:
	print("\n=== ", label, " (новое направление ", new_dir, ", скорость ", vel, ") ===")
	print("фаза\tкасаний\tmin_d\tmax_d\tearly_out_A\tearly_out_B\tтипы клипов (1=movement 2=ballcontrol)")
	var lost := 0
	for k in 12:
		var turn_at := 600 + k * 4
		var r: Dictionary = _run(turn_at, new_dir, vel)
		var verdict := "" if r["touches"] > 0 else "  <-- МЯЧ ПОТЕРЯН"
		if r["touches"] == 0:
			lost += 1
		print("+%d\t%d\t%.2f\t%.2f\t%d\t%d\t%s%s" % [
			k * 4, r["touches"], r["min"], r["max"], r["eo_a"], r["eo_b"], str(r["fn"]), verdict])
	print("потерь: ", lost, " из 12")

func _initialize() -> void:
	_setup()
	_series("ПОВОРОТ НА 45° (диагональ)", Vector3(1, -1, 0).normalized(), 3.5)
	_series("ПОВОРОТ НА 90°", Vector3(1, 0, 0), 3.5)
	_series("ПОВОРОТ НА 45°, СПРИНТ", Vector3(1, -1, 0).normalized(), 8.0)
	quit(0)
