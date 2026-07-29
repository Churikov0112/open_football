# Порт GameplayFootball, фаза 1: лаб-сцена + палочник + импортёр .anim — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Цель:** отдельная лаб-сцена, в которой 14-костный скелет-«палочник» (1:1 утилитарный скелет
GameplayFootball) проигрывает любой из 293 `.anim`-клипов с корректной интерполяцией, метаданными
касаний мяча и отладочными маркерами.

**Архитектура:** чистое C#-ядро в `src/gpf/` (порт `animation.cpp` + структуры клипа; классы —
`RefCounted`, чтобы GDScript-тесты могли их дёргать), лаб-презентация в `src/lab/` (Godot-ноды),
данные — read-only копия в `assets/gpf/`. Вся математика живёт в «их» системе координат (Z-вверх,
вперёд = −Y); конверсия осей — одна матрица на узле-обёртке `GpfSpace`, кости не конвертируются.

**Tech stack:** Godot 4.7.1 .NET (`net8.0`, `Godot.NET.Sdk/4.7.1`), C# ядро + GDScript check-харнесс.

**Первоисточники:** спека [2026-07-29-gameplayfootball-port-roadmap-design.md](../specs/2026-07-29-gameplayfootball-port-roadmap-design.md),
тех-разбор [2026-07-29-gameplayfootball-core-report.md](../specs/2026-07-29-gameplayfootball-core-report.md).
C++-оригинал: `C:\Users\User\Desktop\projects\FootballCPP` (номера строк ниже — от него).

## Global Constraints

- **Godot exe:** `C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` (единственный валидный).
- **Перед любым headless-тестом — `dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"`**: headless-команды C# сами не пересобирают.
- **Float-парсинг — только `CultureInfo.InvariantCulture`**: системная локаль RU, `float.Parse("0.5")` без неё упадёт/наврёт.
- **Namespace `Gpf`** для ядра, `Gpf.Lab` для лаб-нод. Никаких GDScript `class_name`/autoload для C#, никаких `[GlobalClass]`.
- **Данные `assets/gpf/**` — read-only копия**, не редактировать ни один `.anim`.
- **Система координат:** внутри ядра и скелета — «их» пространство (Z-вверх, вперёд −Y, кватернионы `x,y,z,w` как в файлах == порядок Godot). Конверсия — только базис узла `GpfSpace`.
- **Check-скрипты** — конвенции репо: `extends SceneTree`, `_initialize()`, аккумулятор `ok`, построчные `print("CHECK FAIL: ...")`, финал `print("CHECK PASS" if ok else "CHECK FAIL")` + `quit(0 if ok else 1)`. `.uid`-файлы тестов коммитятся вместе со скриптом (генерятся `--headless --import`, см. задачу 8).
- **Коммиты** — Conventional Commits, описания по-русски.
- **Вики не трогать до задачи 8** (там всё разом: страница, index, hooks, log.md).
- **Модель по таблице CLAUDE.md:** задачи 2–4 и 6 — порт критичной математики (Fable 5/Opus 5); задачи 1, 7 — механика/сцена (Opus 5/Sonnet 5).
- **Godot 4.7.1 API:** `Skeleton3D.SetBonePoseRotation/SetBonePosePosition/GetBoneGlobalPose/ResetBonePose`, `ImmediateMesh`, `FileAccess`/`DirAccess` — всё существует в 4.7; ничего из 4.8+ не использовать.

---

### Задача 1: Датасет GameplayFootball в репо

**Files:**
- Create: `assets/gpf/animations/**` (копия 293 `.anim` + 3 `.anim.util`, 17 подпапок)
- Create: `assets/gpf/player.object`
- Create: `assets/gpf/LICENSE-GameplayFootball`
- Modify: `ASSET_CREDITS.md` (в конец)

**Interfaces:**
- Produces: пути данных для всех следующих задач: `res://assets/gpf/animations/...`, `res://assets/gpf/player.object`. Тестовые файлы-реперы: `res://assets/gpf/animations/movement/walk/045.anim`, `res://assets/gpf/animations/ballcontrol/idle/000.anim`.

- [ ] **Шаг 1: скопировать данные**

```powershell
New-Item -ItemType Directory -Force "C:\Users\User\Desktop\projects\OpenFootball\assets\gpf"
Copy-Item -Recurse "C:\Users\User\Desktop\projects\FootballCPP\data\media\animations" "C:\Users\User\Desktop\projects\OpenFootball\assets\gpf\animations"
Copy-Item "C:\Users\User\Desktop\projects\FootballCPP\data\media\objects\players\player.object" "C:\Users\User\Desktop\projects\OpenFootball\assets\gpf\player.object"
Copy-Item "C:\Users\User\Desktop\projects\FootballCPP\LICENSE" "C:\Users\User\Desktop\projects\OpenFootball\assets\gpf\LICENSE-GameplayFootball"
```

- [ ] **Шаг 2: проверить количество**

Run: `(Get-ChildItem -Recurse -Filter *.anim "C:\Users\User\Desktop\projects\OpenFootball\assets\gpf\animations").Count`
Expected: `293`

Run: `(Get-ChildItem -Recurse -Filter *.anim.util "C:\Users\User\Desktop\projects\OpenFootball\assets\gpf\animations").Count`
Expected: `3` (`base.anim.util`, `base.inverse.anim.util`, `straight.anim.util` в корне `animations/`)

- [ ] **Шаг 3: запись в ASSET_CREDITS.md** (добавить в конец файла)

