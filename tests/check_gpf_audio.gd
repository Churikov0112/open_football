extends SceneTree
# Тикет 08 фазы 7: звуковой слой — гейн/порог/питч касания (ball.cpp:553-560) и гейн удара
# о штангу (:324-327).
#
# Разделение слоёв тоже пинится: ядро (`Gpf.Ball`) отдаёт СИГНАЛЫ и не знает ни про
# аудио-узлы, ни про `audio_volume`; формулы живут в плеере лабы (`Gpf.Lab.MatchAudio`).
# Здесь проверяются обе половины: числа формул и то, что сигналы реально уходят.

const AUDIO_VOLUME := 0.5  # GetConfiguration()->GetReal("audio_volume", 0.5f)

var _fails := 0
var _touch_gains: Array[float] = []
var _woodwork_forces: Array[float] = []


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps


func _on_touch(gain: float) -> void:
	_touch_gains.append(gain)


func _on_woodwork(momentum_length: float) -> void:
	_woodwork_forces.append(momentum_length)


func _initialize() -> void:
	print("== check_gpf_audio ==")

	var A = load("res://src/lab/MatchAudio.cs")
	var B = load("res://src/gpf/Ball.cs")
	var R = load("res://src/gpf/GpfRng.cs")
	if A == null or B == null or R == null:
		_fail("нет MatchAudio.cs/Ball.cs/GpfRng.cs — сначала dotnet build")
		_done()
		return

	# ---------- 1. Гейн касания: gain * 0.6 * audio_volume (:554) ----------
	for gain in [0.0, 0.25, 0.5, 1.0]:
		var want: float = gain * 0.6 * AUDIO_VOLUME
		if not feq(A.TouchGain(gain), want):
			_fail("TouchGain(%.2f) = %.6f, ожидалось %.6f" % [gain, A.TouchGain(gain), want])

	# ---------- 2. Порог слышимости 0.01 по ФИНАЛЬНОМУ гейну (:555) ----------
	# 0.03 * 0.6 * 0.5 = 0.009 — тихо; 0.04 * 0.6 * 0.5 = 0.012 — слышно.
	if A.TouchAudible(0.03):
		_fail("порог: касание с гейном 0.03 (финальный 0.009) не должно звучать")
	if not A.TouchAudible(0.04):
		_fail("порог: касание с гейном 0.04 (финальный 0.012) должно звучать")
	# нулевой гейн не звучит никогда
	if A.TouchAudible(0.0):
		_fail("порог: нулевой гейн не должен звучать")

	# ---------- 3. Питч: 0.9 + random(0, 0.2) (:556) ----------
	var rng = R.new()
	rng.Reseed(20260808)
	var mirror = R.new()
	mirror.Reseed(20260808)
	var pitches: Array[float] = []
	for i in range(64):
		var p: float = A.TouchPitch(rng)
		var want_p: float = 0.9 + mirror.Uniform(0.0, 0.2)
		if not feq(p, want_p):
			_fail("TouchPitch: %.6f, ожидалось %.6f (тот же ГСЧ)" % [p, want_p])
			break
		if p < 0.9 or p >= 1.1:
			_fail("TouchPitch вне [0.9, 1.1): %.6f" % p)
			break
		pitches.append(p)
	# «питч заметно варьируется» — разброс по 64 броскам должен покрывать хотя бы полдиапазона
	if pitches.size() == 64:
		var lo: float = pitches.min()
		var hi: float = pitches.max()
		if hi - lo < 0.1:
			_fail("питч почти не гуляет: разброс %.4f на 64 бросках" % (hi - lo))
		else:
			print("питч: %.3f..%.3f по 64 броскам" % [lo, hi])

	# ---------- 4. Гейн штанги: clamp(|momentum| * 0.05, 0.01, 1) * 0.5 * volume (:325) ----------
	for force in [0.0, 5.0, 12.0, 25.0, 100.0]:
		var want_w: float = clampf(force * 0.05, 0.01, 1.0) * 0.5 * AUDIO_VOLUME
		if not feq(A.WoodworkGain(force), want_w):
			_fail("WoodworkGain(%.1f) = %.6f, ожидалось %.6f" % [force, A.WoodworkGain(force), want_w])
	# клампы держат с обеих сторон
	if not feq(A.WoodworkGain(0.0), 0.01 * 0.5 * AUDIO_VOLUME):
		_fail("WoodworkGain: нижний кламп 0.01 не держит")
	if not feq(A.WoodworkGain(1000.0), 1.0 * 0.5 * AUDIO_VOLUME):
		_fail("WoodworkGain: верхний кламп 1.0 не держит")

	# ---------- 5. Ядро отдаёт сигнал касания с гейном шва ----------
	var ball = B.new()
	ball.connect("BallTouchSound", Callable(self, "_on_touch"))
	ball.connect("WoodworkHit", Callable(self, "_on_woodwork"))
	ball.TriggerBallTouchSound(0.42)
	if _touch_gains.size() != 1 or not feq(_touch_gains[0], 0.42):
		_fail("сигнал касания: получено %s, ожидался один гейн 0.42" % [_touch_gains])

	# ---------- 6. Сигнал штанги: есть при ударе, громче при сильном ударе ----------
	# Мяч уже в зоне контакта штанги (PitchHalfW 55, GoalHalfWidth 3.7) — как в check_gpf_ball.
	var forces: Array[float] = []
	for speed in [10.0, 30.0]:
		_woodwork_forces.clear()
		var b2 = B.new()
		b2.connect("WoodworkHit", Callable(self, "_on_woodwork"))
		b2.ResetSituation(Vector3.ZERO)
		b2.SetPosition(Vector3(54.85, 3.7, 1.0))
		# SetPosition обнуляет момент и сам гоняет предсказание — этот сигнал (мяч лежит у
		# штанги без скорости) к удару отношения не имеет, слушаем то, что после SetMomentum
		_woodwork_forces.clear()
		b2.SetMomentum(Vector3(speed, 0, 0))
		if _woodwork_forces.is_empty():
			_fail("удар в штангу на %.0f м/с не дал сигнала" % speed)
			break
		forces.append(_woodwork_forces[0])
	if forces.size() == 2:
		if not (A.WoodworkGain(forces[1]) > A.WoodworkGain(forces[0])):
			_fail("громкость штанги не растёт с силой: %.3f → %.3f"
					% [A.WoodworkGain(forces[0]), A.WoodworkGain(forces[1])])
		else:
			print("штанга: сила %.1f → гейн %.3f, сила %.1f → гейн %.3f"
					% [forces[0], A.WoodworkGain(forces[0]), forces[1], A.WoodworkGain(forces[1])])

	# ---------- 7. Мяч вдали от штанги сигнала не даёт ----------
	_woodwork_forces.clear()
	var b3 = B.new()
	b3.connect("WoodworkHit", Callable(self, "_on_woodwork"))
	b3.ResetSituation(Vector3.ZERO)
	b3.SetPosition(Vector3(0, 0, 1.0))
	b3.SetMomentum(Vector3(20, 0, 0))
	b3.Process()
	if not _woodwork_forces.is_empty():
		_fail("сигнал штанги в центре поля: %s" % [_woodwork_forces])

	# ---------- 8. Выключённые штанги (ball_lab) сигнала не дают ----------
	_woodwork_forces.clear()
	var b4 = B.new()
	b4.WoodworkEnabled = false
	b4.connect("WoodworkHit", Callable(self, "_on_woodwork"))
	b4.ResetSituation(Vector3.ZERO)
	b4.SetPosition(Vector3(54.85, 3.7, 1.0))
	_woodwork_forces.clear()
	b4.SetMomentum(Vector3(10, 0, 0))
	if not _woodwork_forces.is_empty():
		_fail("WoodworkEnabled = false, а сигнал есть: %s" % [_woodwork_forces])

	# ---------- 9. Проводка плееров: два узла со звуком оригинала ----------
	# Ловит битый путь и несобранный импорт: без потока плеер молчит, а сигнал уходит впустую.
	var host := Node.new()
	var audio = A.new()
	audio.Setup(host)
	var players := []
	for child in host.get_children():
		if child is AudioStreamPlayer:
			players.append(child)
	if players.size() != 2:
		_fail("плееров %d, ожидалось два (касание и штанга)" % players.size())
	for player in players:
		if player.stream == null:
			_fail("у плеера %s нет потока — проверь assets/gpf/media/sounds" % player.name)
	# Само проигрывание тут не дёргаем: узлы этого скрипта в дерево попадают только на первом
	# кадре, а Play() вне дерева движок считает ошибкой. Гейт по порогу и обе формулы гейна
	# проверены выше как чистые функции — играть нечем и незачем (драйвер headless — Dummy).
	host.queue_free()

	_done()


func _done() -> void:
	print("CHECK PASS" if _fails == 0 else "CHECK FAIL: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)
