extends SceneTree

# Исходники ассетов оригинала лежат в репозитории зеркалом путей GameplayFootball:
# `data/media/<путь>` оригинала → `assets/gpf/media/<путь>` порта. Это делает якоря в
# комментариях порта честными и убирает зависимость сборки от второго проекта на диске.
#
# Скрипт закрепляет ГРАНИЦУ набора: что обязано лежать (фаза 7) и что обязано отсутствовать
# (меню, гербы, шрифты — фазы 8 и 10). Ошибка «скопировал всё подряд» ловится так же, как
# ошибка «забыл файл».

const MEDIA := "res://assets/gpf/media"

# Все 29 .ase оригинала (`data/media/**/*.ase`) и все 7 .object-обёрток.
const ASE := [
	"objects/balls/generic.ase",
	"objects/helpers/blue.ase",
	"objects/helpers/direction.ase",
	"objects/helpers/green.ase",
	"objects/helpers/largedebugcircle.ase",
	"objects/helpers/red.ase",
	"objects/helpers/smalldebugcircle.ase",
	"objects/helpers/yellow.ase",
	"objects/menu/background01.ase",
	"objects/officials/redcard.ase",
	"objects/officials/yellowcard.ase",
	"objects/players/hairstyles/bald.ase",
	"objects/players/hairstyles/long01.ase",
	"objects/players/hairstyles/medium01.ase",
	"objects/players/hairstyles/medium02.ase",
	"objects/players/hairstyles/short01.ase",
	"objects/players/hairstyles/short02.ase",
	"objects/players/models/foot.ase",
	"objects/players/models/fullbody.ase",
	"objects/players/models/head.ase",
	"objects/players/models/lowerarm.ase",
	"objects/players/models/lowerleg.ase",
	"objects/players/models/pelvis.ase",
	"objects/players/models/trunk.ase",
	"objects/players/models/upperarm.ase",
	"objects/players/models/upperleg.ase",
	"objects/stadiums/goals.ase",
	"objects/stadiums/test/pitch.ase",
	"objects/stadiums/test/test.ase",
]

const OBJECT := [
	"objects/balls/generic.object",
	"objects/lighting/generic.object",
	"objects/players/fullbody.object",
	"objects/players/player.object",
	"objects/stadiums/goals.object",
	"objects/stadiums/test/pitchonly.object",
	"objects/stadiums/test/test.object",
]

# Все 6 wav оригинала. Проводка crowd/whistle — фаза 8, но файлы едут сейчас.
const WAV := [
	"sounds/ballsound.wav",
	"sounds/crowd01.wav",
	"sounds/crowd02.wav",
	"sounds/goalpost.wav",
	"sounds/whistle2.wav",
	"sounds/whistle3.wav",
]

# Текстуры фазы: всё, на что ссылаются *BITMAP четырёх .ase стадиона/мяча, плюс вход
# генератора газона (seamlessgrass08 + overlay), плюс набор адбордов RandomizeAdboards,
# плюс фолбэк диффуза aseloader (orange.jpg) и служебные заливки textures/.
const TEXTURES := [
	# *BITMAP test.ase
	"objects/stadiums/test/abstractads.png",
	"objects/stadiums/test/floor01wall.png",
	"objects/stadiums/test/floor01wall_selfillum.png",
	"objects/stadiums/test/floor01wall_specular.png",
	"objects/stadiums/test/floor02wall.png",
	"objects/stadiums/test/floor02wall_specular.png",
	"objects/stadiums/test/hekje.png",
	"objects/stadiums/test/lightgrey.png",
	"textures/concrete/concrete.wall01_normal.jpg",
	"textures/concrete/concrete.wall01_specular.jpg",
	"textures/concrete/concrete.wall01a.jpg",
	"textures/stadium/ad_placeholder.jpg",
	"textures/stadium/crowd01.png",
	"textures/stadium/crowd01_normal.png",
	"textures/stadium/greenish_floor.png",
	# *BITMAP pitch.ase
	"textures/pitch/pitch_01.png",
	"textures/pitch/pitch_02.png",
	"textures/pitch/pitch_03.png",
	"textures/pitch/pitch_04.png",
	"textures/pitch/pitch_normal_01.png",
	"textures/pitch/pitch_normal_02.png",
	"textures/pitch/pitch_normal_03.png",
	"textures/pitch/pitch_normal_04.png",
	"textures/pitch/pitch_specular_01.png",
	"textures/pitch/pitch_specular_02.png",
	"textures/pitch/pitch_specular_03.png",
	"textures/pitch/pitch_specular_04.png",
	# *BITMAP goals.ase
	"objects/stadiums/white.png",
	"textures/stadium/goalnetting.png",
	# *BITMAP generic.ase
	"objects/balls/ball.jpg",
	# вход генератора газона
	"textures/pitch/overlay.png",
	"textures/pitch/seamlessgrass08.png",
	# фолбэк диффуза aseloader.cpp:39-98 и служебные заливки
	"textures/orange.jpg",
	"textures/almost_black.png",
	"textures/almost_white.png",
	"textures/black.png",
	"textures/white.png",
	# не в *BITMAP, но лежат в каталогах стадиона и бетона — едут вместе с ними
	"objects/stadiums/test/goals.png",
	"objects/stadiums/test/seat01.png",
	"objects/stadiums/test/seat01_normal.png",
	"objects/stadiums/test/white.png",
	"textures/concrete/concrete.wall01_normalb.jpg",
]

