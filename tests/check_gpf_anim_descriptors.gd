extends SceneTree
# Дескрипторы клипа (animation.cpp:789-1052): скорости с квантованием, углы, направления, нога.
# Эталон — movement/walk/045.anim. Все опорные числа выведены ИЗ КЛЮЧЕЙ ФАЙЛА по формулам C++:
#   player: 0 → (0, 0, -0.09); 12 → (-0.30, -0.461739, -0.05);
#           19 → (-0.474545, -0.674297, -0.075714); 24 → (-0.64, -0.84, -0.08)
#   body@0  = (0.047014, -0.062720, -0.002958, 0.996919) → z-эйлер ≈ -3.4e-07
#   body@24 = (0.010774, -0.147878, -0.372312, 0.916187) → z-эйлер ≈ -0.7853957 (≈ -pi/4)
# ВНИМАНИЕ: у root-трека ЧЕТЫРЕ ключа — outgoing считается по паре 19→24, а не 12→24.

const WALK := "res://assets/gpf/animations/movement/walk/045.anim"
# Чистый idle: root стоит на месте все 5 ключей → outgoing velocity 0.
# (`movement/idle/000.anim` не существует; реальный «нулевой» клип — 000_idlelevel1.)
const IDLE := "res://assets/gpf/animations/movement/idle/000_idlelevel1.anim"

# outgoing angle = FixAngle(GetAngle2D(pos@24 - pos@19)):
#   delta = (-0.165455, -0.165703); atan2(y, x) = -2.3554451 → +2pi = 3.9277402
#   FixAngle: +0.5pi = 5.4985365 → ModulateIntoRange(-pi, pi) = -0.7846493
const OUT_ANGLE := -0.7846493
# outgoing body angle = z-эйлер(body@24) - outgoing angle = -0.7853957 - (-0.7846493) = -0.0007464
const OUT_BODY_ANGLE := -0.0007464