```markdown
## GameplayFootball animation dataset (assets/gpf/)

- Источник: GameplayFootball, © Bastiaan Konings Schuiling (форк vi3itor/FootballCPP).
- Файлы: `assets/gpf/animations/**` (293 `.anim` + 3 `.anim.util`), `assets/gpf/player.object`.
- Лицензия: Apache License 2.0 — текст в `assets/gpf/LICENSE-GameplayFootball`.
- Клубные лого/киты из оригинала НЕ копировались (трейдмарки).
```

- [ ] **Шаг 4: коммит**

```bash
git add assets/gpf ASSET_CREDITS.md
git commit -m "feat(gpf): датасет анимаций GameplayFootball (Apache 2.0) в assets/gpf"
```

---

### Задача 2: `Gpf.Animation` — парсер CSV-части `.anim`

**Files:**
- Create: `src/gpf/Animation.cs`
- Test: `tests/check_gpf_anim_parse.gd`

**Interfaces:**
- Consumes: `res://assets/gpf/animations/movement/walk/045.anim` (задача 1).
- Produces (для задач 3–7):
  - `class Gpf.Animation : RefCounted`
  - `bool LoadFromFile(string resPath)`
  - `int GetFrameCount()`, `int GetTrackCount()`, `string GetTrackName(int i)`, `string GetName()`
  - `Godot.Collections.Array GetKeyFrames(string nodeName)` (int-кадры ключей по возрастанию)
  - `Quaternion GetKeyRotation(string nodeName, int frame)`, `Vector3 GetKeyPosition(string nodeName, int frame)`
  - `public static readonly string[] TrackOrder` — 14 имён в порядке файла.

**Формат (сверено с `animation.cpp:1076-1125` и реальными файлами):** текст, CSV-строки до первой
строки `extension...` или `<...`; строка 0 — `player,frame,x,y,z,frame,x,y,z...` (только позиция
корня), строки 1..13 — `имя,frame,qx,qy,qz,qw,...` (только ориентация, порядок компонент == Godot).
Кадры разрежены; `frameCount = maxFrame + 1` (`animation.cpp:123`). 1 кадр = 10 мс.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Парсер CSV-части .anim: треки, порядок, ключи, frameCount.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func quat_eq(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps \
		and absf(a.z - b.z) < eps and absf(a.w - b.w) < eps

func _initialize() -> void:
	var ok := true

	var AnimScript := load("res://src/gpf/Animation.cs")
	if AnimScript == null:
		print("CHECK FAIL: src/gpf/Animation.cs не найден — сначала dotnet build")
		quit(1)
		return
	var anim = AnimScript.new()

	if not anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim"):
		print("CHECK FAIL: LoadFromFile 045.anim"); ok = false

	# 25 кадров (максимальный ключ 24), 14 треков в порядке файла.
	if anim.GetFrameCount() != 25:
		print("CHECK FAIL: frameCount 045 → ", anim.GetFrameCount()); ok = false
	if anim.GetTrackCount() != 14:
		print("CHECK FAIL: trackCount → ", anim.GetTrackCount()); ok = false
	var expected_order := ["player", "body", "middle", "neck",
		"left_shoulder", "left_elbow", "right_shoulder", "right_elbow",
		"left_thigh", "left_knee", "left_ankle",
		"right_thigh", "right_knee", "right_ankle"]
	for i in range(mini(14, anim.GetTrackCount())):
		if anim.GetTrackName(i) != expected_order[i]:
			print("CHECK FAIL: track[", i, "] → ", anim.GetTrackName(i)); ok = false

	# Разреженные ключи left_ankle: 0,3,6,12,24 (строка 11 файла).
	var la_frames: Array = anim.GetKeyFrames("left_ankle")
	if la_frames != [0, 3, 6, 12, 24]:
		print("CHECK FAIL: left_ankle keyframes → ", la_frames); ok = false

	# Точные значения из файла.
	if not quat_eq(anim.GetKeyRotation("body", 24),
			Quaternion(0.010774, -0.147878, -0.372312, 0.916187)):
		print("CHECK FAIL: body@24 → ", anim.GetKeyRotation("body", 24)); ok = false
	if not vec_eq(anim.GetKeyPosition("player", 24), Vector3(-0.64, -0.84, -0.08)):
		print("CHECK FAIL: player@24 → ", anim.GetKeyPosition("player", 24)); ok = false
	if not vec_eq(anim.GetKeyPosition("player", 0), Vector3(0.0, 0.0, -0.09)):
		print("CHECK FAIL: player@0 → ", anim.GetKeyPosition("player", 0)); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает**

Run:
```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_gpf_anim_parse.gd"
```
Expected: `CHECK FAIL: src/gpf/Animation.cs не найден...`, exit code 1.

- [ ] **Шаг 3: реализация `src/gpf/Animation.cs`**

```csharp
using Godot;
using System.Collections.Generic;
using System.Globalization;

namespace Gpf
{
    // Порт клипа GameplayFootball (src/utils/animation.cpp, Apache 2.0).
    // 14 треков: строка 0 "player" — позиция корня, строки 1..13 — джойнты-кватернионы
    // (абсолютная локальная ориентация в пространстве родителя). Кадр = 10 мс, ключи разрежены.
    // Всё — в «их» осях: Z-вверх, вперёд −Y; порядок компонент кватерниона в файле == Godot (x,y,z,w).
    public partial class Animation : RefCounted
    {
        public struct KeyFrame
        {
            public Quaternion Orientation;
            public Vector3 Position;
        }

        private sealed class NodeAnimation
        {
            public string NodeName = "";
            public SortedDictionary<int, KeyFrame> Keys = new();
        }

        public static readonly string[] TrackOrder =
        {
            "player", "body", "middle", "neck",
            "left_shoulder", "left_elbow", "right_shoulder", "right_elbow",
            "left_thigh", "left_knee", "left_ankle",
            "right_thigh", "right_knee", "right_ankle",
        };

        private readonly List<NodeAnimation> _tracks = new();
        private int _frameCount;
        private string _name = "";

        public string GetName() => _name;
        public int GetFrameCount() => _frameCount;
        public int GetTrackCount() => _tracks.Count;
        public string GetTrackName(int i) => _tracks[i].NodeName;

        public Godot.Collections.Array GetKeyFrames(string nodeName)
        {
            var result = new Godot.Collections.Array();
            var track = FindTrack(nodeName);
            if (track != null)
                foreach (int frame in track.Keys.Keys) result.Add(frame);
            return result;
        }

        public Quaternion GetKeyRotation(string nodeName, int frame)
            => FindTrack(nodeName)!.Keys[frame].Orientation;

        public Vector3 GetKeyPosition(string nodeName, int frame)
            => FindTrack(nodeName)!.Keys[frame].Position;

        private NodeAnimation FindTrack(string nodeName)
            => _tracks.Find(t => t.NodeName == nodeName);

        public bool LoadFromFile(string resPath)
        {
            using var f = FileAccess.Open(resPath, FileAccess.ModeFlags.Read);
            if (f == null)
            {
                GD.PushError($"Gpf.Animation: не открыть {resPath}");
                return false;
            }
            _name = resPath;

            // Трёхфазный разбор как в Animation::Load (animation.cpp:1109):
            // CSV-строки → extension-строки → XML-хвост.
            var csv = new List<string[]>();
            var lines = new List<string>();
            while (!f.EofReached())
            {
                string line = f.GetLine();
                if (line.StripEdges().Length > 0) lines.Add(line);
            }

            int cursor = 0;
            for (; cursor < lines.Count; cursor++)
            {
                if (lines[cursor].StartsWith("extension") || lines[cursor].StartsWith("<")) break;
                csv.Add(lines[cursor].Split(','));
            }
            LoadData(csv);

            // extension-строки и XML-хвост подключаются в задаче 4.
            return _tracks.Count > 0;
        }

        // Порт Animation::LoadData (animation.cpp:1076-1107).
        private void LoadData(List<string[]> file)
        {
            for (int line = 0; line < file.Count; line++)
            {
                var tokens = file[line];
                int key = 1;
                while (key < tokens.Length)
                {
                    int frame = int.Parse(tokens[key], CultureInfo.InvariantCulture);
                    var orientation = Quaternion.Identity;
                    var position = Vector3.Zero;
                    if (line != 0)
                    {
                        // джойнты: только ориентация (frame,qx,qy,qz,qw)
                        orientation = new Quaternion(
                            ParseF(tokens[key + 1]), ParseF(tokens[key + 2]),
                            ParseF(tokens[key + 3]), ParseF(tokens[key + 4]));
                        key += 5;
                    }
                    else
                    {
                        // player: только позиция (frame,x,y,z)
                        position = new Vector3(
                            ParseF(tokens[key + 1]), ParseF(tokens[key + 2]), ParseF(tokens[key + 3]));
                        key += 4;
                    }
                    SetKeyFrame(tokens[0], frame, orientation, position);
                }
            }
        }

        private void SetKeyFrame(string nodeName, int frame, Quaternion orientation, Vector3 position)
        {
            var track = FindTrack(nodeName);
            if (track == null)
            {
                track = new NodeAnimation { NodeName = nodeName };
                _tracks.Add(track);
            }
            track.Keys[frame] = new KeyFrame { Orientation = orientation, Position = position };
            if (frame >= _frameCount) _frameCount = frame + 1; // animation.cpp:123
        }

        private static float ParseF(string s) => float.Parse(s, CultureInfo.InvariantCulture);
    }
}
```

- [ ] **Шаг 4: собрать и прогнать**

Run:
```powershell
dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_gpf_anim_parse.gd"
```
Expected: сборка `0 Ошибок`; тест `CHECK PASS`, exit code 0.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/Animation.cs tests/check_gpf_anim_parse.gd
git commit -m "feat(gpf): Gpf.Animation — парсер CSV-части .anim"
```

---

### Задача 3: интерполяция клипа 1:1 с `animation.cpp`

**Files:**
- Create: `src/gpf/QuatUtil.cs`
- Modify: `src/gpf/Animation.cs` (добавить методы)
- Test: `tests/check_gpf_anim_sample.gd`

**Interfaces:**
- Consumes: `Gpf.Animation` из задачи 2.
- Produces (для задач 6–7):
  - `Quaternion Animation.SampleRotation(string nodeName, int frame, float timeOffsetMs)`
  - `Vector3 Animation.SampleRootPosition(int frame, float timeOffsetMs)`
  - `static class Gpf.QuatUtil` (внутренний, только для C#): `Slerp(a, bias, b)`, `Lerp(a, bias, b)`, `SameNeighborhood(q, reference)`.

**Семантика (порт, не изобретение):** между разреженными ключами — их slerp
(`GetInterpolatedValues`, `animation.cpp:179-295`; кватернионный slerp — `quaternion.cpp:352-401`,
включая хак-экстраполяцию `bias > 1`). Субкадровое сглаживание — схема `Animation::Apply`
(`animation.cpp:389-405`): два семпла на `frame` и `frame+1`, `MakeSameNeighborhood`, покомпонентный
lerp с `bias = clamp(timeOffsetMs/10, 0, 1)`, нормализация. Ветки краёв: `frame <= 0` → первый ключ;
`frame >= frameCount` → экстраполяция от двух последних ключей; ключи трека могут кончиться раньше
`frameCount` (он общий на клип) → удержание последнего ключа.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Интерполяция: точный ключ, lerp позиции корня, slerp между ключами, края.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

# Кватернион с точностью до знака (q и -q — один поворот).
func quat_close(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps

func _initialize() -> void:
	var ok := true
	var anim = load("res://src/gpf/Animation.cs").new()
	anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")

	# Семпл на точном ключе с offset 0 == значение ключа.
	if not quat_close(anim.SampleRotation("body", 12, 0.0),
			Quaternion(0.060027, -0.163966, -0.174606, 0.969033)):
		print("CHECK FAIL: SampleRotation body@12 → ", anim.SampleRotation("body", 12, 0.0)); ok = false

	# Позиция корня: кадр 6 между ключами 0 и 12 → линейная интерполяция.
	if not vec_eq(anim.SampleRootPosition(6, 0.0), Vector3(-0.15, -0.2308695, -0.07)):
		print("CHECK FAIL: root@6 → ", anim.SampleRootPosition(6, 0.0)); ok = false

	# Slerp между ключами: left_elbow, ключи 12 и 19, кадр 15 → bias 3/7.
	var q12 := Quaternion(-0.791526, 0.0, 0.0, 0.611136)
	var q19 := Quaternion(-0.567869, 0.0, 0.0, 0.823119)
	var expected := q12.slerp(q19, 3.0 / 7.0)
	if not quat_close(anim.SampleRotation("left_elbow", 15, 0.0), expected, 5.0e-4):
		print("CHECK FAIL: left_elbow@15 → ", anim.SampleRotation("left_elbow", 15, 0.0)); ok = false

	# Субкадровый сдвиг: между кадрами 12 и 13 результат «между» семплами этих кадров.
	var mid := anim.SampleRotation("left_elbow", 12, 5.0)
	if not mid.is_normalized():
		print("CHECK FAIL: субкадровый семпл не нормализован"); ok = false

	# Края: кадр ≤ 0 → первый ключ (ветка frame <= 0).
	if not quat_close(anim.SampleRotation("left_elbow", -3, 0.0),
			Quaternion(-0.402422, 0.0, 0.000001, 0.915454)):
		print("CHECK FAIL: left_elbow@-3 → ", anim.SampleRotation("left_elbow", -3, 0.0)); ok = false
	if not quat_close(anim.SampleRotation("left_elbow", 0, 0.0),
			Quaternion(-0.402422, 0.0, 0.000001, 0.915454)):
		print("CHECK FAIL: left_elbow@0 → ", anim.SampleRotation("left_elbow", 0, 0.0)); ok = false
	if not quat_close(anim.SampleRotation("left_elbow", 24, 0.0),
			Quaternion(-0.269418, 0.0, 0.0, 0.963023), 5.0e-3):
		print("CHECK FAIL: left_elbow@24 → ", anim.SampleRotation("left_elbow", 24, 0.0)); ok = false

	# За концом клипа не падает и выдаёт нормализованный кватернион (экстраполяция).
	if not anim.SampleRotation("left_elbow", 30, 0.0).is_normalized():
		print("CHECK FAIL: экстраполяция за концом"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает**

Run:
```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_gpf_anim_sample.gd"
```
Expected: падение на вызове `SampleRotation` (нет метода) — скрипт-ошибка или `CHECK FAIL`.

- [ ] **Шаг 3: реализация**

`src/gpf/QuatUtil.cs` (порт `quaternion.cpp`, дословно, включая допущения оригинала):

```csharp
using Godot;
using System;

namespace Gpf
{
    // Порт кватернионной математики Blunted2 (src/base/math/quaternion.cpp).
    // НЕ заменять на Godot Slerp: оригинал допускает bias>1 (экстраполяция, animation.cpp:277)
    // и мы обязаны сохранить поведение 1:1.
    public static class QuatUtil
    {
        // quaternion.cpp:426 MakeSameNeighborhood — вернуть q в полусфере reference.
        public static Quaternion SameNeighborhood(Quaternion q, Quaternion reference)
            => q.Dot(reference) < 0 ? new Quaternion(-q.X, -q.Y, -q.Z, -q.W) : q;

        // quaternion.cpp:352 GetSlerped(bias, to).
        public static Quaternion Slerp(Quaternion a, float bias, Quaternion b)
        {
            var qb = b;
            double cosHalfTheta = a.W * qb.W + a.X * qb.X + a.Y * qb.Y + a.Z * qb.Z;
            if (cosHalfTheta < 0)
            {
                qb = new Quaternion(-qb.X, -qb.Y, -qb.Z, -qb.W);
                cosHalfTheta = -cosHalfTheta;
            }
            if (Math.Abs(cosHalfTheta) >= 1.0) return a;

            double halfTheta = Math.Acos(cosHalfTheta);
            double sinHalfTheta = Math.Sqrt(1.0 - cosHalfTheta * cosHalfTheta);
            if (Math.Abs(sinHalfTheta) < 0.000001)
                return new Quaternion(
                    (float)(a.X * 0.5 + qb.X * 0.5), (float)(a.Y * 0.5 + qb.Y * 0.5),
                    (float)(a.Z * 0.5 + qb.Z * 0.5), (float)(a.W * 0.5 + qb.W * 0.5));

            double ratioA = Math.Sin((1 - bias) * halfTheta) / sinHalfTheta;
            double ratioB = Math.Sin(bias * halfTheta) / sinHalfTheta;
            return new Quaternion(
                (float)(a.X * ratioA + qb.X * ratioB), (float)(a.Y * ratioA + qb.Y * ratioB),
                (float)(a.Z * ratioA + qb.Z * ratioB), (float)(a.W * ratioA + qb.W * ratioB));
        }

        // Покомпонентный lerp (нормализует вызывающий — как GetLerped().GetNormalized() в Apply).
        public static Quaternion Lerp(Quaternion a, float bias, Quaternion b)
            => new Quaternion(
                a.X + (b.X - a.X) * bias, a.Y + (b.Y - a.Y) * bias,
                a.Z + (b.Z - a.Z) * bias, a.W + (b.W - a.W) * bias);
    }
}
```

Добавить в `src/gpf/Animation.cs` (внутрь класса):

```csharp
        // Порт GetInterpolatedValues (animation.cpp:179-295).
        private void GetInterpolatedValues(SortedDictionary<int, KeyFrame> keys, int frame,
                                           out Quaternion orientation, out Vector3 position)
        {
            orientation = Quaternion.Identity;
            position = Vector3.Zero;
            if (keys.Count == 0) return;

            if (frame > 0 && frame < _frameCount)
            {
                // последний ключ < frame и первый ключ >= frame (animation.cpp:186-206)
                bool hasBefore = false, hasAfter = false;
                int beforeFrame = 0, afterFrame = 0;
                KeyFrame before = default, after = default;
                foreach (var kv in keys)
                {
                    if (kv.Key >= frame) { after = kv.Value; afterFrame = kv.Key; hasAfter = true; break; }
                    before = kv.Value; beforeFrame = kv.Key; hasBefore = true;
                }

                if (hasBefore && hasAfter)
                {
                    float bias = (frame - beforeFrame) / (float)(afterFrame - beforeFrame);
                    orientation = QuatUtil.Slerp(before.Orientation, bias, after.Orientation);
                    position = before.Position * (1f - bias) + after.Position * bias;
                }
                else if (hasAfter) // все ключи позже текущего кадра
                {
                    orientation = after.Orientation;
                    position = after.Position;
                }
                else // ключи трека кончились раньше frameCount → держим последний
                {
                    orientation = before.Orientation;
                    position = before.Position;
                }
            }
            else if (frame >= _frameCount)
            {
                // экстраполяция за концом (animation.cpp:247-282): slerp с bias > 1
                KeyFrame last = default, secondLast = default;
                int lastFrame = 0, secondLastFrame = 0, seen = 0;
                foreach (var kv in keys)
                {
                    secondLast = last; secondLastFrame = lastFrame;
                    last = kv.Value; lastFrame = kv.Key; seen++;
                }
                if (seen == 1) { orientation = last.Orientation; position = last.Position; return; }
                float dist1 = lastFrame - secondLastFrame;
                float dist2 = frame - lastFrame;
                float bias = 1f + (1f / dist1) * dist2;
                orientation = QuatUtil.Slerp(secondLast.Orientation, bias, last.Orientation);
                position = secondLast.Position * (1f - bias) + last.Position * bias;
            }
            else // frame <= 0 → первый ключ (animation.cpp:284-292)
            {
                foreach (var kv in keys)
                {
                    orientation = kv.Value.Orientation;
                    position = kv.Value.Position;
                    break;
                }
            }
        }

        // Субкадровый семпл по схеме Animation::Apply (animation.cpp:389-405).
        public Quaternion SampleRotation(string nodeName, int frame, float timeOffsetMs)
        {
            var track = FindTrack(nodeName);
            if (track == null) return Quaternion.Identity;
            float bias = Mathf.Clamp(timeOffsetMs / 10f, 0f, 1f);
            GetInterpolatedValues(track.Keys, frame, out var qPre, out _);
            GetInterpolatedValues(track.Keys, frame + 1, out var qPost, out _);
            qPre = QuatUtil.SameNeighborhood(qPre, qPost);
            return QuatUtil.Lerp(qPre, bias, qPost).Normalized();
        }

        public Vector3 SampleRootPosition(int frame, float timeOffsetMs)
        {
            var track = FindTrack("player");
            if (track == null) return Vector3.Zero;
            float bias = Mathf.Clamp(timeOffsetMs / 10f, 0f, 1f);
            GetInterpolatedValues(track.Keys, frame, out _, out var pPre);
            GetInterpolatedValues(track.Keys, frame + 1, out _, out var pPost);
            return pPre * (1f - bias) + pPost * bias;
        }
```

- [ ] **Шаг 4: собрать и прогнать**

Run: `dotnet build` + тот же check-запуск, что в шаге 2.
Expected: `CHECK PASS`, exit 0. Также перегнать `check_gpf_anim_parse.gd` — по-прежнему `CHECK PASS`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/QuatUtil.cs src/gpf/Animation.cs tests/check_gpf_anim_sample.gd
git commit -m "feat(gpf): интерполяция клипа (slerp/nlerp, экстраполяция) 1:1 с animation.cpp"
```

---

### Задача 4: метаданные — касания мяча и XML-хвост

**Files:**
- Modify: `src/gpf/Animation.cs`
- Test: `tests/check_gpf_anim_meta.gd`

**Interfaces:**
- Produces (для задачи 7 и фазы 2):
  - `int GetTouchCount()`, `int GetTouchFrame(int index)`, `Vector3 GetTouchPosition(int index)`
  - `string GetAnimType()` (текст тега `<type>`, например `"movement"`, `"ballcontrol"`)
  - `string GetVariable(string tag)` — сырой текст любого XML-тега хвоста, `""` если нет.

**Формат (сверено):** после CSV идут 0..N строк `extension,football,frame,x,y,z[,frame,x,y,z...]`
(`footballanimationextension.cpp:109-125`), затем XML-хвост — последовательность плоских тегов
верхнего уровня (`<type>`, `<balldirection>` с текстом `0.000000,1.000000,0.000000`, `<steps>`,
`<baseanim>` и т.п.), значения с переводами строк/табами — тримить.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Метаданные клипа: касания мяча (extension,football) и XML-хвост.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	# ballcontrol/idle/000.anim: 38 кадров, 1 касание @12 (0, -0.57, 0.11), type ballcontrol.
	var bc = AnimScript.new()
	bc.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim")
	if bc.GetFrameCount() != 38:
		print("CHECK FAIL: frameCount 000 → ", bc.GetFrameCount()); ok = false
	if bc.GetTouchCount() != 1:
		print("CHECK FAIL: touchCount → ", bc.GetTouchCount()); ok = false
	elif bc.GetTouchFrame(0) != 12 or not vec_eq(bc.GetTouchPosition(0), Vector3(0.0, -0.57, 0.11)):
		print("CHECK FAIL: touch[0] → ", bc.GetTouchFrame(0), " ", bc.GetTouchPosition(0)); ok = false
	if bc.GetAnimType() != "ballcontrol":
		print("CHECK FAIL: type 000 → '", bc.GetAnimType(), "'"); ok = false
	if bc.GetVariable("baseanim") != "true":
		print("CHECK FAIL: baseanim → '", bc.GetVariable("baseanim"), "'"); ok = false
	if bc.GetVariable("nosuchtag") != "":
		print("CHECK FAIL: несуществующий тег должен давать ''"); ok = false

	# movement/walk/045.anim: касаний нет, type movement.
	var mv = AnimScript.new()
	mv.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	if mv.GetTouchCount() != 0:
		print("CHECK FAIL: у walk/045 не должно быть касаний"); ok = false
	if mv.GetAnimType() != "movement":
		print("CHECK FAIL: type 045 → '", mv.GetAnimType(), "'"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает** (тот же шаблон запуска; Expected: скрипт-ошибка/`CHECK FAIL` — методов нет)

- [ ] **Шаг 3: реализация** — в `Animation.cs`:

Поля и публичные методы:

```csharp
        private readonly SortedDictionary<int, Vector3> _touches = new();
        private readonly Dictionary<string, string> _variables = new();

        public int GetTouchCount() => _touches.Count;

        public int GetTouchFrame(int index)
        {
            int i = 0;
            foreach (var kv in _touches) { if (i == index) return kv.Key; i++; }
            return -1;
        }

        public Vector3 GetTouchPosition(int index)
        {
            int i = 0;
            foreach (var kv in _touches) { if (i == index) return kv.Value; i++; }
            return Vector3.Zero;
        }

        public string GetAnimType() => GetVariable("type");

        public string GetVariable(string tag)
            => _variables.TryGetValue(tag, out var v) ? v : "";
```

Приватные парсеры:

```csharp
        // Порт FootballAnimationExtension::Load (footballanimationextension.cpp:109-125).
        private void LoadFootballExtension(string[] tokens)
        {
            int key = 2;
            while (key + 3 < tokens.Length)
            {
                int frame = int.Parse(tokens[key], CultureInfo.InvariantCulture);
                _touches[frame] = new Vector3(
                    ParseF(tokens[key + 1]), ParseF(tokens[key + 2]), ParseF(tokens[key + 3]));
                key += 4;
            }
        }

        // XML-хвост: плоские теги верхнего уровня → словарь тег → тримленный текст.
        private void LoadXmlTail(string xml)
        {
            if (xml.Trim().Length == 0) return;
            var doc = new System.Xml.XmlDocument();
            doc.LoadXml("<root>" + xml + "</root>");
            foreach (System.Xml.XmlNode child in doc.DocumentElement!.ChildNodes)
                if (child.NodeType == System.Xml.XmlNodeType.Element)
                    _variables[child.Name] = child.InnerText.Trim();
        }
```

В `LoadFromFile` после `LoadData(csv);` заменить комментарий-заглушку на:

```csharp
            for (; cursor < lines.Count; cursor++)
            {
                if (!lines[cursor].StartsWith("extension")) break;
                var tokens = lines[cursor].Split(',');
                if (tokens.Length > 1 && tokens[1] == "football") LoadFootballExtension(tokens);
            }

            var xml = new System.Text.StringBuilder();
            for (; cursor < lines.Count; cursor++) xml.AppendLine(lines[cursor]);
            LoadXmlTail(xml.ToString());
```

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build` + `check_gpf_anim_meta.gd` → `CHECK PASS`; перегнать parse/sample-тесты → `CHECK PASS`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/Animation.cs tests/check_gpf_anim_meta.gd
git commit -m "feat(gpf): метаданные клипа — касания мяча и XML-хвост"
```

---

### Задача 5: утилитарный 14-костный скелет + конверсия осей

**Files:**
- Create: `src/gpf/SkeletonBuilder.cs`
- Test: `tests/check_gpf_skeleton.gd`

**Interfaces:**
- Consumes: пропорции из `assets/gpf/player.object` (числа зашиты в код дословно, файл — эталон для сверки).
- Produces (для задач 6–7):
  - `class Gpf.SkeletonBuilder : RefCounted`
  - `Skeleton3D BuildUtilitySkeleton()` — 14 костей, имена == `Animation.TrackOrder`, рест-позы = чистые трансляции из `player.object`, «их» пространство.
  - `Node3D BuildAxisWrapper()` — узел `GpfSpace` с базисом конверсии.
  - `Basis AxisConversionBasis()`.

**Пропорции (дословно из `player.object`, НЕ «на глаз»):** body `(0,0,0.96)`, middle `(0,0,0.15)`,
neck `(0,−0.03,0.5)`, left_shoulder `(0.16,−0.01,0.48)`, left_elbow `(−0.01,0,−0.33)`,
right_shoulder `(−0.16,−0.01,0.48)`, right_elbow `(0.01,0,−0.33)`, left_thigh `(0.087,0,−0.01)`,
left_knee `(0,0,−0.42)`, left_ankle `(0,−0.04,−0.44)`, правая нога — зеркально по X. Рест-повороты
`.object` игнорируем: клип задаёт джойнтам АБСОЛЮТНУЮ локальную ориентацию (`SetRotation`,
`animation.cpp:694-710`), а `.object`-повороты нужны были только для расстановки сегментных мешей.

**Конверсия осей:** их (Z-вверх, вперёд −Y, правая тройка) → Godot (Y-вверх, вперёд −Z): образы осей
X→`(−1,0,0)`, Y→`(0,0,1)`, Z→`(0,1,0)`. Это собственная ротация (det = +1, не зеркало), их «вперёд»
`(0,−1,0)` переходит в Godot-«вперёд» `(0,0,−1)`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Скелет: 14 костей, иерархия, рест-позы из player.object, базис конверсии осей.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-6) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var builder = load("res://src/gpf/SkeletonBuilder.cs").new()
	var skel: Skeleton3D = builder.BuildUtilitySkeleton()

	if skel.get_bone_count() != 14:
		print("CHECK FAIL: bone count → ", skel.get_bone_count()); ok = false

	# Иерархия: пары (кость, родитель).
	var parents := {
		"body": "player", "middle": "body", "neck": "middle",
		"left_shoulder": "middle", "left_elbow": "left_shoulder",
		"right_shoulder": "middle", "right_elbow": "right_shoulder",
		"left_thigh": "body", "left_knee": "left_thigh", "left_ankle": "left_knee",
		"right_thigh": "body", "right_knee": "right_thigh", "right_ankle": "right_knee",
	}
	for bone in parents:
		var idx := skel.find_bone(bone)
		if idx < 0:
			print("CHECK FAIL: нет кости ", bone); ok = false; continue
		var pidx := skel.get_bone_parent(idx)
		if pidx < 0 or skel.get_bone_name(pidx) != parents[bone]:
			print("CHECK FAIL: родитель ", bone, " → ", skel.get_bone_name(pidx) if pidx >= 0 else "нет"); ok = false
	if skel.get_bone_parent(skel.find_bone("player")) != -1:
		print("CHECK FAIL: player должен быть корнем"); ok = false

	# Рест-позы (player.object, дословно).
	var rests := {
		"player": Vector3(0, 0, 0), "body": Vector3(0, 0, 0.96), "middle": Vector3(0, 0, 0.15),
		"neck": Vector3(0, -0.03, 0.5),
		"left_shoulder": Vector3(0.16, -0.01, 0.48), "left_elbow": Vector3(-0.01, 0, -0.33),
		"right_shoulder": Vector3(-0.16, -0.01, 0.48), "right_elbow": Vector3(0.01, 0, -0.33),
		"left_thigh": Vector3(0.087, 0, -0.01), "left_knee": Vector3(0, 0, -0.42),
		"left_ankle": Vector3(0, -0.04, -0.44),
		"right_thigh": Vector3(-0.087, 0, -0.01), "right_knee": Vector3(0, 0, -0.42),
		"right_ankle": Vector3(0, -0.04, -0.44),
	}
	for bone in rests:
		var idx := skel.find_bone(bone)
		if idx >= 0 and not vec_eq(skel.get_bone_rest(idx).origin, rests[bone]):
			print("CHECK FAIL: rest ", bone, " → ", skel.get_bone_rest(idx).origin); ok = false

	# Базис конверсии: собственная ротация, «их вперёд» (0,-1,0) → Godot (0,0,-1), «их верх» → (0,1,0).
	var wrapper: Node3D = builder.BuildAxisWrapper()
	var b: Basis = wrapper.basis
	if absf(b.determinant() - 1.0) > 1.0e-6:
		print("CHECK FAIL: det базиса → ", b.determinant()); ok = false
	if not vec_eq(b * Vector3(0, -1, 0), Vector3(0, 0, -1)):
		print("CHECK FAIL: их-вперёд → ", b * Vector3(0, -1, 0)); ok = false
	if not vec_eq(b * Vector3(0, 0, 1), Vector3(0, 1, 0)):
		print("CHECK FAIL: их-верх → ", b * Vector3(0, 0, 1)); ok = false

	skel.free()
	wrapper.free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает** (Expected: `SkeletonBuilder.cs` не найден)

- [ ] **Шаг 3: реализация `src/gpf/SkeletonBuilder.cs`**

```csharp
using Godot;

namespace Gpf
{
    // Утилитарный скелет 1:1 data/media/objects/players/player.object (позиции — дословно).
    // Скелет живёт в «их» пространстве (Z-вверх, вперёд −Y); конверсия осей — базис
    // родителя-обёртки GpfSpace, кости не трогаем. Рест-повороты .object игнорируются:
    // клип пишет джойнтам абсолютную локальную ориентацию.
    public partial class SkeletonBuilder : RefCounted
    {
        private static readonly (string Name, string Parent, Vector3 Pos)[] Bones =
        {
            ("player",         "",               new Vector3(0, 0, 0)),
            ("body",           "player",         new Vector3(0, 0, 0.96f)),
            ("middle",         "body",           new Vector3(0, 0, 0.15f)),
            ("neck",           "middle",         new Vector3(0, -0.03f, 0.5f)),
            ("left_shoulder",  "middle",         new Vector3(0.16f, -0.01f, 0.48f)),
            ("left_elbow",     "left_shoulder",  new Vector3(-0.01f, 0, -0.33f)),
            ("right_shoulder", "middle",         new Vector3(-0.16f, -0.01f, 0.48f)),
            ("right_elbow",    "right_shoulder", new Vector3(0.01f, 0, -0.33f)),
            ("left_thigh",     "body",           new Vector3(0.087f, 0, -0.01f)),
            ("left_knee",      "left_thigh",     new Vector3(0, 0, -0.42f)),
            ("left_ankle",     "left_knee",      new Vector3(0, -0.04f, -0.44f)),
            ("right_thigh",    "body",           new Vector3(-0.087f, 0, -0.01f)),
            ("right_knee",     "right_thigh",    new Vector3(0, 0, -0.42f)),
            ("right_ankle",    "right_knee",     new Vector3(0, -0.04f, -0.44f)),
        };

        public Skeleton3D BuildUtilitySkeleton()
        {
            var skel = new Skeleton3D { Name = "GpfSkeleton" };
            foreach (var b in Bones)
            {
                int idx = skel.AddBone(b.Name);
                if (b.Parent != "") skel.SetBoneParent(idx, skel.FindBone(b.Parent));
                skel.SetBoneRest(idx, new Transform3D(Basis.Identity, b.Pos));
                skel.ResetBonePose(idx);
            }
            return skel;
        }

        // Их оси → Godot: X→(−1,0,0), Y→(0,0,1), Z→(0,1,0). det=+1 (ротация, не зеркало);
        // их «вперёд» (0,−1,0) становится Godot-«вперёд» (0,0,−1), Z-вверх — Y-вверх.
        public Basis AxisConversionBasis()
            => new Basis(new Vector3(-1, 0, 0), new Vector3(0, 0, 1), new Vector3(0, 1, 0));

        public Node3D BuildAxisWrapper()
            => new Node3D { Name = "GpfSpace", Basis = AxisConversionBasis() };
    }
}
```

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build` + `check_gpf_skeleton.gd` → `CHECK PASS`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/SkeletonBuilder.cs tests/check_gpf_skeleton.gd
git commit -m "feat(gpf): утилитарный 14-костный скелет + конверсия осей"
```

---

### Задача 6: `AnimationApplier` — применение кадра на Skeleton3D

**Files:**
- Create: `src/gpf/AnimationApplier.cs`
- Test: `tests/check_gpf_apply.gd`

**Interfaces:**
- Consumes: `Gpf.Animation` (задачи 2–4), `Gpf.SkeletonBuilder` (задача 5).
- Produces (для задачи 7):
  - `class Gpf.AnimationApplier : RefCounted`
  - `void Apply(Skeleton3D skel, Gpf.Animation anim, int frame, float timeOffsetMs, bool noPos = false, float baseRotZ = 0f)`

**Семантика (несглаженный путь `Animation::Apply`, `animation.cpp:370-433, 694-710`):** джойнты →
`SetBonePoseRotation(idx, семпл)` (позиция кости остаётся рестовой); `player` →
`SetBonePosePosition(idx, семпл)`; при `noPos` X и Y корня зануляются (Z остаётся — вертикальные
приседы живут, `animation.cpp:409-416`); `baseRotZ` — доворот `body` вокруг их-вертикали Z
(`animation.cpp:417-422`), в лабе всегда 0, параметр нужен фазам 2+.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Применение кадра: джойнт — абсолютная локальная ротация, player — позиция корня.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func quat_close(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps

func _initialize() -> void:
	var ok := true
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)  # глобальные позы требуют дерева
	var anim = load("res://src/gpf/Animation.cs").new()
	anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	var applier = load("res://src/gpf/AnimationApplier.cs").new()

	applier.Apply(skel, anim, 12, 0.0)

	# body: локальная ротация == ключ кадра 12 из файла.
	var body := skel.find_bone("body")
	if not quat_close(skel.get_bone_pose_rotation(body),
			Quaternion(0.060027, -0.163966, -0.174606, 0.969033)):
		print("CHECK FAIL: body pose → ", skel.get_bone_pose_rotation(body)); ok = false

	# player: позиция корня == ключ кадра 12.
	var root := skel.find_bone("player")
	if not vec_eq(skel.get_bone_pose_position(root), Vector3(-0.30, -0.461739, -0.05)):
		print("CHECK FAIL: root pose → ", skel.get_bone_pose_position(root)); ok = false

	# Глобальная поза body = позиция корня + рест-смещение (0,0,0.96): корень не вращается.
	if not vec_eq(skel.get_bone_global_pose(body).origin, Vector3(-0.30, -0.461739, 0.91)):
		print("CHECK FAIL: body global → ", skel.get_bone_global_pose(body).origin); ok = false

	# Позиция джойнтов не затронута ротацией: рест middle остался (0,0,0.15) локально.
	var middle := skel.find_bone("middle")
	if not vec_eq(skel.get_bone_pose_position(middle), Vector3(0, 0, 0.15)):
		print("CHECK FAIL: middle позиция сползла → ", skel.get_bone_pose_position(middle)); ok = false

	# noPos: X,Y корня зануляются, Z остаётся.
	applier.Apply(skel, anim, 12, 0.0, true)
	if not vec_eq(skel.get_bone_pose_position(root), Vector3(0, 0, -0.05)):
		print("CHECK FAIL: noPos → ", skel.get_bone_pose_position(root)); ok = false

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает** (Expected: `AnimationApplier.cs` не найден)

- [ ] **Шаг 3: реализация `src/gpf/AnimationApplier.cs`**

```csharp
using Godot;

namespace Gpf
{
    // Применение кадра клипа на Skeleton3D — несглаженный путь Animation::Apply
    // (animation.cpp:370-433, 694-710): джойнты получают АБСОЛЮТНУЮ локальную ротацию,
    // player — позицию корня. Сглаживание/offsets/MovementHistory — фазы 3+.
    public partial class AnimationApplier : RefCounted
    {
        public void Apply(Skeleton3D skel, Animation anim, int frame, float timeOffsetMs,
                          bool noPos = false, float baseRotZ = 0f)
        {
            for (int i = 0; i < anim.GetTrackCount(); i++)
            {
                string name = anim.GetTrackName(i);
                int idx = skel.FindBone(name);
                if (idx < 0) continue;

                if (name == "player")
                {
                    Vector3 pos = anim.SampleRootPosition(frame, timeOffsetMs);
                    if (noPos) { pos.X = 0; pos.Y = 0; } // animation.cpp:409-412 (Z остаётся)
                    skel.SetBonePosePosition(idx, pos);
                }
                else
                {
                    Quaternion q = anim.SampleRotation(name, frame, timeOffsetMs);
                    if (name == "body" && baseRotZ != 0f) // animation.cpp:417-422
                        q = (new Quaternion(new Vector3(0, 0, 1), baseRotZ) * q).Normalized();
                    skel.SetBonePoseRotation(idx, q);
                }
            }
        }
    }
}
```

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build` + `check_gpf_apply.gd` → `CHECK PASS`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/AnimationApplier.cs tests/check_gpf_apply.gd
git commit -m "feat(gpf): AnimationApplier — применение кадра на Skeleton3D"
```

---

### Задача 7: лаб-сцена `anim_lab` — палочник, плеер клипов, маркеры касаний

**Files:**
- Create: `scenes/lab/anim_lab.tscn`
- Create: `src/lab/LabMain.cs`
- Create: `src/lab/StickmanRenderer.cs`

**Interfaces:**
- Consumes: всё из задач 2–6.
- Produces: сцена `res://scenes/lab/anim_lab.tscn`, запускаемая отдельно (главная сцена проекта не меняется). Управление: `←`/`→` — клип, `Space` — пауза, `R` — сначала.

- [ ] **Шаг 1: `src/lab/StickmanRenderer.cs`**

```csharp
using Godot;

namespace Gpf.Lab
{
    // Палочник: линии костей по глобальным позам Skeleton3D. Работает в координатах
    // скелета («их» пространство) — обязан быть братом скелета под GpfSpace с identity-трансформом.
    // Левая сторона красная, правая синяя — контроль зеркала при приёмке.
    public partial class StickmanRenderer : MeshInstance3D
    {
        private Skeleton3D _skeleton;
        private ImmediateMesh _mesh;

        public void Setup(Skeleton3D skeleton)
        {
            _skeleton = skeleton;
            _mesh = new ImmediateMesh();
            Mesh = _mesh;
            MaterialOverride = new StandardMaterial3D
            {
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                VertexColorUseAsAlbedo = true,
            };
        }

        public override void _Process(double delta)
        {
            if (_skeleton == null) return;
            _mesh.ClearSurfaces();
            _mesh.SurfaceBegin(Mesh.PrimitiveType.Lines);
            for (int i = 0; i < _skeleton.GetBoneCount(); i++)
            {
                int parent = _skeleton.GetBoneParent(i);
                if (parent < 0) continue;
                _mesh.SurfaceSetColor(BoneColor(_skeleton.GetBoneName(i)));
                _mesh.SurfaceAddVertex(_skeleton.GetBoneGlobalPose(parent).Origin);
                _mesh.SurfaceAddVertex(_skeleton.GetBoneGlobalPose(i).Origin);
            }
            _mesh.SurfaceEnd();
        }

        private static Color BoneColor(string bone)
        {
            if (bone.StartsWith("left_")) return new Color(1f, 0.25f, 0.25f);
            if (bone.StartsWith("right_")) return new Color(0.3f, 0.5f, 1f);
            return Colors.White;
        }
    }
}
```

- [ ] **Шаг 2: `src/lab/LabMain.cs`**

```csharp
using Godot;
using System.Collections.Generic;

namespace Gpf.Lab
{
    // Лаб-сцена фазы 1 порта GameplayFootball: палочник + плеер .anim-клипов.
    // ←/→ — смена клипа, Space — пауза, R — с начала. Главная сцена проекта не затронута.
    public partial class LabMain : Node3D
    {
        private readonly List<string> _clipPaths = new();
        private readonly Gpf.AnimationApplier _applier = new();
        private readonly List<MeshInstance3D> _touchMarkers = new();
        private Gpf.Animation _anim;
        private int _clipIndex;
        private Skeleton3D _skeleton;
        private Node3D _gpfSpace;
        private Label _label;
        private double _timeMs;
        private bool _paused;

        public override void _Ready()
        {
            // Дисциплина ядра — фикс-тик 100 Гц (только в лабе; матч живёт на дефолтных 60).
            Engine.PhysicsTicksPerSecond = 100;

            var builder = new Gpf.SkeletonBuilder();
            _gpfSpace = builder.BuildAxisWrapper();
            AddChild(_gpfSpace);
            _skeleton = builder.BuildUtilitySkeleton();
            _gpfSpace.AddChild(_skeleton);
            var stickman = new StickmanRenderer();
            _gpfSpace.AddChild(stickman);
            stickman.Setup(_skeleton);

            SetupEnvironment();
            SetupUi();

            ScanClips("res://assets/gpf/animations");
            _clipPaths.Sort();
            GD.Print($"[LAB] clips: {_clipPaths.Count}");
            if (_clipPaths.Count > 0) LoadClip(0);
        }

        private void SetupEnvironment()
        {
            var floor = new MeshInstance3D
            {
                Mesh = new PlaneMesh { Size = new Vector2(20, 20) },
                MaterialOverride = new StandardMaterial3D
                    { AlbedoColor = new Color(0.13f, 0.33f, 0.15f) },
            };
            AddChild(floor);

            var light = new DirectionalLight3D();
            light.RotationDegrees = new Vector3(-55, 30, 0);
            AddChild(light);

            var cam = new Camera3D { Position = new Vector3(2.5f, 1.7f, 3.0f) };
            AddChild(cam);
            cam.LookAt(new Vector3(0, 1, 0));
        }

        private void SetupUi()
        {
            var canvas = new CanvasLayer();
            AddChild(canvas);
            _label = new Label { Position = new Vector2(16, 12) };
            canvas.AddChild(_label);
        }

        private void ScanClips(string dir)
        {
            using var d = DirAccess.Open(dir);
            if (d == null) return;
            d.ListDirBegin();
            for (string f = d.GetNext(); f != ""; f = d.GetNext())
            {
                string path = dir + "/" + f;
                if (d.CurrentIsDir()) { if (!f.StartsWith(".")) ScanClips(path); }
                else if (f.EndsWith(".anim")) _clipPaths.Add(path);
            }
            d.ListDirEnd();
        }

        private void LoadClip(int index)
        {
            int n = _clipPaths.Count;
            _clipIndex = ((index % n) + n) % n;
            _anim = new Gpf.Animation();
            _anim.LoadFromFile(_clipPaths[_clipIndex]);
            _timeMs = 0;

            foreach (var m in _touchMarkers) m.QueueFree();
            _touchMarkers.Clear();
            for (int i = 0; i < _anim.GetTouchCount(); i++)
            {
                var marker = new MeshInstance3D
                {
                    Mesh = new SphereMesh { Radius = 0.11f, Height = 0.22f },
                    Position = _anim.GetTouchPosition(i), // клип-пространство == GpfSpace
                    MaterialOverride = new StandardMaterial3D
                    {
                        AlbedoColor = new Color(1f, 0.6f, 0.1f, 0.5f),
                        Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
                        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                    },
                };
                _gpfSpace.AddChild(marker);
                _touchMarkers.Add(marker);
            }
        }

        public override void _Process(double delta)
        {
            if (_anim == null || _anim.GetFrameCount() == 0) return;
            if (!_paused)
            {
                _timeMs += delta * 1000.0;
                double lengthMs = _anim.GetFrameCount() * 10.0;
                if (_timeMs >= lengthMs) _timeMs -= lengthMs; // цикл
            }
            int frame = (int)(_timeMs / 10.0);
            float offset = (float)(_timeMs - frame * 10.0);
            _applier.Apply(_skeleton, _anim, frame, offset);

            string touches = "";
            for (int i = 0; i < _anim.GetTouchCount(); i++)
                touches += $" @{_anim.GetTouchFrame(i)}";
            _label.Text = $"{_anim.GetName()}  [{_clipIndex + 1}/{_clipPaths.Count}]\n"
                + $"type: {_anim.GetAnimType()}   frames: {_anim.GetFrameCount()}   frame: {frame}"
                + (touches == "" ? "" : $"   touches:{touches}") + "\n"
                + "←/→ клип   Space пауза   R сначала";
        }

        public override void _UnhandledKeyInput(InputEvent ev)
        {
            if (ev is not InputEventKey k || !k.Pressed || k.Echo) return;
            switch (k.Keycode)
            {
                case Key.Right: LoadClip(_clipIndex + 1); break;
                case Key.Left: LoadClip(_clipIndex - 1); break;
                case Key.Space: _paused = !_paused; break;
                case Key.R: _timeMs = 0; break;
            }
        }
    }
}
```

- [ ] **Шаг 3: `scenes/lab/anim_lab.tscn`** (текстом; uid Godot допишет сам при первом открытии)

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/lab/LabMain.cs" id="1"]

[node name="AnimLab" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Шаг 4: собрать и smoke-прогнать headless**

Run:
```powershell
dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --quit-after 30 res://scenes/lab/anim_lab.tscn
```
Expected: строка `[LAB] clips: 293`, ноль строк `ERROR`/`SCRIPT ERROR` (сцена новая — baseline у неё пустой).

- [ ] **Шаг 5: перегнать обе стандартные валидации** (меню-загрузка и матч-сцена, команды из CLAUDE.md) — baseline матча не изменился по категориям.

- [ ] **Шаг 6: коммит**

```bash
git add scenes/lab/anim_lab.tscn src/lab/LabMain.cs src/lab/StickmanRenderer.cs
git commit -m "feat(lab): лаб-сцена anim_lab — палочник, плеер клипов, маркеры касаний"
```

---

### Задача 8: приёмка глазами, оси, документация

**Files:**
- Create: `docs/wiki/порт-gameplayfootball.md`
- Modify: `docs/wiki/index.md` (строка каталога)
- Modify: `docs/wiki/архитектура.md` (ссылка на новую страницу)
- Modify: `docs/wiki/открытые-вопросы.md` (пункт про фикс-тик)
- Modify: `.claude/hooks/wiki-hint.py` (маппинги новых файлов)
- Modify: `log.md` (веха, только в конец)
- Add: `tests/check_gpf_*.gd.uid`, `scenes/lab/anim_lab.tscn` (uid, если Godot перезаписал)

- [ ] **Шаг 1: визуальная приёмка (человек за рулём).** Запуск:

```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" res://scenes/lab/anim_lab.tscn
```

Чек-лист (все пункты обязательны):
1. `movement/walk/045.anim`: палочник ША ГАЕТ — ноги переступают, руки машут противофазно ногам,
   корень уезжает вперёд со сдвигом **вправо** (в Godot-осях: −Z и +X). Дрейф влево = зеркало осей.
2. **Колени сгибаются назад**, локти — вперёд (внутрь). Сгиб колена вперёд = ошибка знака/порядка
   компонент кватерниона.
3. Палочник стоит **на полу** (стопы ~Y=0, таз ~Y=0.9), не парит и не уходит под пол.
4. `ballcontrol/idle/000.anim`: оранжевый шар-маркер лежит на полу в полуметре перед палочником,
   на кадре ~12 стопа приходит к маркеру.
5. Вертикаль: палочник не лежит на боку (лежит = перепутан базис `GpfSpace`).

Если пункт 1/2 падает — НЕ подгонять базис наугад: проверить по порядку (а) порядок `qx,qy,qz,qw`
в `LoadData`, (б) `SetBonePoseRotation` перезаписывает, а не домножает, (в) базис `GpfSpace` равен
столбцам `X(−1,0,0) Y(0,0,1) Z(0,1,0)`. Наблюдение зафиксировать письменно перед правкой.

- [ ] **Шаг 2: страница вики `docs/wiki/порт-gameplayfootball.md`** — написать по фактическому
состоянию после приёмки. Обязательное содержание (своими словами, это НЕ шаблон для копирования):
что такое порт и ссылка на роадмап-спеку; статус «фаза 1 готова»; структура (`src/gpf/` — ядро,
`src/lab/` — лаба, `assets/gpf/` — данные Apache 2.0, read-only); формат `.anim` в три строки;
инварианты (их пространство внутри / конверсия только в `GpfSpace`; InvariantCulture; кадр = 10 мс;
`frameCount = maxFrame+1`); как запускать лабу и управление; список тестов `check_gpf_*`; ссылки
`[[архитектура]]`, `[[конвенции]]`, `[[открытые-вопросы]]`.

- [ ] **Шаг 3: связать вики.** В `docs/wiki/index.md` добавить строку каталога
(`порт-gameplayfootball.md — C#-ядро порта: .anim-датасет, палочник, лаб-сцена`); в
`docs/wiki/архитектура.md` в конец раздела «Проверка (headless)» добавить ссылку
`Порт ядра GameplayFootball — [[порт-gameplayfootball]]`; в `docs/wiki/открытые-вопросы.md`
переписать пункт про фикс-тик: лаба живёт на 100 Гц (`Engine.PhysicsTicksPerSecond` в
`LabMain._Ready`), перевод матча на 100 Гц — решение фазы 4 (физика мяча).

- [ ] **Шаг 4: `.claude/hooks/wiki-hint.py`** — в словарь `PAGES` добавить:

```python
    # --- порт GameplayFootball (C#) ---
    "Animation.cs":         "порт-gameplayfootball",
    "QuatUtil.cs":          "порт-gameplayfootball",
    "SkeletonBuilder.cs":   "порт-gameplayfootball",
    "AnimationApplier.cs":  "порт-gameplayfootball",
    "LabMain.cs":           "порт-gameplayfootball",
    "StickmanRenderer.cs":  "порт-gameplayfootball",
```

- [ ] **Шаг 5: веха в `log.md`** (только в конец, формат `## [YYYY-MM-DD] тип | описание`):
фаза 1 порта готова — датасет 293 `.anim` в репо, C#-ядро `Gpf.Animation`/`SkeletonBuilder`/
`AnimationApplier` (порт `animation.cpp` парсинг+интерполяция), лаб-сцена с палочником и маркерами
касаний, 5 headless-тестов; что отложено (Mirror, вариации, выбор клипа — фаза 2).

- [ ] **Шаг 6: сгенерировать `.uid` и финальная валидация**

Run:
```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
```
затем все 5 тестов `check_gpf_*.gd` → `CHECK PASS`, обе стандартные headless-команды → baseline
не изменился, `git status` — только ожидаемые файлы (`.uid` тестов и сцены — добавить).

- [ ] **Шаг 7: коммит**

```bash
git add docs/wiki tests/*.uid scenes/lab .claude/hooks/wiki-hint.py log.md
git commit -m "docs(wiki): страница порт-gameplayfootball + веха фазы 1"
```

---

## Самопроверка плана (выполнена при написании)

- **Покрытие спеки (фаза 1 роадмапа):** лаб-сцена ✓ (з.7), скелет 1:1 по пропорциям `player.object` ✓
  (з.5, числа дословно), импортёр `.anim` ✓ (з.2–3), парсер метаданных ✓ (з.4), «выбранный клип
  проигрывается на палочнике» ✓ (з.7), отладочные маркеры костей ✓ (палочник = линии+цвета, з.7),
  точки предсказанного касания ✓ (маркеры касаний, з.7), палочник как вечный эталон ✓ (сцена
  остаётся). Дисциплина 100 Гц — в лабе (з.7), глобальный перевод отложен до фазы 4 (з.8, шаг 3).
  Вне скоупа фазы 1 (по спеке): `Mirror()`, генерация вариаций, `AnimCollection`, выбор клипа,
  варпинг, smuggle — фазы 2+.
- **Типы согласованы:** `SampleRotation(string,int,float)` (з.3) == вызовы в з.6/7;
  `GetTouchPosition(int)` (з.4) == з.7; `BuildUtilitySkeleton()`/`BuildAxisWrapper()` (з.5) == з.6/7.
- **Известное упрощение:** `GetInterpolatedValues` в C++ собирает вектор weighed keys; порт делает
  эквивалентный двухуказательный проход — семантика веток совпадает (проверяется тестами з.3),
  структура кода — нет. Осознанно: так читаемее, а тесты держат эквивалентность.