# Набор RandomizeAdboards (match.cpp:571-573) — подмена диффуза ad_placeholder.jpg.
const ADBOARDS := [
	"ad_3xblast01.png",
	"ad_altfunc01.png",
	"ad_blauwprint01.png",
	"ad_bleep01.png",
	"ad_brokenbread01.png",
	"ad_groningen01.png",
	"ad_indietopia01.png",
	"ad_omeganorth01.png",
	"ad_polygon01.png",
	"ad_polygon02.png",
	"ad_polygon_flyingdutchman02.png",
	"ad_polygon_jigsawHD02.png",
	"ad_stark01.png",
	"ad_stark02.png",
	"ad_tenshu01.png",
	"ad_your_ad_here.png",
]

# Фазы 8 и 10: текстуры меню, гербы команд/соревнований, шрифты. Сюда не едут.
const FORBIDDEN_DIRS := [
	"menu",
	"fonts",
	"blunted",
	"objects/players/textures",
]

var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("  FAIL: ", msg)


func _expect_files(label: String, rels: Array) -> void:
	var missing: Array[String] = []
	for rel in rels:
		if not FileAccess.file_exists("%s/%s" % [MEDIA, rel]):
			missing.append(rel)
	if missing.is_empty():
		print("%s: %d/%d" % [label, rels.size(), rels.size()])
	else:
		_fail("%s — нет %d из %d: %s" % [label, missing.size(), rels.size(),
				", ".join(missing.slice(0, 5))])


# Файлы .ase/.object/.anim читаются сырым FileAccess, а не импортом Godot. Импортированный
# .ase означал бы, что кто-то поставил аддон Aseprite и движок считает наши данные спрайтом.
func _expect_no_import(rels: Array) -> void:
	var imported: Array[String] = []
	for rel in rels:
		if FileAccess.file_exists("%s/%s.import" % [MEDIA, rel]):
			imported.append(rel)
	if imported.is_empty():
		print("импорт .ase/.object: не создаётся (%d файлов)" % rels.size())
	else:
		_fail("Godot импортирует данные оригинала: %s" % ", ".join(imported.slice(0, 5)))


func _initialize() -> void:
	print("== check_gpf_media ==")

	if not DirAccess.dir_exists_absolute(MEDIA):
		_fail("нет каталога %s — ассеты оригинала не зеркалированы в репозиторий" % MEDIA)
		_done()
		return

	_expect_files(".ase", ASE)
	_expect_files(".object", OBJECT)
	_expect_files("wav", WAV)
	_expect_files("текстуры фазы", TEXTURES)

	var ads: Array[String] = []
	for name in ADBOARDS:
		ads.append("textures/adboards/%s" % name)
	_expect_files("адборды", ads)

	for dir in FORBIDDEN_DIRS:
		if DirAccess.dir_exists_absolute("%s/%s" % [MEDIA, dir]):
			_fail("каталог %s приехал, хотя это фаза 8/10" % dir)

	_expect_no_import(ASE)
	_expect_no_import(OBJECT)

	_done()


func _done() -> void:
	if _fails == 0:
		print("OK: ассеты фазы 7 на месте, лишнего нет")
	else:
		print("ПРОВАЛЕНО: %d расхождений" % _fails)
	quit(1 if _fails > 0 else 0)