func feq(a: float, b: float, eps := 1.0e-3) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-3) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	var anim = AnimScript.new()
	anim.LoadFromFile(WALK)

	# Квантование корзинами (animation.cpp:825-828): |incoming| = 4.5887, |outgoing| = 4.6833,
	# обе в [4.2, 6.0) → 5.0.
	var iv: float = anim.GetIncomingVelocity()
	if not feq(iv, 5.0):
		print("CHECK FAIL: incoming velocity → ", iv); ok = false
	var ov: float = anim.GetOutgoingVelocity()
	if not feq(ov, 5.0):
		print("CHECK FAIL: outgoing velocity → ", ov); ok = false

	# incoming: (pos@12 - pos@0) / (12 - 0) * 100, Z занулён (animation.cpp:799-814)
	var im: Vector3 = anim.GetIncomingMovement()
	if not vec_eq(im, Vector3(-2.5, -3.847825, 0.0)):
		print("CHECK FAIL: incoming movement → ", im); ok = false
	# outgoing: (pos@24 - pos@19) / (24 - 19) * 100, Z занулён (animation.cpp:837-853)
	var om: Vector3 = anim.GetOutgoingMovement()
	if not vec_eq(om, Vector3(-3.30910, -3.31406, 0.0)):
		print("CHECK FAIL: outgoing movement → ", om); ok = false
	# translation: pos@24 - pos@0, Z занулён (animation.cpp:789-797)
	var tr: Vector3 = anim.GetTranslation()
	if not vec_eq(tr, Vector3(-0.64, -0.84, 0.0)):
		print("CHECK FAIL: translation → ", tr); ok = false

	var oa: float = anim.GetOutgoingAngle()
	if not feq(oa, OUT_ANGLE):
		print("CHECK FAIL: outgoing angle → ", oa); ok = false
	# Порог 3e-4 нарочно жёстче |OUT_BODY_ANGLE|: он отличает «тело смотрит точно по ходу
	# движения» (верно для walk/045) от халтурного возврата нуля.
	var oba: float = anim.GetOutgoingBodyAngle()
	if not feq(oba, OUT_BODY_ANGLE, 3.0e-4):
		print("CHECK FAIL: outgoing body angle → ", oba); ok = false
	# Клип «walk 45» стартует лицом вперёд: z-эйлер первого ключа body ≈ 0.
	var iba: float = anim.GetIncomingBodyAngle()
	if not feq(iba, 0.0, 1.0e-4):
		print("CHECK FAIL: incoming body angle → ", iba); ok = false

	# Направления — производные от углов: GetRotated2D((0,-1,0), angle) = (sin a, -cos a, 0)
	var od: Vector3 = anim.GetOutgoingDirection()
	if not vec_eq(od, Vector3(sin(OUT_ANGLE), -cos(OUT_ANGLE), 0.0)):
		print("CHECK FAIL: outgoing direction → ", od); ok = false
	var ibd: Vector3 = anim.GetIncomingBodyDirection()
	if not vec_eq(ibd, Vector3(0.0, -1.0, 0.0)):
		print("CHECK FAIL: incoming body direction → ", ibd); ok = false
	var obd: Vector3 = anim.GetOutgoingBodyDirection()
	if not vec_eq(obd, Vector3(sin(OUT_BODY_ANGLE), -cos(OUT_BODY_ANGLE), 0.0)):
		print("CHECK FAIL: outgoing body direction → ", obd); ok = false
	# ranged = (0, -outgoingVelocity, 0), повёрнутый на outgoing angle (animation.cpp:855-867)
	var rom: Vector3 = anim.GetRangedOutgoingMovement()
	if not feq(rom.length(), 5.0):
		print("CHECK FAIL: ranged outgoing movement len → ", rom.length()); ok = false
	if not vec_eq(rom, Vector3(5.0 * sin(OUT_ANGLE), -5.0 * cos(OUT_ANGLE), 0.0)):
		print("CHECK FAIL: ranged outgoing movement → ", rom); ok = false

	# Кэш инвалидируется write-API: подмена последнего ключа root меняет outgoing.
	# Новая дельта 19→24 = (-0.30 + 0.474545, -1.42 + 0.674297) = (0.174545, -0.745703),
	# /5*100 → (3.4909, -14.9141), длина 15.317 → корзина 7.0.
	var w = AnimScript.new()
	w.LoadFromFile(WALK)
	# прогреть ВСЕ три кэша, которые проверяем после записи
	var warm: float = w.GetOutgoingVelocity()
	var warm_tr: Vector3 = w.GetTranslation()
	var warm_oa: float = w.GetOutgoingAngle()
	if not feq(warm, 5.0) or not vec_eq(warm_tr, Vector3(-0.64, -0.84, 0.0)) or not feq(warm_oa, OUT_ANGLE):
		print("CHECK FAIL: прогрев кэша → ", warm, " ", warm_tr, " ", warm_oa); ok = false
	w.SetKeyFrame("player", 24, Quaternion.IDENTITY, Vector3(-0.30, -1.42, -0.08))
	var ov2: float = w.GetOutgoingVelocity()
	if not feq(ov2, 7.0):
		print("CHECK FAIL: DirtyCache после SetKeyFrame (velocity) → ", ov2); ok = false
	# translation = pos@24 - pos@0 = (-0.30 - 0, -1.42 - 0)
	var tr2: Vector3 = w.GetTranslation()
	if not vec_eq(tr2, Vector3(-0.30, -1.42, 0.0)):
		print("CHECK FAIL: DirtyCache после SetKeyFrame (translation) → ", tr2); ok = false
	# angle: atan2(-0.745703, 0.174545) = -1.3409680 → +2pi = 4.9423173 → FixAngle = 0.2299283
	var oa2: float = w.GetOutgoingAngle()
	if not feq(oa2, 0.2299283):
		print("CHECK FAIL: DirtyCache после SetKeyFrame (angle) → ", oa2); ok = false

	# ── Ветка ±180° в GetOutgoingAngle (animation.cpp:925-933) ──────────────────────────
	# Синтетика: на копии walk/045 подменяем последний ключ root так, чтобы перемещение 19→24
	# смотрело почти в +Y. Тогда a = GetAngle2D(delta) ≈ pi/2, FixAngle даёт |угол| > 0.95*pi
	# и включается разруливание стороны по z-эйлеру ПОСЛЕДНЕГО ключа body.
	# Знак берётся из СЫРОГО z (без ModulateIntoRange) — у walk/045 это -0.7853957, signSide = -1.
	# key@19 = (-0.474545, -0.674297, ...), знаменатель 24-19 = 5, значит |delta|*20 = скорость.
	for c in [
		# [dx, dy, z-эйлер body@24 (NAN = не трогать), ожидаемый угол, подпись]
		# a = atan2(0.249, 0.02) = 1.4906471 → FixAngle = +3.0614434 (> 0.95pi).
		# signSide(+) != signSide(-0.785) → переброс: pi*0.99*signSide(z) = -3.1101767
		[0.02, 0.249, NAN, -3.1101767, "переброс на сторону body (z<0, угол>0)"],
		# a = atan2(0.249, -0.02) = 1.6509455 → FixAngle = -3.0614434 (< -0.95pi).
		# signSide(-) == signSide(-0.785) → кламп, но |угол| < 0.99pi → значение проходит НАСКВОЗЬ.
		# Именно этот случай отличает ветку «стороны совпали» от переброса.
		[-0.02, 0.249, NAN, -3.0614434, "кламп сквозной (z<0, угол<0, |угол| < 0.99pi)"],
		# a = atan2(0.249, -0.004) = 1.5868592 → FixAngle = -3.1255298 (за -0.99pi).
		# Стороны совпали → кламп РЕАЛЬНО срезает до -0.99pi = -3.1101767.
		[-0.004, 0.249, NAN, -3.1101767, "кламп кусает (z<0, угол<0, |угол| > 0.99pi)"],
		# То же перемещение, что во второй строке, но body@24 развёрнут на +0.5 рад:
		# signSide(-3.0614) != signSide(+0.5) → переброс: pi*0.99*(+1) = +3.1101767.
		# Пара со второй строкой доказывает, что сторона берётся именно из body.
		[-0.02, 0.249, 0.5, 3.1101767, "переброс на сторону body (z>0, угол<0)"],
	]:
		var dx: float = c[0]
		var dy: float = c[1]
		var zbody: float = c[2]
		var want: float = c[3]
		var label: String = c[4]
		var b = AnimScript.new()
		b.LoadFromFile(WALK)
		b.SetKeyFrame("player", 24, Quaternion.IDENTITY, Vector3(-0.474545 + dx, -0.674297 + dy, -0.08))
		if not is_nan(zbody):
			# z-эйлер по QuatUtil.GetAngles для (0, 0, sin(t/2), cos(t/2)) равен ровно t
			b.SetKeyFrame("body", 24, Quaternion(0.0, 0.0, sin(zbody * 0.5), cos(zbody * 0.5)), Vector3.ZERO)
		# ветка ±180° живёт только при outgoing velocity >= 1.8 — держим 5.0
		var bv: float = b.GetOutgoingVelocity()
		if not feq(bv, 5.0):
			print("CHECK FAIL: ±180° [", label, "] скорость вне ветки → ", bv); ok = false
		var ba: float = b.GetOutgoingAngle()
		if not feq(ba, want):
			print("CHECK FAIL: ±180° [", label, "] угол → ", ba, " ждали ", want); ok = false

	# GetOutgoingFootId (animation.cpp:1029-1052). Полная таблица ветвлений:
	# нечётное число шагов меняет ногу, чётное — оставляет текущую.
	var f = AnimScript.new()
	f.LoadFromFile(WALK)
	if f.GetVariable("steps") != "":
		print("CHECK FAIL: у walk/045 не должно быть тега steps → ", f.GetVariable("steps")); ok = false
	# steps нет → 1 шаг (нечёт), дефолтная нога right=1 → left=0
	if f.GetOutgoingFootId() != 0:
		print("CHECK FAIL: outgoing foot (steps пусто, from right) → ", f.GetOutgoingFootId()); ok = false
	f.SetCurrentFootId(0) # left, нечёт → right=1
	if f.GetOutgoingFootId() != 1:
		print("CHECK FAIL: outgoing foot (steps пусто, from left) → ", f.GetOutgoingFootId()); ok = false
	f.SetVariable("steps", "2") # чёт → нога сохраняется: left → left=0
	if f.GetOutgoingFootId() != 0:
		print("CHECK FAIL: outgoing foot (steps=2, from left) → ", f.GetOutgoingFootId()); ok = false
	f.SetCurrentFootId(1) # чёт, right → right=1
	if f.GetOutgoingFootId() != 1:
		print("CHECK FAIL: outgoing foot (steps=2, from right) → ", f.GetOutgoingFootId()); ok = false

	# idle-клип: root стоит → outgoing velocity 0 → outgoing body angle обязан быть 0
	# (animation.cpp:1020-1022), а outgoing angle падает в ветку z-эйлера body (:935-956).
	var idle = AnimScript.new()
	idle.LoadFromFile(IDLE)
	var idle_ov: float = idle.GetOutgoingVelocity()
	if not feq(idle_ov, 0.0):
		print("CHECK FAIL: idle outgoing velocity → ", idle_ov); ok = false
	var idle_iv: float = idle.GetIncomingVelocity()
	if not feq(idle_iv, 0.0):
		print("CHECK FAIL: idle incoming velocity → ", idle_iv); ok = false
	var idle_oba: float = idle.GetOutgoingBodyAngle()
	if not feq(idle_oba, 0.0):
		print("CHECK FAIL: idle outgoing body angle → ", idle_oba); ok = false
	# body всех ключей idle = (0.031410, 0, 0, 0.999507) → z-эйлер 0
	var idle_oa: float = idle.GetOutgoingAngle()
	if not feq(idle_oa, 0.0):
		print("CHECK FAIL: idle outgoing angle → ", idle_oa); ok = false
	var idle_tr: Vector3 = idle.GetTranslation()
	if not vec_eq(idle_tr, Vector3.ZERO):
		print("CHECK FAIL: idle translation → ", idle_tr); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
