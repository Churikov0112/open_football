extends SceneTree
## Регресс на ПРЕДСУЩЕСТВУЮЩИЙ баг (был с первых коммитов контроллеров, не из рефактора фаз 1-2):
## гол С ПЕНАЛЬТИ/ШТРАФНОГО размораживал поле-ИИ в _release() посреди празднования — игроки
## бежали к мячу вместо idle, вместо «как при обычном голе с игры». Фикс: _release() уважает
## is_celebrating() (пенальти не трогает заморозку; штрафной морозит, т.к. converted-тела рождаются
## активными). Детерминированно: имитируем гол напрямую (_celebrating + _set_ai_frozen), без физики
## мяча — жертва (поле-ИИ team_2) обязана остаться замороженной ПОСЛЕ отработки _release().

var _mm: Node
var _pen: Node
var _fk: Node
var _victim: Node          # поле-ИИ тело team_2 (не вратарь, не управляемый) — должно остаться frozen
var _phase: int = 0
var _t: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

## Заморожен = его Brain-компонент не тикает физпроцесс (как ставит _set_ai_frozen).
func _victim_frozen() -> bool:
	var b = _victim.brain() if _victim != null and _victim.has_method(&"brain") else null
	return b != null and not b.is_physics_processing()

## Имитируем гол (то же, что замыкание GoalArea): празднование + заморозка поля.
func _simulate_goal() -> void:
	_mm.set(&"_celebrating", true)
	_mm.call(&"_set_ai_frozen", true)

func _clear_goal() -> void:
	_mm.set(&"_celebrating", false)
	_mm.call(&"_set_ai_frozen", false)

func _fail(msg: String) -> void:
	print("CHECK FAIL: ", msg)
	quit(1)

func _process(delta: float) -> bool:
	_t += delta
	match _phase:
		0:  # дать сцене осесть, взять узлы + жертву
			if _t < 0.2:
				return false
			_pen = _mm.get_node_or_null("PenaltyController")
			_fk = _mm.get_node_or_null("FreeKickController")
			_victim = _mm.call(&"_away_outfielder")
			if _pen == null or _fk == null:
				_fail("нет контроллера пенальти/штрафного"); return true
			if _victim == null:
				_fail("нет поле-ИИ team_2 для проверки"); return true
			# --- ГЕЙТ ПОДКАТОВ: _poll_ai_tackles во время празднования = no-op (иначе соперник
			#     добивает забившего слайдом → падение + вставание) ---
			_mm.set(&"_celebrating", true)
			var vbrain = _victim.brain() if _victim.has_method(&"brain") else null
			if vbrain != null:
				vbrain.set(&"wants_to_tackle", true)
			_mm.call(&"_poll_ai_tackles")
			if int(_mm.get(&"_tackle_state")) != 0:   # 0 = TackleState.NORMAL
				_fail("подкат стартовал во время празднования (гейт _poll_ai_tackles не сработал)"); return true
			if vbrain != null:
				vbrain.set(&"wants_to_tackle", false)
			_mm.set(&"_celebrating", false)
			# --- ПЕНАЛЬТИ: старт + удар + гол ---
			_pen.start_single(_mm.controlled_player, -_mm.field_length)
			_pen._fire(0.7)                     # → фаза WATCH → позже _release()
			_simulate_goal()
			if not _victim_frozen():
				_fail("поле-ИИ не заморозился при старте празднования (пенальти)"); return true
			_t = 0.0
			_phase = 1
			return false
		1:  # ждём отработки _release() пенальти, затем проверяем что жертва ВСЁ ЕЩЁ заморожена
			if _mm.is_penalty_active():
				if _t > 6.0:
					_fail("пенальти не завершился (release) за 6с"); return true
				return false
			if not _victim_frozen():
				_fail("поле-ИИ РАЗМОРОЖЕН после release пенальти во время празднования (баг)"); return true
			# сброс состояния перед фазой штрафного
			_clear_goal()
			_fk.start(_mm.controlled_player, -_mm.field_length)
			_fk._fire_shot(0.7)                 # → WATCH → позже _release()
			_simulate_goal()
			if not _victim_frozen():
				_fail("поле-ИИ не заморозился при старте празднования (штрафной)"); return true
			_t = 0.0
			_phase = 2
			return false
		2:  # ждём отработки _release() штрафного, затем проверяем заморозку
			if _mm.is_free_kick_active():
				if _t > 6.0:
					_fail("штрафной не завершился (release) за 6с"); return true
				return false
			if not _victim_frozen():
				_fail("поле-ИИ РАЗМОРОЖЕН после release штрафного во время празднования (баг)"); return true
			print("CHECK PASS: set-piece goal keeps field AI frozen through _release (penalty + free kick)")
			quit(0)
			return true
	return false
