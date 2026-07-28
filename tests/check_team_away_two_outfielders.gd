extends SceneTree
## Регресс: у team_2 должно быть ДВА полевых (нужно для кикоффа — партнёр для паса). Раньше был
## только один — эта постоянная добавка сделала матч честным 2v2+вратари.

var _mm: Node
var _elapsed: float = 0.0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/match.tscn")
	_mm = scene.instantiate()
	root.add_child(_mm)

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < 0.15:
		return false
	var away_outfield: Array = _mm._team_away.outfield()
	var home_outfield: Array = _mm._team_home.outfield()
	var ok := away_outfield.size() == 2
	ok = (home_outfield.size() == 2) and ok   # team_1 не затронут — human+teammate как раньше
	print("SMOKE: away_outfield=", away_outfield.size(), " home_outfield=", home_outfield.size())
	if ok:
		print("CHECK PASS: team_away has two outfielders")
		quit(0)
	else:
		print("CHECK FAIL: away_outfield=", away_outfield.size(), " home_outfield=", home_outfield.size())
		quit(1)
	return true
