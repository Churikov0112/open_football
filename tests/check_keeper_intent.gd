extends SceneTree
## Headless-проверка keeper-шва: stick_to_zone (5 зон + дедзона), HumanKeeperIntent (через
## фейковый сабкласс со скриптованными осями), AIKeeperIntent (детерминизм по сиду). Всё
## синхронно в _init — RefCounted, узлы не нужны.

class _FakeHKI extends HumanKeeperIntent:
	var ax_lat := 0.0   # значение _axis(...move_right)
	var ax_vert := 0.0  # значение _axis(...move_back)
	func _axis(neg: StringName, pos: StringName) -> float:
		if pos == &"move_right": return ax_lat
		if pos == &"move_back": return ax_vert
		return 0.0

func _init() -> void:
	var ok := true

	# stick_to_zone: знаки → зоны, дедзона → CENTER.
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(0, 0), 0.15), PenaltyLogic.Zone.CENTER, "нейтраль→CENTER") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(0.1, 0.05), 0.15), PenaltyLogic.Zone.CENTER, "в дедзоне→CENTER") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(-1, 1), 0.15), PenaltyLogic.Zone.HIGH_L, "лево-верх→HIGH_L") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(-1, -1), 0.15), PenaltyLogic.Zone.LOW_L, "лево-низ→LOW_L") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(1, 1), 0.15), PenaltyLogic.Zone.HIGH_R, "право-верх→HIGH_R") and ok
	ok = _z(PenaltyLogic.stick_to_zone(Vector2(1, -1), 0.15), PenaltyLogic.Zone.LOW_R, "право-низ→LOW_R") and ok

	# HumanKeeperIntent: конфиг осей → стик → зона.
	var cfg := {"aim_lat": [&"move_left", &"move_right"], "aim_vert": [&"move_forward", &"move_back"]}
	var f := _FakeHKI.new(cfg)
	# ax_lat=+1 (право), ax_vert=-1 → y = -(-1)=+1 (верх) → HIGH_R.
	f.ax_lat = 1.0
	f.ax_vert = -1.0
	ok = _z(f.dive_zone(), PenaltyLogic.Zone.HIGH_R, "HKI право+верх→HIGH_R") and ok
	# нейтраль → CENTER.
	f.ax_lat = 0.0
	f.ax_vert = 0.0
	ok = _z(f.dive_zone(), PenaltyLogic.Zone.CENTER, "HKI нейтраль→CENTER") and ok

	# База KeeperIntent → CENTER.
	ok = _z(KeeperIntent.new().dive_zone(), PenaltyLogic.Zone.CENTER, "база→CENTER") and ok

	# AIKeeperIntent: один выбор по сиду, стабилен между вызовами и в [0,4].
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var ai := AIKeeperIntent.new(rng)
	var z1 := ai.dive_zone()
	var z2 := ai.dive_zone()
	ok = _expect(z1 == z2 and z1 >= 0 and z1 <= 4, "AIKeeper детерминирован в [0,4]") and ok

	if ok:
		print("CHECK PASS: keeper_intent")
		quit(0)
	else:
		print("CHECK FAIL: keeper_intent")
		quit(1)

func _z(got: int, want: int, label: String) -> bool:
	if got != want:
		print("  FAIL: ", label, " got=", got, " want=", want)
		return false
	return true

func _expect(cond: bool, label: String) -> bool:
	if not cond:
		print("  FAIL: ", label)
	return cond
