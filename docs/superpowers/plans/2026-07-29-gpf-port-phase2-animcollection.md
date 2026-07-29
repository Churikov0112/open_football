# Порт GameplayFootball, фаза 2: AnimCollection — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Цель:** палочник в лаб-сцене бегает по подаваемым командам (направление/скорость), выбирая
правильный клип из полной библиотеки: 283 файловых клипа ×2 (зеркала) + автогенерированные
вариации из 10 шаблонов ×2, с квадрантами, CrudeSelection и цепочкой stable_sort-предикатов.

**Архитектура:** дословный порт `animcollection.{hpp,cpp}` + недостающих кусков `animation.cpp`
(write-API, Mirror, кэш-дескрипторы, ConvertToStartFacingForwardIfIdle) + слоя сортировок из
`humanoidbase.cpp` в чистое C#-ядро `src/gpf/` (`RefCounted`, тестируется GDScript-чеками).
Лаб-презентация — новая сцена `walk_lab.tscn` в `src/lab/`. Всё — в «их» осях (Z-вверх, вперёд −Y).

**Tech stack:** Godot 4.7.1 .NET (`net8.0`), C# ядро + GDScript check-харнесс.

**Первоисточники:** роадмап [2026-07-29-gameplayfootball-port-roadmap-design.md](../specs/2026-07-29-gameplayfootball-port-roadmap-design.md) (п. 2 фазировки),
тех-отчёт [2026-07-29-gameplayfootball-core-report.md](../specs/2026-07-29-gameplayfootball-core-report.md) §2.
C++-оригинал: `C:\Users\User\Desktop\projects\FootballCPP` (все номера строк ниже — от него; read-only).
Ключевые файлы: `src/onthepitch/player/humanoid/animcollection.{hpp,cpp}`, `src/utils/animation.cpp`,
`src/onthepitch/player/humanoid/humanoidbase.cpp`, `src/base/math/bluntmath.{hpp,cpp}`,
`src/base/math/vector3.hpp`, `src/base/math/quaternion.cpp`, `src/utils.cpp`, `src/gamedefines.hpp`.

## Global Constraints

- **Godot exe:** `C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` (единственный валидный).
- **Перед любым headless-тестом — `dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"`**: headless-команды C# сами не пересобирают.
- **Float-парсинг — только `CultureInfo.InvariantCulture`** (системная локаль RU). Аналог `atof("")`
  оригинала — 0, не исключение: используем `BluntMath.AtoF`/`AtoI` (задача 1).
- **Namespace `Gpf`** для ядра, `Gpf.Lab` для лаб-нод. Никаких `[GlobalClass]`, никакого чтения
  `FootballConstants` из ядра.
- **Данные `assets/gpf/**` — read-only**, не редактировать ни один `.anim`.
- **Оси:** ядро и скелет — «их» пространство (Z-вверх, вперёд −Y). Конверсия — только базис `GpfSpace`.
- **Порт дословный, с константами и порядком применения 1:1**, каждая функция — с комментарием-ссылкой
  на файл:строки C++. Замеченные баги оригинала (например, `queryIncomingToFenceSide +
  fenceToOutgoingAngle` в `animcollection.cpp:619` — enum складывается с радианами) портируются
  **bug-for-bug** с пометкой в комментарии.
- **Сортировки только стабильные.** `List<T>.Sort` в C# НЕстабилен; всё, что в оригинале
  `std::stable_sort`, идёт через `AnimSelector.StableSort` (LINQ `OrderBy` — документированно
  стабилен). Нарушение = недетерминированный выбор клипа.
- **Интероп GDScript↔C#** (из фазы 1, `docs/wiki/порт-gameplayfootball.md`): `var x := ...` не выводит
  тип из C#-Variant — объявлять тип явно; C#-дефолт-аргументы через мост не видны — звать полным
  списком; enum'ы через мост не гонять — GDScript-facing методы принимают/возвращают `int`-иды.
- **Check-скрипты** — конвенции репо: `extends SceneTree`, `_initialize()`, аккумулятор `ok`,
  построчные `print("CHECK FAIL: ...")`, финал `print("CHECK PASS" if ok else "CHECK FAIL")` +
  `quit(0 if ok else 1)`. Новый `.gd` требует `.uid`: после создания прогнать
  `& "<godot exe>" --path "<repo>" --headless --import` и закоммитить `.uid` вместе со скриптом.
- **Коммиты** — Conventional Commits, описания по-русски.
- **Вики не трогать до задачи 11** (там всё разом).
- **Модель по таблице CLAUDE.md:** задачи 2–8 — критичная математика порта (Fable 5 / Opus 5);
  задачи 1, 9, 10 — механика/сцена (Opus 5 / Sonnet 5); задача 11 — доки (Sonnet 5).
- **Скорости оригинала** (`gamedefines.hpp:18-27`): idle 0 / dribble 3.5 / walk 5.0 / sprint 8.0;
  переключатели 1.8 / 4.2 / 6.0. Корзины квантования клипа (`animation.cpp:825-828`): `<1.8→0`,
  `[1.8,4.2)→3.5`, `[4.2,6.0)→5.0`, `≥6.0→7.0` (да, 7.0, не 8.0 — так в оригинале).

## Швы фазы 1, закрываемые этим планом

| Шов (из финального ревью фазы 1) | Задача |
|---|---|
| 1. Нет write-API у `Gpf.Animation` (SetKeyFrame приватен, нет Clone) | 2 |
| 2. Касания и XML-переменные трансформируются вместе с клипом (Mirror/Rotate2D/Shift) | 2, 4 |
| 3. Нормализация `*direction`-тегов при загрузке (`animation.cpp:1157-1192`) | 4 |
| 4. Enumerator XML-тегов для копирования variableCache | 2 (Clone копирует `_variables` напрямую — отдельный enumerator не нужен) |
| 5. `position.Rotate2D(baseRot)` при `!noPos` в Apply | 9 |
| 6. Скорости/углы клипа вычисляются из root-трека и кэшируются | 3 |

Дополнительно обнаружено при подготовке плана: **`ConvertToStartFacingForwardIfIdle`**
(`animation.cpp:297-342`) вызывается оригиналом в конце `Animation::Load` (`:1196`) и в фазе 1 не
портирован. CrudeSelection (idle-ветка `animcollection.cpp:737-747`) предполагает, что клипы с
idle-входом уже развёрнуты «лицом вперёд» — без этого выбор клипа с места ломается. Закрывается в
задаче 4; **существующие ожидания `check_gpf_anim_meta.gd` для `ballcontrol/idle/000.anim` могут
измениться** — процедура пересчёта прописана в задаче 4 шаг 5.

**Что НЕ портируется в фазе 2 (мертво уже в оригинале или другая фаза):** `Slowdown` и
`SmoothPositions` (`animcollection.cpp:1035-1169`) — вызовы закомментированы в `_PrepareAnim`
(`:1186-1187`); хвост `AddExtraTouches` после `return animTouchFrame; // XDEBUG disable this`
(`:911`) — мёртвый код; `Invert`/`Hax`/`Save`; ветка «duplicate dribble anims» (`:453-471`) —
закомментирована; `omitLuxuryAnims`-фильтр сохраняем (в нашем датасете «luxury»-файлов нет — он
no-op, но порт дословный); реальный `CalculateFactualSpatialState` — фаза 3 (в лабе — lite-версия,
задача 10, помечена как упрощение, не порт).

---

### Задача 1: `Gpf.BluntMath` + `Gpf.Velo` — математический фундамент

**Files:**
- Create: `src/gpf/BluntMath.cs`
- Create: `src/gpf/Velo.cs`
- Modify: `src/gpf/QuatUtil.cs` (добавить `GetAngles`, `AngleAxis`)
- Test: `tests/check_gpf_bluntmath.gd`

**Interfaces:**
- Consumes: ничего (чистая математика).
- Produces (для задач 2–10):
  - `static class Gpf.BluntMath`: `float Curve(float source, float bias)`,
    `float NormalizedClamp(float v, float min, float max)`,
    `float ModulateIntoRange(float min, float max, float v)`, `int SignSide(float n)`,
    `bool IsOdd(int n)`, `float FixAngle(float angle)`, `float AtoF(string s)`, `int AtoI(string s)`,
    `Vector3 GetVectorFromString(string s)`, `string GetStringFromVector(Vector3 v)`,
    `Vector3 GetRotated2D(Vector3 v, float angle)`, `float GetAngle2D(Vector3 v)`,
    `float GetAngle2D(Vector3 v, Vector3 test)`, `Vector3 GetNormalized(Vector3 v, Vector3 fallback)`,
    `Vector3 Get2D(Vector3 v)`.
  - `static class Gpf.Velo` + константы: `Idle=0f, Dribble=3.5f, Walk=5.0f, Sprint=8.0f,
    IdleDribbleSwitch=1.8f, DribbleWalkSwitch=4.2f, WalkSprintSwitch=6.0f`; enum-иды скоростей —
    `int`: 0 idle / 1 dribble / 2 walk / 3 sprint (== `e_Velocity` через `GetVelocityID`, мост-дружелюбно);
    `float RangeVelocity(float)`, `float ClampVelocity(float)`, `float FloorVelocity(float)`,
    `float EnumToFloatVelocity(int id)`, `int FloatToEnumVelocity(float)`,
    `int GetVelocityID(int id, bool treatDribbleAsWalk = false)`.
  - `Gpf.QuatUtil`: `void GetAngles(Quaternion q, out float x, out float y, out float z)`,
    `Quaternion AngleAxis(float angle, Vector3 axis)`.

**Семантика — дословный порт:** `curve`/`NormalizedClamp`/`ModulateIntoRange`/`signSide`/`is_odd` —
`bluntmath.{hpp:46-49,cpp:34-39,61-67,94-100}`; `FixAngle` — `animcollection.hpp:50-55`
(`angle + 0.5π` → modulate в `[-π,π]`); `Rotate2D`/`GetAngle2D` — `vector3.hpp:276-333` (внимание:
безаргументный `GetAngle2D()` возвращает `[0,2π)`, двухаргументный — `[-π,π]` с **минусом** перед
`atan2`); `GetVectorFromString`/`GetStringFromVector` — `base/utils.cpp:213-237`; скорости —
`animcollection.hpp:57-104`, `utils.cpp:81-102`; `GetAngles` — `quaternion.cpp:197-226`
(**перестановка индексов**: `x=elements[0], y=elements[2], z=elements[1]` — портировать в точности,
НЕ заменять на Godot `GetEuler`); `AngleAxis` — `quaternion.cpp:284-296`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Математический фундамент порта: Blunted-математика, скорости, эйлеры.

func feq(a: float, b: float, eps := 1.0e-5) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-5) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var BM = load("res://src/gpf/BluntMath.cs")
	var V = load("res://src/gpf/Velo.cs")
	if BM == null or V == null:
		print("CHECK FAIL: BluntMath.cs/Velo.cs не найдены — сначала dotnet build")
		quit(1)
		return

	# ModulateIntoRange (bluntmath.cpp:94-100)
	if not feq(BM.ModulateIntoRange(-PI, PI, 5.5509), 5.5509 - TAU):
		print("CHECK FAIL: ModulateIntoRange 5.5509 → ", BM.ModulateIntoRange(-PI, PI, 5.5509)); ok = false
	if not feq(BM.ModulateIntoRange(-PI, PI, -4.0), -4.0 + TAU):
		print("CHECK FAIL: ModulateIntoRange -4"); ok = false

	# Curve (bluntmath.hpp:46-49): sin((x-0.5)*pi)*0.5+0.5 при bias=1
	if not feq(BM.Curve(0.5, 1.0), 0.5):
		print("CHECK FAIL: Curve(0.5,1)"); ok = false
	if not feq(BM.Curve(0.25, 1.0), sin(-0.25 * PI) * 0.5 + 0.5):
		print("CHECK FAIL: Curve(0.25,1)"); ok = false
	if not feq(BM.Curve(0.25, 0.0), 0.25):
		print("CHECK FAIL: Curve(0.25,0) — bias 0 == линейно"); ok = false

	# NormalizedClamp (bluntmath.cpp:34-39)
	if not feq(BM.NormalizedClamp(5.0, 0.0, 20.0), 0.25):
		print("CHECK FAIL: NormalizedClamp"); ok = false
	if not feq(BM.NormalizedClamp(-3.0, 0.0, 6.0), 0.0):
		print("CHECK FAIL: NormalizedClamp кламп снизу"); ok = false

	# SignSide (bluntmath.cpp:61-63): n >= 0 → 1
	if BM.SignSide(0.0) != 1 or BM.SignSide(-0.001) != -1:
		print("CHECK FAIL: SignSide"); ok = false

	# FixAngle (animcollection.hpp:50-55)
	if not feq(BM.FixAngle(0.0), 0.5 * PI):
		print("CHECK FAIL: FixAngle(0)"); ok = false
	if not feq(BM.FixAngle(0.75 * TAU), 0.5 * PI * -0.5, 1.0e-4):
		print("CHECK FAIL: FixAngle(1.5pi) → ", BM.FixAngle(0.75 * TAU)); ok = false

	# AtoF/AtoI — семантика atof/atoi: "" и мусор → 0 (не исключение)
	if not feq(BM.AtoF(""), 0.0) or not feq(BM.AtoF("0.5"), 0.5) or BM.AtoI("") != 0 or BM.AtoI("19") != 19:
		print("CHECK FAIL: AtoF/AtoI"); ok = false

	# GetVectorFromString (base/utils.cpp:222-237)
	if not vec_eq(BM.GetVectorFromString("0.5, -1, 0"), Vector3(0.5, -1, 0)):
		print("CHECK FAIL: GetVectorFromString"); ok = false
	if not vec_eq(BM.GetVectorFromString(""), Vector3.ZERO):
		print("CHECK FAIL: GetVectorFromString('')"); ok = false

	# GetRotated2D (vector3.hpp:325-333): (0,-1,0) на -45° → (sin,-cos)
	var r: Vector3 = BM.GetRotated2D(Vector3(0, -1, 0), -0.25 * PI)
	if not vec_eq(r, Vector3(-sin(0.25 * PI), -cos(0.25 * PI), 0.0)):
		print("CHECK FAIL: GetRotated2D → ", r); ok = false

	# GetAngle2D() безаргументный: [0, 2pi) (vector3.hpp:276-280)
	if not feq(BM.GetAngle2D(Vector3(-0.34, -0.378261, 0.0)), atan2(-0.378261, -0.34) + TAU, 1.0e-4):
		print("CHECK FAIL: GetAngle2D() one-arg"); ok = false
	# GetAngle2D(test): [-pi, pi], знак как в оригинале (vector3.hpp:283-289)
	if not feq(BM.GetAngle2D(Vector3(0, -1, 0), Vector3(-1, 0, 0)), -0.5 * PI, 1.0e-4):
		print("CHECK FAIL: GetAngle2D(a,b) знак → ", BM.GetAngle2D(Vector3(0, -1, 0), Vector3(-1, 0, 0))); ok = false

	# GetNormalized(fallback): нулевой вектор → fallback
	if not vec_eq(BM.GetNormalized(Vector3.ZERO, Vector3(0, -1, 0)), Vector3(0, -1, 0)):
		print("CHECK FAIL: GetNormalized fallback"); ok = false

	# Скорости (animcollection.hpp:57-104): корзины RangeVelocity
	if not feq(V.RangeVelocity(1.7), 0.0) or not feq(V.RangeVelocity(1.8), 3.5) \
		or not feq(V.RangeVelocity(4.2), 5.0) or not feq(V.RangeVelocity(6.0), 8.0):
		print("CHECK FAIL: RangeVelocity корзины"); ok = false
	if not feq(V.FloorVelocity(0.5), 3.5) or not feq(V.FloorVelocity(4.0), 5.0) or not feq(V.FloorVelocity(5.5), 8.0):
		print("CHECK FAIL: FloorVelocity"); ok = false
	if V.FloatToEnumVelocity(4.5) != 2 or V.FloatToEnumVelocity(0.0) != 0 or V.FloatToEnumVelocity(7.0) != 3:
		print("CHECK FAIL: FloatToEnumVelocity"); ok = false
	if not feq(V.EnumToFloatVelocity(1), 3.5):
		print("CHECK FAIL: EnumToFloatVelocity"); ok = false
	# GetVelocityID (utils.cpp:81-102): treatDribbleAsWalk схлопывает 2,3 → 1,2
	if V.GetVelocityID(3, false) != 3 or V.GetVelocityID(3, true) != 2 or V.GetVelocityID(1, true) != 1:
		print("CHECK FAIL: GetVelocityID"); ok = false

	# GetAngles (quaternion.cpp:197-226, перестановка x=el0,y=el2,z=el1):
	# body@24 клипа walk/045 → z == -pi/4 (выведено вручную из формулы оригинала)
	var QU = load("res://src/gpf/QuatUtil.cs")
	var angles: Vector3 = QU.GetAnglesVec(Quaternion(0.010774, -0.147878, -0.372312, 0.916187))
	if not feq(angles.z, -0.25 * PI, 1.0e-3):
		print("CHECK FAIL: GetAngles z → ", angles.z); ok = false
	# Чистый поворот вокруг Z на 0.3: z == 0.3
	var qz := Quaternion(Vector3(0, 0, 1), 0.3)
	if not feq(QU.GetAnglesVec(qz).z, 0.3, 1.0e-4):
		print("CHECK FAIL: GetAngles чистый Z"); ok = false

	# AngleAxis (quaternion.cpp:284-296) == конструктор Godot
	var q1: Quaternion = QU.AngleAxis(0.7, Vector3(0, 0, 1))
	if not feq(q1.z, sin(0.35), 1.0e-6) or not feq(q1.w, cos(0.35), 1.0e-6):
		print("CHECK FAIL: AngleAxis"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

Пояснение к статическим вызовам из GDScript: `load(...).Метод(...)` на C#-скрипте зовёт статические
методы класса — рабочий паттерн для `RefCounted`-обёрток. Чтобы это работало, `BluntMath`/`Velo`/
`QuatUtil` объявляются `public partial class ... : RefCounted` со статическими методами (не `static
class` — иначе Godot не сделает скрипт-обёртку). `GetAngles` с `out`-параметрами через мост не
зовётся — добавить обёртку `public static Vector3 GetAnglesVec(Quaternion q)`.

- [ ] **Шаг 2: убедиться, что тест падает**

Run:
```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_gpf_bluntmath.gd"
```
Expected: `CHECK FAIL: BluntMath.cs/Velo.cs не найдены...`, exit 1.

- [ ] **Шаг 3: реализация**

`src/gpf/BluntMath.cs`:

```csharp
using Godot;
using System;
using System.Globalization;

namespace Gpf
{
    // Порт математики Blunted2 (src/base/math/bluntmath.{hpp,cpp}, src/base/math/vector3.hpp,
    // src/base/utils.cpp) + FixAngle (animcollection.hpp:50-55). Всё в «их» осях: 2D = плоскость XY,
    // Z-вверх. RefCounted (не static class) — чтобы GDScript мог звать статические методы через load().
    public partial class BluntMath : RefCounted
    {
        // bluntmath.hpp:46-49
        public static float Curve(float source, float bias)
            => (Mathf.Sin((source - 0.5f) * Mathf.Pi) * 0.5f + 0.5f) * bias + source * (1.0f - bias);

        // bluntmath.cpp:34-39
        public static float NormalizedClamp(float v, float min, float max)
            => (Mathf.Clamp(v, min, max) - min) / (max - min);

        // bluntmath.cpp:94-100
        public static float ModulateIntoRange(float min, float max, float v)
        {
            float step = max - min;
            float newValue = v;
            while (newValue < min) newValue += step;
            while (newValue > max) newValue -= step;
            return newValue;
        }

        // bluntmath.cpp:61-63 (n >= 0 → 1)
        public static int SignSide(float n) => n >= 0 ? 1 : -1;

        // bluntmath.cpp:65-67
        public static bool IsOdd(int n) => (n & 1) != 0;

        // animcollection.hpp:50-55: «движковый» угол → футбольный (база «вниз по Y», не «вправо по X»)
        public static float FixAngle(float angle)
            => ModulateIntoRange(-Mathf.Pi, Mathf.Pi, angle + 0.5f * Mathf.Pi);

        // Семантика atof/atoi: пусто/мусор → 0, никаких исключений (в оригинале везде atof(GetVariable(...)))
        public static float AtoF(string s)
            => float.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out float v) ? v : 0f;

        public static int AtoI(string s)
            => int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out int v) ? v : 0;

        // base/utils.cpp:222-237 (пустая строка → (0,0,0); < 3 компонент — остаток нули)
        public static Vector3 GetVectorFromString(string s)
        {
            if (string.IsNullOrEmpty(s)) return Vector3.Zero;
            string[] tok = s.Split(',');
            var v = Vector3.Zero;
            if (tok.Length > 0) v.X = AtoF(tok[0].Trim());
            if (tok.Length > 1) v.Y = AtoF(tok[1].Trim());
            if (tok.Length > 2) v.Z = AtoF(tok[2].Trim());
            return v;
        }

        // base/utils.cpp:213-220
        public static string GetStringFromVector(Vector3 v)
            => string.Format(CultureInfo.InvariantCulture, "{0:F6}, {1:F6}, {2:F6}", v.X, v.Y, v.Z);

        // vector3.hpp:325-333 (Z не трогается)
        public static Vector3 GetRotated2D(Vector3 v, float angle)
        {
            float c = Mathf.Cos(angle), s = Mathf.Sin(angle);
            return new Vector3(v.X * c - v.Y * s, v.Y * c + v.X * s, v.Z);
        }

        // vector3.hpp:276-280: [0, 2pi)
        public static float GetAngle2D(Vector3 v)
        {
            float angle = Mathf.Atan2(v.Y, v.X);
            if (angle < 0) angle += 2f * Mathf.Pi;
            return angle;
        }

        // vector3.hpp:283-289: [-pi, pi], знак с минусом перед atan2 — портировать в точности
        public static float GetAngle2D(Vector3 v, Vector3 test)
        {
            float angle = -Mathf.Atan2(v.X * test.Y - v.Y * test.X, v.X * test.X + v.Y * test.Y);
            return ModulateIntoRange(-Mathf.Pi, Mathf.Pi, angle);
        }

        // Vector3::GetNormalized(fallback): нулевая длина → fallback
        public static Vector3 GetNormalized(Vector3 v, Vector3 fallback)
        {
            float len = v.Length();
            return len == 0f ? fallback : v / len;
        }

        // vector3.hpp:336-339
        public static Vector3 Get2D(Vector3 v) => new Vector3(v.X, v.Y, 0f);
    }
}
```

`src/gpf/Velo.cs`:

```csharp
using Godot;

namespace Gpf
{
    // Скорости GameplayFootball: константы gamedefines.hpp:18-27, конверсии animcollection.hpp:57-104,
    // GetVelocityID utils.cpp:81-102. Enum-иды скоростей гоняем как int (мост GDScript↔C#):
    // 0 idle / 1 dribble / 2 walk / 3 sprint.
    public partial class Velo : RefCounted
    {
        public const float Idle = 0.0f;               // gamedefines.hpp:18
        public const float Dribble = 3.5f;            // gamedefines.hpp:19
        public const float Walk = 5.0f;               // gamedefines.hpp:20
        public const float Sprint = 8.0f;             // gamedefines.hpp:21
        public const float IdleDribbleSwitch = 1.8f;  // gamedefines.hpp:25
        public const float DribbleWalkSwitch = 4.2f;  // gamedefines.hpp:26
        public const float WalkSprintSwitch = 6.0f;   // gamedefines.hpp:27

        public const int IdVelIdle = 0;
        public const int IdVelDribble = 1;
        public const int IdVelWalk = 2;
        public const int IdVelSprint = 3;

        // animcollection.hpp:57-63
        public static float RangeVelocity(float velocity)
        {
            float ret = Idle;
            if (velocity >= IdleDribbleSwitch && velocity < DribbleWalkSwitch) ret = Dribble;
            else if (velocity >= DribbleWalkSwitch && velocity < WalkSprintSwitch) ret = Walk;
            else if (velocity >= WalkSprintSwitch) ret = Sprint;
            return ret;
        }

        // animcollection.hpp:65-69
        public static float ClampVelocity(float velocity)
        {
            if (velocity < 0) return 0;
            if (velocity > Sprint) return Sprint;
            return velocity;
        }

        // animcollection.hpp:71-77 (да, ветвление оригинала именно такое)
        public static float FloorVelocity(float velocity)
        {
            float ret = Idle;
            if (velocity > 0 && velocity < Dribble) ret = Dribble;
            else if (velocity <= Walk) ret = Walk;
            else ret = Sprint;
            return ret;
        }

        // animcollection.hpp:79-95
        public static float EnumToFloatVelocity(int id) => id switch
        {
            IdVelIdle => Idle,
            IdVelDribble => Dribble,
            IdVelWalk => Walk,
            IdVelSprint => Sprint,
            _ => 0,
        };

        // animcollection.hpp:97-104
        public static int FloatToEnumVelocity(float velocity)
        {
            float ranged = RangeVelocity(velocity);
            if (ranged == Idle) return IdVelIdle;
            if (ranged == Dribble) return IdVelDribble;
            if (ranged == Walk) return IdVelWalk;
            if (ranged == Sprint) return IdVelSprint;
            return IdVelIdle;
        }

        // utils.cpp:81-102
        public static int GetVelocityID(int id, bool treatDribbleAsWalk = false)
        {
            int result = id is >= 0 and <= 3 ? id : 0;
            if (treatDribbleAsWalk && result > 1) result--;
            return result;
        }
    }
}
```

Добавить в `src/gpf/QuatUtil.cs` (внутрь класса; класс уже `RefCounted`-совместим — если в фазе 1 он
`static class`, поменять на `public partial class QuatUtil : RefCounted` со статическими членами):

```csharp
        // quaternion.cpp:197-226. ВНИМАНИЕ: перестановка индексов оригинала — x=elements[0],
        // y=elements[2], z=elements[1]. НЕ заменять на Godot GetEuler (другая конвенция).
        public static void GetAngles(Quaternion q, out float x, out float y, out float z)
        {
            float ex = q.X, ey = q.Z, ez = q.Y, ew = q.W; // el[0], el[2], el[1], el[3]
            float singularityTest = ex * ey + ez * ew;
            if (singularityTest > 0.49999f || singularityTest < -0.49999f)
            {
                if (singularityTest > 0) { z = 2f * Mathf.Atan2(ex, ez); y = Mathf.Pi * 0.5f; }
                else { z = -2f * Mathf.Atan2(ex, ez); y = -Mathf.Pi * 0.5f; }
                x = 0;
                return;
            }
            float sqx = ex * ex, sqy = ey * ey, sqz = ez * ez;
            z = Mathf.Atan2(2f * ey * ew - 2f * ex * ez, 1f - 2f * sqy - 2f * sqz);
            y = Mathf.Asin(2f * ex * ey + 2f * ez * ew);
            x = Mathf.Atan2(2f * ex * ew - 2f * ey * ez, 1f - 2f * sqx - 2f * sqz);
        }

        // Мост-обёртка для GDScript-тестов (out-параметры через мост не ходят).
        public static Vector3 GetAnglesVec(Quaternion q)
        {
            GetAngles(q, out float x, out float y, out float z);
            return new Vector3(x, y, z);
        }

        // quaternion.cpp:284-296 (эквивалент конструктора Godot Quaternion(axis, angle);
        // держим свою обёртку, чтобы код порта читался как оригинал).
        public static Quaternion AngleAxis(float angle, Vector3 axis)
        {
            float half = 0.5f * angle;
            float s = Mathf.Sin(half);
            return new Quaternion(s * axis.X, s * axis.Y, s * axis.Z, Mathf.Cos(half));
        }
```

- [ ] **Шаг 4: собрать и прогнать**

Run:
```powershell
dotnet build "C:\Users\User\Desktop\projects\OpenFootball\OpenFootball.sln"
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless --import
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" --headless -s "res://tests/check_gpf_bluntmath.gd"
```
Expected: сборка `0 Ошибок`; `CHECK PASS`, exit 0. Если `QuatUtil` менял объявление класса —
перегнать также `check_gpf_anim_sample.gd` (регресс фазы 1) → `CHECK PASS`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/BluntMath.cs src/gpf/Velo.cs src/gpf/QuatUtil.cs tests/check_gpf_bluntmath.gd tests/check_gpf_bluntmath.gd.uid
git commit -m "feat(gpf): BluntMath/Velo/эйлеры — математический фундамент фазы 2"
```

---

### Задача 2: write-API `Gpf.Animation` — Clone, SetKeyFrame, Shift, переменные, нога

**Files:**
- Modify: `src/gpf/Animation.cs`
- Test: `tests/check_gpf_anim_write.gd`

**Interfaces:**
- Consumes: `Gpf.BluntMath` (задача 1).
- Produces (для задач 3–8):
  - `public void SetKeyFrame(string nodeName, int frame, Quaternion orientation, Vector3 position)` — приватный становится публичным (порт `animation.cpp:122-158`; в конце — `DirtyCache()`).
  - `public Gpf.Animation Clone()` — глубокая копия (порт конструктора копии `animation.cpp:34-85`).
  - `public void Shift(int fromFrame, int offset)` — только `offset == ±1` (порт `animation.cpp:723-787`), **касания сдвигаются синхронно** (порт `footballanimationextension.cpp:19-47`).
  - `public void SetVariable(string name, string value)` (порт `animation.cpp:1340-1356` — у нас один словарь `_variables`, XMLTree-дублирование не нужно), `public void SetName(string name)`.
  - `public int GetCurrentFootId()` / `public void SetCurrentFootId(int id)` — 0 left / 1 right (== `e_Foot`, `animation.hpp:41-44`); дефолт **1 (right)** — `animation.cpp:29`.
  - `public void DirtyCache()` — в задаче 2 это заглушка-noop с TODO-комментарием, наполняется в задаче 3.
  - internal-доступ для `AnimCollection` (задачи 5–6): `internal SortedDictionary<int, KeyFrame> TrackKeys(int i)`, `internal void ClearTrackKeys(int i)`, `internal void GetInterpolatedValuesAt(int trackIndex, int frame, out Quaternion orientation, out Vector3 position)`, `internal SortedDictionary<int, Vector3> Touches => _touches`, `internal Dictionary<string, string> Variables => _variables`.

**Шов 4 (enumerator XML-тегов):** отдельный enumerator не нужен — `Clone()` копирует `_variables`
словарём напрямую (аналог копии `variableCache` в `animation.cpp:49-55`).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Write-API клипа: Clone (глубина), SetKeyFrame (рост frameCount), Shift (±1, синхрон касаний),
# SetVariable/SetName, CurrentFoot.

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	var src = AnimScript.new()
	src.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim")
	var src_frames: int = src.GetFrameCount()
	var src_touch_frame: int = src.GetTouchFrame(0)
	var src_touch_pos: Vector3 = src.GetTouchPosition(0)

	# Clone: та же форма...
	var copy = src.Clone()
	if copy.GetFrameCount() != src_frames or copy.GetTrackCount() != src.GetTrackCount():
		print("CHECK FAIL: Clone форма"); ok = false
	if copy.GetTouchCount() != src.GetTouchCount() or copy.GetTouchFrame(0) != src_touch_frame:
		print("CHECK FAIL: Clone касания"); ok = false
	if copy.GetAnimType() != src.GetAnimType() or copy.GetName() != src.GetName():
		print("CHECK FAIL: Clone переменные/имя"); ok = false
	if copy.GetCurrentFootId() != src.GetCurrentFootId():
		print("CHECK FAIL: Clone нога"); ok = false

	# ...но глубокая: правка копии не трогает оригинал
	copy.SetKeyFrame("player", 200, Quaternion.IDENTITY, Vector3(9, 9, 9))
	copy.SetVariable("type", "hacked")
	if src.GetFrameCount() != src_frames:
		print("CHECK FAIL: Clone мелкий — frameCount оригинала изменился"); ok = false
	if src.GetAnimType() == "hacked":
		print("CHECK FAIL: Clone мелкий — variables общие"); ok = false
	if copy.GetFrameCount() != 201:
		print("CHECK FAIL: SetKeyFrame не растит frameCount (animation.cpp:123) → ", copy.GetFrameCount()); ok = false

	# SetKeyFrame поверх существующего ключа — замена, не дубликат
	var probe = AnimScript.new()
	probe.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	probe.SetKeyFrame("player", 0, Quaternion.IDENTITY, Vector3(1, 2, -0.09))
	var p0: Vector3 = probe.GetKeyPosition("player", 0)
	if not vec_eq(p0, Vector3(1, 2, -0.09)):
		print("CHECK FAIL: SetKeyFrame замена → ", p0); ok = false
	var frames_before: Array = probe.GetKeyFrames("player")

	# Shift +1 от кадра 12: ключи >= 12 сдвинуты, frameCount+1, ключ 0 на месте
	var sh = src.Clone()
	var t_before: int = sh.GetTouchFrame(0)
	sh.Shift(1, 1)
	if sh.GetFrameCount() != src_frames + 1:
		print("CHECK FAIL: Shift +1 frameCount → ", sh.GetFrameCount()); ok = false
	if sh.GetTouchFrame(0) != t_before + 1:
		print("CHECK FAIL: Shift не сдвинул касание (шов 2) → ", sh.GetTouchFrame(0)); ok = false
	if not vec_eq(sh.GetTouchPosition(0), src_touch_pos):
		print("CHECK FAIL: Shift изменил позицию касания"); ok = false
	# Shift -1 обратно: возврат к исходной форме
	sh.Shift(1, -1)
	if sh.GetFrameCount() != src_frames or sh.GetTouchFrame(0) != t_before:
		print("CHECK FAIL: Shift -1 не вернул форму"); ok = false

	# SetVariable/SetName/нога
	var a = AnimScript.new()
	a.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	a.SetVariable("priority", "1")
	if a.GetVariable("priority") != "1":
		print("CHECK FAIL: SetVariable новый тег"); ok = false
	a.SetName("autogen test")
	if a.GetName() != "autogen test":
		print("CHECK FAIL: SetName"); ok = false
	if a.GetCurrentFootId() != 1:
		print("CHECK FAIL: дефолтная нога должна быть right=1 (animation.cpp:29)"); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает** (тот же шаблон запуска; Expected: скрипт-ошибка — методов `Clone`/`Shift`/... нет)

- [ ] **Шаг 3: реализация** — в `src/gpf/Animation.cs`:

1. Сделать существующий `SetKeyFrame` публичным и добавить в его конец `DirtyCache();`.
2. Добавить поле ноги и методы:

```csharp
        // e_Foot (animation.hpp:41-44): 0 left / 1 right. Дефолт right (animation.cpp:29):
        // «все клипы начинают движение с правой ноги, если не отзеркалены».
        private int _currentFoot = 1;
        public int GetCurrentFootId() => _currentFoot;
        public void SetCurrentFootId(int id) => _currentFoot = id;

        public void SetName(string name) => _name = name;

        // Порт SetVariable (animation.cpp:1340-1356): у нас один словарь вместо XMLTree+variableCache.
        public void SetVariable(string name, string value) => _variables[name] = value;

        // Кэш дескрипторов (скорости/углы) появляется в следующей задаче; пока noop.
        public void DirtyCache() { }
```

3. `Clone` (порт конструктора копии `animation.cpp:34-85`; extensions у нас интегрированы —
   `_touches` копируются глубоко, что строже shallow-копии оригинала: безопаснее для Mirror):

```csharp
        public Animation Clone()
        {
            var dst = new Animation { _name = _name, _frameCount = _frameCount, _currentFoot = _currentFoot };
            foreach (var track in _tracks)
            {
                var t = new NodeAnimation { NodeName = track.NodeName };
                foreach (var kv in track.Keys) t.Keys[kv.Key] = kv.Value; // KeyFrame — struct, копия по значению
                dst._tracks.Add(t);
            }
            foreach (var kv in _touches) dst._touches[kv.Key] = kv.Value;
            foreach (var kv in _variables) dst._variables[kv.Key] = kv.Value; // шов 4: enumerator не нужен
            return dst;
        }
```

4. `Shift` (порт `animation.cpp:723-787` + синхрон касаний `footballanimationextension.cpp:19-47`):

```csharp
        // Порт Animation::Shift (animation.cpp:723-787). Поддержан только offset ±1 — как в оригинале
        // («todo: offset does not yet work» для остальных). Касания сдвигаются синхронно (шов 2;
        // extension->Shift, animation.cpp:782-786 + footballanimationextension.cpp:19-47).
        public void Shift(int fromFrame, int offset)
        {
            if (offset == 1)
            {
                bool somethingShifted = false;
                foreach (var track in _tracks)
                {
                    var newKeys = new SortedDictionary<int, KeyFrame>();
                    foreach (var kv in track.Keys)
                    {
                        int frameNum = kv.Key;
                        if (kv.Key >= fromFrame) { frameNum++; somethingShifted = true; }
                        newKeys[frameNum] = kv.Value;
                    }
                    track.Keys.Clear();
                    foreach (var kv in newKeys) track.Keys[kv.Key] = kv.Value;
                }
                if (somethingShifted) { _frameCount++; DirtyCache(); }
            }
            if (offset == -1)
            {
                bool somethingShifted = false;
                foreach (var track in _tracks)
                {
                    var newKeys = new SortedDictionary<int, KeyFrame>();
                    foreach (var kv in track.Keys)
                    {
                        int frameNum = kv.Key;
                        if (kv.Key != fromFrame) // ключ на fromFrame выбрасывается (animation.cpp:764)
                        {
                            if (kv.Key > fromFrame) { frameNum--; somethingShifted = true; }
                            newKeys[frameNum] = kv.Value;
                        }
                    }
                    track.Keys.Clear();
                    foreach (var kv in newKeys) track.Keys[kv.Key] = kv.Value;
                }
                if (somethingShifted) { _frameCount--; DirtyCache(); }
            }

            // Касания — те же правила сдвига (footballanimationextension.cpp:19-47)
            var newTouches = new SortedDictionary<int, Vector3>();
            foreach (var kv in _touches)
            {
                int frameNum = kv.Key;
                if (offset == 1) { if (kv.Key >= fromFrame) frameNum++; newTouches[frameNum] = kv.Value; }
                else if (offset == -1)
                {
                    if (kv.Key == fromFrame) continue;
                    if (kv.Key > fromFrame) frameNum--;
                    newTouches[frameNum] = kv.Value;
                }
                else newTouches[frameNum] = kv.Value;
            }
            _touches.Clear();
            foreach (var kv in newTouches) _touches[kv.Key] = kv.Value;
        }
```

5. Internal-доступ для `AnimCollection`/генератора (внутри одной сборки):

```csharp
        internal SortedDictionary<int, KeyFrame> TrackKeys(int i) => _tracks[i].Keys;
        internal void ClearTrackKeys(int i) => _tracks[i].Keys.Clear();
        internal SortedDictionary<int, Vector3> Touches => _touches;
        internal Dictionary<string, string> Variables => _variables;

        internal void GetInterpolatedValuesAt(int trackIndex, int frame,
                                              out Quaternion orientation, out Vector3 position)
            => GetInterpolatedValues(_tracks[trackIndex].Keys, frame, out orientation, out position);
```

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build`, `--headless --import`, `check_gpf_anim_write.gd` → `CHECK PASS`; регресс фазы 1: `check_gpf_anim_parse.gd`, `check_gpf_anim_sample.gd`, `check_gpf_anim_meta.gd` → `CHECK PASS`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/Animation.cs tests/check_gpf_anim_write.gd tests/check_gpf_anim_write.gd.uid
git commit -m "feat(gpf): write-API Gpf.Animation — Clone/SetKeyFrame/Shift/переменные/нога"
```

---

### Задача 3: дескрипторы клипа — кэш скоростей, углов, направлений

**Files:**
- Modify: `src/gpf/Animation.cs`
- Test: `tests/check_gpf_anim_descriptors.gd`

**Interfaces:**
- Consumes: `BluntMath`, `Velo`, `QuatUtil.GetAngles` (задача 1), write-API (задача 2).
- Produces (для задач 4–8, 10):
  - `public Vector3 GetTranslation()` — `animation.cpp:789-797`
  - `public Vector3 GetIncomingMovement()` — `:799-814`
  - `public float GetIncomingVelocity()` — `:816-835` (квантование корзин!)
  - `public Vector3 GetOutgoingMovement()` — `:837-853`
  - `public Vector3 GetRangedOutgoingMovement()` — `:855-867`
  - `public Vector3 GetOutgoingDirection()` — `:869-875`
  - `public Vector3 GetIncomingBodyDirection()` — `:877-883`
  - `public Vector3 GetOutgoingBodyDirection()` — `:885-891`
  - `public float GetOutgoingVelocity()` — `:893-912`
  - `public float GetOutgoingAngle()` — `:914-962`
  - `public float GetIncomingBodyAngle()` — `:964-991`
  - `public float GetOutgoingBodyAngle()` — `:993-1027`
  - `public int GetOutgoingFootId()` — `:1029-1052` (тег `steps`)
  - `DirtyCache()` наполняется: сбрасывает все dirty-флаги (`animation.cpp:92-105`).

**Семантика (шов 6, порт дословно):** скорость/движение — дельта **двух первых** (incoming) или
**двух последних** (outgoing) ключей root-трека `×100 / разность кадров`, Z занулён; квантование
`<1.8→0 / [1.8,4.2)→3.5 / [4.2,6.0)→5.0 / ≥6.0→7.0`. `GetOutgoingAngle`: при outgoing velocity
≥ 1.8 — `FixAngle(GetAngle2D(последний вектор движения))` + разруливание ±180° по знаку z-эйлера
последнего ключа **body-трека** (`:925-933`, кламп в `±0.99π`); иначе — z-эйлер последнего ключа
body. `GetIncomingBodyAngle` — z-эйлер **первого** ключа body. `GetOutgoingBodyAngle` — z-эйлер
последнего ключа body **минус `GetOutgoingAngle()`**, только при outgoing velocity ≥ 1.8, иначе 0.
Body-трек — `nodeAnimations.at(1)`, у нас `_tracks[1]` (порядок треков фиксирован `TrackOrder`).
Все геттеры ленивы через dirty-флаги; `DirtyCache` инвалидирует всё (вызывается из `SetKeyFrame`,
`Shift`, `Mirror`, `ConvertToStartFacingForwardIfIdle`, `LoadFromFile` в начале).

**Опорные значения для теста** (выведены вручную из ключей `movement/walk/045.anim`, известных из
тестов фазы 1: player@0 = `(0,0,-0.09)`, @12 = `(-0.30,-0.461739,-0.05)`, @24 = `(-0.64,-0.84,-0.08)`;
body@24 = `(0.010774,-0.147878,-0.372312,0.916187)` → z-эйлер −π/4):
incoming movement = `(-2.5, -3.84783, 0)` (длина 4.589 → walk 5.0); outgoing movement =
`(-2.83333, -3.15218, 0)` (длина 4.238 → walk 5.0); outgoing angle = `FixAngle(atan2(-0.378261,
-0.34) + 2π)` ≈ **−0.73232**; outgoing body angle ≈ `−π/4 − (−0.73232)` ≈ **−0.05308**;
translation = `(-0.64, -0.84, 0)`.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Дескрипторы клипа: скорости (квантование), углы, направления, нога — walk/045 как эталон.

func feq(a: float, b: float, eps := 1.0e-3) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-3) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func _initialize() -> void:
	var ok := true
	var anim = load("res://src/gpf/Animation.cs").new()
	anim.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")

	if not feq(anim.GetIncomingVelocity(), 5.0):
		print("CHECK FAIL: incoming velocity → ", anim.GetIncomingVelocity()); ok = false
	if not feq(anim.GetOutgoingVelocity(), 5.0):
		print("CHECK FAIL: outgoing velocity → ", anim.GetOutgoingVelocity()); ok = false
	if not vec_eq(anim.GetIncomingMovement(), Vector3(-2.5, -3.84783, 0.0)):
		print("CHECK FAIL: incoming movement → ", anim.GetIncomingMovement()); ok = false
	if not vec_eq(anim.GetOutgoingMovement(), Vector3(-2.83333, -3.15218, 0.0)):
		print("CHECK FAIL: outgoing movement → ", anim.GetOutgoingMovement()); ok = false
	if not vec_eq(anim.GetTranslation(), Vector3(-0.64, -0.84, 0.0)):
		print("CHECK FAIL: translation → ", anim.GetTranslation()); ok = false
	if not feq(anim.GetOutgoingAngle(), -0.73232):
		print("CHECK FAIL: outgoing angle → ", anim.GetOutgoingAngle()); ok = false
	if not feq(anim.GetOutgoingBodyAngle(), -0.05308, 2.0e-3):
		print("CHECK FAIL: outgoing body angle → ", anim.GetOutgoingBodyAngle()); ok = false
	# Клип «walk 45» стартует лицом вперёд: |incoming body angle| мал.
	if absf(anim.GetIncomingBodyAngle()) > 0.2:
		print("CHECK FAIL: incoming body angle слишком велик → ", anim.GetIncomingBodyAngle()); ok = false
	# Направления — производные от углов
	var od: Vector3 = anim.GetOutgoingDirection()
	if not vec_eq(od, Vector3(sin(-0.73232), -cos(-0.73232), 0.0)):
		print("CHECK FAIL: outgoing direction → ", od); ok = false
	var rom: Vector3 = anim.GetRangedOutgoingMovement()
	if not feq(rom.length(), 5.0):
		print("CHECK FAIL: ranged outgoing movement len → ", rom.length()); ok = false

	# Кэш инвалидируется write-API: подмена последнего ключа root меняет outgoing
	var w = load("res://src/gpf/Animation.cs").new()
	w.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	w.GetOutgoingVelocity() # прогреть кэш
	w.SetKeyFrame("player", 24, Quaternion.IDENTITY, Vector3(-0.30, -1.42, -0.08))
	# теперь дельта 12→24 = (0,-0.958)/12*100 → длина 7.98 → корзина 7.0
	if not feq(w.GetOutgoingVelocity(), 7.0):
		print("CHECK FAIL: DirtyCache после SetKeyFrame → ", w.GetOutgoingVelocity()); ok = false

	# GetOutgoingFootId (animation.cpp:1029-1052): дефолт right=1, steps нет → нечётный 1 шаг → left=0
	var f = load("res://src/gpf/Animation.cs").new()
	f.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	var steps_var: String = f.GetVariable("steps")
	var expected_foot: int
	var steps_n: int = 1 if steps_var == "" else int(steps_var)
	if steps_n % 2 == 1:
		expected_foot = 0 # от right шагнули нечётно → left
	else:
		expected_foot = 1
	if f.GetOutgoingFootId() != expected_foot:
		print("CHECK FAIL: outgoing foot → ", f.GetOutgoingFootId(), " (steps='", steps_var, "')"); ok = false

	# idle-клип: outgoing velocity 0 → outgoing body angle обязан быть 0 (animation.cpp:1020-1022)
	var idle = load("res://src/gpf/Animation.cs").new()
	idle.LoadFromFile("res://assets/gpf/animations/movement/idle/000.anim")
	if not feq(idle.GetOutgoingVelocity(), 0.0):
		print("CHECK FAIL: idle outgoing velocity → ", idle.GetOutgoingVelocity()); ok = false
	if not feq(idle.GetOutgoingBodyAngle(), 0.0):
		print("CHECK FAIL: idle outgoing body angle → ", idle.GetOutgoingBodyAngle()); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

Примечание: если `movement/idle/000.anim` не существует под таким путём — найти реальный idle-клип
(`Get-ChildItem -Recurse "assets\gpf\animations\movement"`), подставить путь; инвариант тот же.

- [ ] **Шаг 2: убедиться, что тест падает** (Expected: нет методов-геттеров)

- [ ] **Шаг 3: реализация** — в `src/gpf/Animation.cs` добавить кэш-поля и геттеры. Каркас кэша:

```csharp
        // Кэш дескрипторов (animation.hpp:146-169). Ленивая инвалидация DirtyCache (animation.cpp:92-105).
        private bool _cTranslationDirty = true;      private Vector3 _cTranslation;
        private bool _cIncomingMovementDirty = true; private Vector3 _cIncomingMovement;
        private bool _cIncomingVelocityDirty = true; private float _cIncomingVelocity;
        private bool _cOutgoingDirectionDirty = true; private Vector3 _cOutgoingDirection;
        private bool _cOutgoingMovementDirty = true; private Vector3 _cOutgoingMovement;
        private bool _cRangedOutgoingMovementDirty = true; private Vector3 _cRangedOutgoingMovement;
        private bool _cOutgoingVelocityDirty = true; private float _cOutgoingVelocity;
        private bool _cAngleDirty = true;            private float _cAngle;
        private bool _cIncomingBodyAngleDirty = true; private float _cIncomingBodyAngle;
        private bool _cOutgoingBodyAngleDirty = true; private float _cOutgoingBodyAngle;
        private bool _cIncomingBodyDirectionDirty = true; private Vector3 _cIncomingBodyDirection;
        private bool _cOutgoingBodyDirectionDirty = true; private Vector3 _cOutgoingBodyDirection;
```

`DirtyCache()` ставит все 12 флагов в `true` (заменить noop задачи 2). Вспомогалки по root/body
трекам (root = `_tracks[0]`, body = `_tracks[1]`):

```csharp
        private (int frame, KeyFrame key) RootKeyAt(int position, bool fromEnd)
        {
            // «первый», «второй», «последний», «предпоследний» ключ root-трека —
            // аналог итераторной арифметики animation.cpp:789-912
            var keys = _tracks[0].Keys;
            int i = 0, target = fromEnd ? keys.Count - 1 - position : position;
            foreach (var kv in keys)
            {
                if (i == target) return (kv.Key, kv.Value);
                i++;
            }
            return (0, default);
        }
```

Геттеры — дословно, каждый со ссылкой на строки. Образец двух ключевых (остальные по той же схеме
из C++, приведённой в секции «Семантика»):

```csharp
        // animation.cpp:816-835
        public float GetIncomingVelocity()
        {
            if (_cIncomingVelocityDirty)
            {
                if (_tracks[0].Keys.Count > 1)
                {
                    var (f0, k0) = RootKeyAt(0, false);
                    var (f1, k1) = RootKeyAt(1, false);
                    Vector3 result = (k1.Position - k0.Position) / (f1 - f0 * 1.0f) * 100f;
                    result.Z = 0;
                    _cIncomingVelocity = result.Length();
                    if (_cIncomingVelocity < 1.8f) _cIncomingVelocity = 0f;                                  // animation.cpp:825
                    else if (_cIncomingVelocity >= 1.8f && _cIncomingVelocity < 4.2f) _cIncomingVelocity = 3.5f;
                    else if (_cIncomingVelocity >= 4.2f && _cIncomingVelocity < 6.0f) _cIncomingVelocity = 5.0f;
                    else if (_cIncomingVelocity >= 6.0f) _cIncomingVelocity = 7.0f;
                }
                else _cIncomingVelocity = 0;
                _cIncomingVelocityDirty = false;
            }
            return _cIncomingVelocity;
        }

        // animation.cpp:914-962
        public float GetOutgoingAngle()
        {
            if (_cAngleDirty || _cOutgoingVelocityDirty)
            {
                if (GetOutgoingVelocity() >= 1.8f)
                {
                    var (fl, kl) = RootKeyAt(0, true);
                    var (fp, kp) = RootKeyAt(1, true);
                    Vector3 lastMove = kl.Position - kp.Position;
                    _cAngle = BluntMath.FixAngle(BluntMath.GetAngle2D(lastMove));

                    // ±180°: знак берём из z-эйлера последнего ключа body (animation.cpp:925-933)
                    if (_cAngle < -0.95f * Mathf.Pi || _cAngle > 0.95f * Mathf.Pi)
                    {
                        QuatUtil.GetAngles(LastBodyKey().Orientation, out _, out _, out float z);
                        if (BluntMath.SignSide(_cAngle) != BluntMath.SignSide(z))
                            _cAngle = Mathf.Pi * 0.99f * BluntMath.SignSide(z);
                        else
                            _cAngle = Mathf.Clamp(_cAngle, -0.99f * Mathf.Pi, 0.99f * Mathf.Pi);
                    }
                }
                else
                {
                    if (_tracks[1].Keys.Count > 0)
                    {
                        QuatUtil.GetAngles(LastBodyKey().Orientation, out _, out _, out float z);
                        _cAngle = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, z);
                    }
                    else _cAngle = 0;
                }
                _cAngleDirty = false;
            }
            return _cAngle;
        }
```

где `LastBodyKey()`/`FirstBodyKey()` — приватные вспомогалки по `_tracks[1].Keys` (последний/первый
`KeyFrame`). Остальные геттеры (перечислены в Produces) переносятся с тех же строк 1:1; направления:

```csharp
        // animation.cpp:869-891
        public Vector3 GetOutgoingDirection()
            => CacheVec(ref _cOutgoingDirectionDirty, ref _cOutgoingDirection,
                () => BluntMath.GetRotated2D(new Vector3(0, -1, 0), GetOutgoingAngle()));
```

(допустим и развёрнутый if-стиль без `CacheVec` — важно сохранить формулы и зависимость от
dirty-флагов, `_cOutgoingDirectionDirty || _cAngleDirty` как в оригинале). `GetOutgoingFootId` —
порт `animation.cpp:1029-1052` через `BluntMath.AtoI(GetVariable("steps"))` (пусто → 1 шаг),
`BluntMath.IsOdd`.

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build`, `--import`, `check_gpf_anim_descriptors.gd` → `CHECK PASS`; регресс: parse/sample/meta/write → `CHECK PASS`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/Animation.cs tests/check_gpf_anim_descriptors.gd tests/check_gpf_anim_descriptors.gd.uid
git commit -m "feat(gpf): дескрипторы клипа — кэш скоростей/углов/направлений (шов 6)"
```

---

### Задача 4: Mirror + ConvertToStartFacingForwardIfIdle + нормализация direction-тегов

**Files:**
- Modify: `src/gpf/Animation.cs`
- Test: `tests/check_gpf_anim_mirror.gd`
- Modify (возможно): `tests/check_gpf_anim_meta.gd` (пересчёт ожиданий, см. шаг 5)

**Interfaces:**
- Consumes: задачи 1–3.
- Produces (для задач 5–8):
  - `public void Mirror()` — порт `animation.cpp:1246-1313`: имя `+"_mirror"`, флип ноги, swap
    left↔right треков, негация X позиции root и Y/Z-компонент кватернионов, **зеркало касаний**
    (X-негация, `footballanimationextension.cpp:59-67`), swap `left`/`right` в **значениях** всех
    переменных, негация X у `balldirection`/`incomingballdirection`/`bumpdirection`, `DirtyCache()`.
  - `LoadFromFile` дополнен (порядок как в `Animation::Load`): нормализация direction-тегов
    (`animation.cpp:1157-1179`, шов 3) → затем `ConvertToStartFacingForwardIfIdle()`
    (`animation.cpp:297-342`, вызов `:1196`).

**Семантика `ConvertToStartFacingForwardIfIdle`:** только для клипов с incoming velocity < 1.8;
поворачивает позиции root-трека на `-incomingBodyAngle` (Rotate2D), домножает ориентации body-трека
слева на `AngleAxis(-incomingBodyAngle, (0,0,1))`, поворачивает **касания** на тот же угол (шов 2;
`extension->Rotate2D`, `:327-331`) и три direction-тега (`:333-339`), в конце `DirtyCache()`.
После этого у любого idle-клипа `GetIncomingBodyAngle() ≈ 0` — на этом стоит idle-ветка
CrudeSelection (`animcollection.cpp:737-747`).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Mirror (инволюция, нога, касания, переменные) + ConvertToStartFacingForwardIfIdle +
# нормализация direction-тегов при загрузке.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func vec_eq(a: Vector3, b: Vector3, eps := 1.0e-4) -> bool:
	return absf(a.x - b.x) < eps and absf(a.y - b.y) < eps and absf(a.z - b.z) < eps

func quat_close(a: Quaternion, b: Quaternion, eps := 1.0e-4) -> bool:
	var d1 := absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z) + absf(a.w - b.w)
	var d2 := absf(a.x + b.x) + absf(a.y + b.y) + absf(a.z + b.z) + absf(a.w + b.w)
	return minf(d1, d2) < eps

func _initialize() -> void:
	var ok := true
	var AnimScript := load("res://src/gpf/Animation.cs")

	# --- Mirror: базовые свойства на walk/045 ---
	var a = AnimScript.new()
	a.LoadFromFile("res://assets/gpf/animations/movement/walk/045.anim")
	var orig_root24: Vector3 = a.GetKeyPosition("player", 24)
	var orig_la_rot: Quaternion = a.GetKeyRotation("left_ankle", 0)
	var orig_ra_rot: Quaternion = a.GetKeyRotation("right_ankle", 0)
	var orig_angle: float = a.GetOutgoingAngle()

	var m = a.Clone()
	m.Mirror()
	if not m.GetName().ends_with("_mirror"):
		print("CHECK FAIL: имя без _mirror → ", m.GetName()); ok = false
	if m.GetCurrentFootId() != 0:
		print("CHECK FAIL: Mirror не флипнул ногу (right→left)"); ok = false
	# X позиции root отражён
	if not vec_eq(m.GetKeyPosition("player", 24), Vector3(-orig_root24.x, orig_root24.y, orig_root24.z)):
		print("CHECK FAIL: root X не отражён → ", m.GetKeyPosition("player", 24)); ok = false
	# Треки left/right поменялись местами (с негацией Y/Z кватерниона)
	var expected_la := Quaternion(orig_ra_rot.x, -orig_ra_rot.y, -orig_ra_rot.z, orig_ra_rot.w)
	if not quat_close(m.GetKeyRotation("left_ankle", 0), expected_la):
		print("CHECK FAIL: left_ankle после Mirror ≠ отражённый right_ankle"); ok = false
	# Дескрипторы пересчитаны: угол сменил знак
	if not feq(m.GetOutgoingAngle(), -orig_angle, 5.0e-3):
		print("CHECK FAIL: outgoing angle после Mirror → ", m.GetOutgoingAngle(), " ожидался ", -orig_angle); ok = false

	# Инволюция: Mirror дважды == исходник (позиции, ротации, нога, имя не проверяем)
	var mm = a.Clone()
	mm.Mirror()
	mm.Mirror()
	if not vec_eq(mm.GetKeyPosition("player", 24), orig_root24):
		print("CHECK FAIL: Mirror² root"); ok = false
	if not quat_close(mm.GetKeyRotation("left_ankle", 0), orig_la_rot):
		print("CHECK FAIL: Mirror² left_ankle"); ok = false
	if mm.GetCurrentFootId() != 1:
		print("CHECK FAIL: Mirror² нога"); ok = false

	# --- Mirror: касания и переменные на ballcontrol/idle/000 ---
	var bc = AnimScript.new()
	bc.LoadFromFile("res://assets/gpf/animations/ballcontrol/idle/000.anim")
	var t_pos: Vector3 = bc.GetTouchPosition(0)
	var t_frame: int = bc.GetTouchFrame(0)
	var bd_raw: String = bc.GetVariable("balldirection")
	var touchfoot_raw: String = bc.GetVariable("touchfoot")
	var bm = bc.Clone()
	bm.Mirror()
	if bm.GetTouchFrame(0) != t_frame:
		print("CHECK FAIL: Mirror сдвинул кадр касания"); ok = false
	if not vec_eq(bm.GetTouchPosition(0), Vector3(-t_pos.x, t_pos.y, t_pos.z)):
		print("CHECK FAIL: Mirror касание X → ", bm.GetTouchPosition(0)); ok = false
	# balldirection: X-негация (animation.cpp:1305-1310)
	if bd_raw != "":
		var bd := load("res://src/gpf/BluntMath.cs").GetVectorFromString(bd_raw)
		var bdm := load("res://src/gpf/BluntMath.cs").GetVectorFromString(bm.GetVariable("balldirection"))
		if not vec_eq(bdm, Vector3(-bd.x, bd.y, bd.z)):
			print("CHECK FAIL: Mirror balldirection → ", bdm); ok = false
	# touchfoot left↔right (animation.cpp:1294-1303)
	if touchfoot_raw == "left" and bm.GetVariable("touchfoot") != "right":
		print("CHECK FAIL: Mirror touchfoot left→right"); ok = false
	if touchfoot_raw == "right" and bm.GetVariable("touchfoot") != "left":
		print("CHECK FAIL: Mirror touchfoot right→left"); ok = false

	# --- Нормализация direction-тегов при загрузке (шов 3): длина 1 либо тег пуст ---
	if bd_raw != "":
		var bd2 := load("res://src/gpf/BluntMath.cs").GetVectorFromString(bd_raw)
		if absf(bd2.length() - 1.0) > 1.0e-3:
			print("CHECK FAIL: balldirection не нормализован при загрузке → len ", bd2.length()); ok = false

	# --- ConvertToStartFacingForwardIfIdle: все idle-клипы стартуют лицом вперёд ---
	# Скан всего корпуса: у каждого клипа с GetIncomingVelocity() < 1.8 угол корпуса на входе ≈ 0.
	var paths: Array[String] = []
	_scan("res://assets/gpf/animations", paths)
	var checked := 0
	for p in paths:
		if p.contains("/templates/"):
			continue
		var c = AnimScript.new()
		if not c.LoadFromFile(p):
			continue
		if c.GetIncomingVelocity() < 1.8:
			checked += 1
			if absf(c.GetIncomingBodyAngle()) > 0.05:
				print("CHECK FAIL: idle-клип не развёрнут вперёд: ", p, " angle=", c.GetIncomingBodyAngle())
				ok = false
	if checked < 20:
		print("CHECK FAIL: подозрительно мало idle-клипов в скане: ", checked); ok = false

	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)

func _scan(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var path := dir + "/" + f
		if d.current_is_dir():
			if not f.begins_with("."): _scan(path, out)
		elif f.ends_with(".anim"):
			out.append(path)
		f = d.get_next()
	d.list_dir_end()
```

- [ ] **Шаг 2: убедиться, что тест падает** (Expected: нет метода `Mirror`; полный скан тоже упадёт — конверсия не подключена)

- [ ] **Шаг 3: реализация** — в `src/gpf/Animation.cs`:

`Mirror` (порт `animation.cpp:1246-1313`):

```csharp
        // Порт Animation::Mirror (animation.cpp:1246-1313) + зеркало касаний
        // (footballanimationextension.cpp:59-67) — extensions у нас интегрированы (шов 2).
        public void Mirror()
        {
            _name += "_mirror";
            _currentFoot = _currentFoot == 1 ? 0 : 1;

            // swap треков left* ↔ right* (animation.cpp:1250-1269)
            for (int i = 0; i < _tracks.Count; i++)
            {
                if (!_tracks[i].NodeName.StartsWith("left")) continue;
                string needle = "right" + _tracks[i].NodeName.Substring(4);
                for (int j = 0; j < _tracks.Count; j++)
                {
                    if (_tracks[j].NodeName != needle) continue;
                    (_tracks[i].Keys, _tracks[j].Keys) = (_tracks[j].Keys, _tracks[i].Keys);
                    break;
                }
            }

            // негация: root X, у джойнтов — Y/Z кватерниона (animation.cpp:1271-1284)
            for (int i = 0; i < _tracks.Count; i++)
            {
                var newKeys = new SortedDictionary<int, KeyFrame>();
                foreach (var kv in _tracks[i].Keys)
                {
                    var k = kv.Value;
                    if (i == 0) k.Position = new Vector3(-k.Position.X, k.Position.Y, k.Position.Z);
                    else k.Orientation = new Quaternion(k.Orientation.X, -k.Orientation.Y,
                                                        -k.Orientation.Z, k.Orientation.W);
                    newKeys[kv.Key] = k;
                }
                _tracks[i].Keys.Clear();
                foreach (var kv in newKeys) _tracks[i].Keys[kv.Key] = kv.Value;
            }

            // касания: X-негация (footballanimationextension.cpp:59-67)
            var mirroredTouches = new SortedDictionary<int, Vector3>();
            foreach (var kv in _touches)
                mirroredTouches[kv.Key] = new Vector3(-kv.Value.X, kv.Value.Y, kv.Value.Z);
            _touches.Clear();
            foreach (var kv in mirroredTouches) _touches[kv.Key] = kv.Value;

            // значения переменных left↔right (animation.cpp:1293-1303)
            foreach (string key in new List<string>(_variables.Keys))
            {
                string v = _variables[key];
                if (v.StartsWith("left")) _variables[key] = "right" + v.Substring(4);
                else if (v.StartsWith("right")) _variables[key] = "left" + v.Substring(5);
            }

            // direction-теги: X-негация (animation.cpp:1305-1310). В оригинале SetVariable зовётся
            // безусловно (пустой тег станет "0.000000, 0.000000, 0.000000") — bug-for-bug.
            foreach (string tag in new[] { "balldirection", "incomingballdirection", "bumpdirection" })
            {
                Vector3 v = GetVariable(tag) != ""
                    ? BluntMath.GetVectorFromString(GetVariable(tag)) * new Vector3(-1, 1, 1)
                    : Vector3.Zero;
                SetVariable(tag, BluntMath.GetStringFromVector(v));
            }

            DirtyCache();
        }
```

Нормализация direction-тегов + конверсия idle — в конец `LoadFromFile` (после `LoadXmlTail`, перед
`return`; порядок как в `Animation::Load`: нормализация `:1157-1179` → variableCache `:1181-1194`
(у нас уже словарь) → `ConvertToStartFacingForwardIfIdle()` `:1196`):

```csharp
        // animation.cpp:1157-1179 (шов 3): три direction-тега нормализуются при загрузке,
        // GetVariable дальше отдаёт уже нормализованный вектор.
        private void NormalizeDirectionTags()
        {
            foreach (string tag in new[] { "bumpdirection", "balldirection", "incomingballdirection" })
            {
                if (!_variables.ContainsKey(tag)) continue;
                Vector3 v = BluntMath.GetVectorFromString(_variables[tag]);
                if (v.Length() > 0) v = v.Normalized();
                _variables[tag] = BluntMath.GetStringFromVector(v);
            }
        }

        // Порт ConvertToStartFacingForwardIfIdle (animation.cpp:297-342): idle-входные клипы
        // разворачиваются лицом вперёд; касания и direction-теги вращаются синхронно (шов 2).
        private void ConvertToStartFacingForwardIfIdle()
        {
            float incomingBodyAngle = GetIncomingBodyAngle();
            if (GetIncomingVelocity() >= 1.8f) return;

            // позиции root (animation.cpp:305-311)
            var rootKeys = new SortedDictionary<int, KeyFrame>();
            foreach (var kv in _tracks[0].Keys)
            {
                var k = kv.Value;
                k.Position = BluntMath.GetRotated2D(k.Position, -incomingBodyAngle);
                rootKeys[kv.Key] = k;
            }
            _tracks[0].Keys.Clear();
            foreach (var kv in rootKeys) _tracks[0].Keys[kv.Key] = kv.Value;

            // ориентации body (animation.cpp:313-325)
            Quaternion zRot = QuatUtil.AngleAxis(-incomingBodyAngle, new Vector3(0, 0, 1));
            var bodyKeys = new SortedDictionary<int, KeyFrame>();
            foreach (var kv in _tracks[1].Keys)
            {
                var k = kv.Value;
                k.Orientation = zRot * k.Orientation;
                bodyKeys[kv.Key] = k;
            }
            _tracks[1].Keys.Clear();
            foreach (var kv in bodyKeys) _tracks[1].Keys[kv.Key] = kv.Value;

            // касания (animation.cpp:327-331 → footballanimationextension.cpp:49-57)
            var rotTouches = new SortedDictionary<int, Vector3>();
            foreach (var kv in _touches)
                rotTouches[kv.Key] = BluntMath.GetRotated2D(kv.Value, -incomingBodyAngle);
            _touches.Clear();
            foreach (var kv in rotTouches) _touches[kv.Key] = kv.Value;

            // direction-теги (animation.cpp:333-339; безусловный SetVariable — bug-for-bug)
            foreach (string tag in new[] { "balldirection", "incomingballdirection", "bumpdirection" })
            {
                Vector3 v = GetVariable(tag) != ""
                    ? BluntMath.GetRotated2D(BluntMath.GetVectorFromString(GetVariable(tag)), -incomingBodyAngle)
                    : Vector3.Zero;
                SetVariable(tag, BluntMath.GetStringFromVector(v));
            }

            DirtyCache();
        }
```

В `LoadFromFile` перед `return _tracks.Count > 0;`:

```csharp
            NormalizeDirectionTags();     // animation.cpp:1157-1179
            if (_tracks.Count >= 2) ConvertToStartFacingForwardIfIdle(); // animation.cpp:1196
```

Также удалить в `LoadXmlTail` устаревший комментарий «нормализация отложена до фазы 2».

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build`, `--import`, `check_gpf_anim_mirror.gd` → `CHECK PASS`.

- [ ] **Шаг 5: регрессия фазы 1 с пересчётом ожиданий**

Прогнать parse/sample/meta/write/descriptors. **Ожидаемое место поломки:** `check_gpf_anim_meta.gd`
и `check_gpf_anim_write.gd` используют `ballcontrol/idle/000.anim` — если его исходный
`incomingBodyAngle ≠ 0`, конверсия повернёт позицию касания `(0,-0.57,0.11)`. Процедура: вычислить
сырой `incomingBodyAngle` клипа (z-эйлер первого ключа body до конверсии — можно временно
распечатать в тесте или посчитать по формуле `GetAngles` от первого кватерниона body из файла);
новое ожидание = `Rotate2D(старое, -этот_угол)`. Если угол ≈ 0 — тесты пройдут как есть, ничего не
менять. **Запрещено** слепо подставлять фактический вывод как ожидание без этой ручной проверки.
`check_gpf_anim_parse.gd`/`check_gpf_anim_sample.gd`/`check_gpf_apply.gd` работают на
`movement/walk/045.anim` (incoming walk → конверсия не применяется) — измениться не должны; если
изменились, это баг реализации.

- [ ] **Шаг 6: коммит**

```bash
git add src/gpf/Animation.cs tests/check_gpf_anim_mirror.gd tests/check_gpf_anim_mirror.gd.uid tests/check_gpf_anim_meta.gd
git commit -m "feat(gpf): Mirror + разворот idle-клипов + нормализация direction-тегов (швы 2,3)"
```

---

### Задача 5: каркас `Gpf.AnimCollection` — квадранты, файловая загрузка ×2, `_PrepareAnim`

**Files:**
- Create: `src/gpf/AnimCollection.cs`
- Test: `tests/check_gpf_collection.gd`

**Interfaces:**
- Consumes: задачи 1–4; `Gpf.SkeletonBuilder`, `Gpf.AnimationApplier` (фаза 1).
- Produces (для задач 6–8, 10):
  - `public partial class AnimCollection : RefCounted`
  - `public void Load(string animationsRoot, Skeleton3D utilitySkeleton)` — скелет обязан быть в дереве (нужны глобальные позы для `touch_bodypart`).
  - `public int GetAnimationCount()`, `public Gpf.Animation GetAnim(int index)`
  - `public int GetQuadrantCount()`, `public float GetQuadrantAngle(int id)`, `public int GetQuadrantVelocityId(int id)`, `public Vector3 GetQuadrantPosition(int id)`
  - `public int GetQuadrantID(Gpf.Animation animation, Vector3 movement, float angle)` — порт `animcollection.cpp:865-880` (animation/angle в оригинале не используются — сигнатура сохранена).
  - `internal static bool CheckFunctionType(string animType, int queryFunctionTypeId)` — порт `:1211-1275`.
  - Иды типов функций (== порядок `e_FunctionType`, `gamedefines.hpp:93-108`): константы
    `FnNone=0, FnMovement=1, FnBallControl=2, FnTrap=3, FnShortPass=4, FnLongPass=5, FnHighPass=6,
    FnHeader=7, FnShot=8, FnDeflect=9, FnCatch=10, FnInterfere=11, FnTrip=12, FnSliding=13, FnSpecial=14`.
  - `public int GetIdleMovementAnimID()` — индекс первого клипа `type=movement` с incoming и outgoing idle (кэшируется при Load; фолбэк `humanoidbase.cpp:1416`).

**Порядок загрузки (порт `AnimCollection::Load`, `animcollection.cpp:354-487`):** ветка templates
подключается в задаче 6; здесь — «все остальные»: рекурсивный скан `.anim` (пропуская каталог
`templates/` и файлы с `luxury` в пути — `:437`), файлы сортируются ordinal-алфавитно (порядок
обхода в C++ файлосистемозависим, наш контракт — детерминизм); каждый файл грузится **дважды**
(`:444-449`): mirror==0 — как есть; mirror==1 — свежая загрузка + `Mirror()`; каждый экземпляр →
`_PrepareAnim`.

**`_PrepareAnim` (порт `:1171-1209`):** предупреждения о несоответствии касание↔тип (`:1177-1179`);
`animdifficultyfactor` из `CalculateAnimDifficulty` (`:977-1033`); `touchframe` + `touch_bodypart`
из живой части `AddExtraTouches` (`:883-911` — всё после `return animTouchFrame; // XDEBUG disable
this` мёртвое и не портируется); `quadrant_id` из `GetQuadrantID` по `GetOutgoingMovement()`/
`GetOutgoingAngle()`; push в список. `Slowdown`/`SmoothPositions` не портируются (вызовы
закомментированы в оригинале, `:1186-1187`).

**Санкционированное приближение (задокументировать в коде):** в C++ `touch_bodypart` ищется по
геометрии сегментов тела (`bodyParts` — Geometry-объекты `player.object`); у нас — глобальные позы
13 костей утилитарного скелета (все, кроме `player`). На выбор ближайшей части тела влияет слабо
(сегменты прикреплены к тем же узлам), сам тег используется только smuggle-фазой 4.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# AnimCollection каркас: 34 квадранта, файловая загрузка ×2, переменные _PrepareAnim.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var col = load("res://src/gpf/AnimCollection.cs").new()
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)

	# Квадранты строятся в конструкторе (animcollection.cpp:61-106): 1 idle + 3×11
	if col.GetQuadrantCount() != 34:
		print("CHECK FAIL: квадрантов → ", col.GetQuadrantCount()); ok = false
	if col.GetQuadrantVelocityId(0) != 0 or not feq(col.GetQuadrantAngle(0), 0.0):
		print("CHECK FAIL: квадрант 0 не idle"); ok = false
	# id 12 = walk 0°; id 19 = walk -45°; id 23 = sprint 0°
	if col.GetQuadrantVelocityId(12) != 2 or not feq(col.GetQuadrantAngle(12), 0.0):
		print("CHECK FAIL: квадрант 12 ≠ walk 0°"); ok = false
	if col.GetQuadrantVelocityId(19) != 2 or not feq(col.GetQuadrantAngle(19), -0.25 * PI):
		print("CHECK FAIL: квадрант 19 ≠ walk -45° → id?", col.GetQuadrantAngle(19)); ok = false
	if col.GetQuadrantVelocityId(23) != 3 or not feq(col.GetQuadrantAngle(23), 0.0):
		print("CHECK FAIL: квадрант 23 ≠ sprint 0°"); ok = false
	# позиция квадранта = (0,-1,0).Rotate2D(angle) * EnumToFloat(velocity)
	var p19: Vector3 = col.GetQuadrantPosition(19)
	if not feq(p19.x, -sin(0.25 * PI) * 5.0) or not feq(p19.y, -cos(0.25 * PI) * 5.0):
		print("CHECK FAIL: позиция квадранта 19 → ", p19); ok = false

	# Загрузка файловой части (templates подключатся в следующей задаче)
	var t0 := Time.get_ticks_msec()
	col.Load("res://assets/gpf/animations", skel)
	print("[collection] load: ", Time.get_ticks_msec() - t0, " ms, anims: ", col.GetAnimationCount())

	# 283 файла (293 минус 10 templates) × 2 зеркала = 566
	if col.GetAnimationCount() != 566:
		print("CHECK FAIL: размер коллекции → ", col.GetAnimationCount(), " (ожидалось 566)"); ok = false

	# Каждый клип обогащён; правило чётности зеркал: чётный индекс — оригинал, нечётный — _mirror
	var bad_quadrant := 0
	var bad_diff := 0
	for i in range(col.GetAnimationCount()):
		var anim = col.GetAnim(i)
		if anim.GetVariable("quadrant_id") == "": bad_quadrant += 1
		var d := float(anim.GetVariable("animdifficultyfactor"))
		if d < 0.0 or d > 1.0: bad_diff += 1
	if bad_quadrant > 0:
		print("CHECK FAIL: клипов без quadrant_id: ", bad_quadrant); ok = false
	if bad_diff > 0:
		print("CHECK FAIL: animdifficultyfactor вне [0,1]: ", bad_diff); ok = false

	# Конкретика: walk/045 → квадрант 19 (walk −45°), его зеркало → 14 (walk +45°)
	var i045 := -1
	for i in range(col.GetAnimationCount()):
		var nm: String = col.GetAnim(i).GetName()
		if nm.ends_with("movement/walk/045.anim"):
			i045 = i
			break
	if i045 < 0:
		print("CHECK FAIL: walk/045 не найден в коллекции"); ok = false
	else:
		if col.GetAnim(i045).GetVariable("quadrant_id") != "19":
			print("CHECK FAIL: quadrant walk/045 → ", col.GetAnim(i045).GetVariable("quadrant_id")); ok = false
		var mirror = col.GetAnim(i045 + 1)
		if not mirror.GetName().ends_with("_mirror"):
			print("CHECK FAIL: за оригиналом не следует зеркало"); ok = false
		elif mirror.GetVariable("quadrant_id") != "14":
			print("CHECK FAIL: quadrant зеркала → ", mirror.GetVariable("quadrant_id")); ok = false

	# Касания: у ballcontrol-клипов touchframe ≥ 0 и есть touch_bodypart; у movement touchframe = -1
	var i_bc := -1
	for i in range(col.GetAnimationCount()):
		if col.GetAnim(i).GetName().ends_with("ballcontrol/idle/000.anim"):
			i_bc = i
			break
	if i_bc < 0:
		print("CHECK FAIL: ballcontrol/idle/000 не найден"); ok = false
	else:
		if int(col.GetAnim(i_bc).GetVariable("touchframe")) < 0:
			print("CHECK FAIL: touchframe ballcontrol → ", col.GetAnim(i_bc).GetVariable("touchframe")); ok = false
		if col.GetAnim(i_bc).GetVariable("touch_bodypart") == "":
			print("CHECK FAIL: touch_bodypart пуст"); ok = false
	if i045 >= 0 and col.GetAnim(i045).GetVariable("touchframe") != "-1":
		print("CHECK FAIL: movement-клип с touchframe ≠ -1"); ok = false

	# GetQuadrantID: движение (0,-5,0) → walk 0° (id 12)
	if i045 >= 0 and col.GetQuadrantID(col.GetAnim(i045), Vector3(0, -5, 0), 0.0) != 12:
		print("CHECK FAIL: GetQuadrantID (0,-5,0) → ", col.GetQuadrantID(col.GetAnim(i045), Vector3(0, -5, 0), 0.0)); ok = false

	# GetIdleMovementAnimID указывает на idle-движение
	var idle_id: int = col.GetIdleMovementAnimID()
	if idle_id < 0 or col.GetAnim(idle_id).GetAnimType() != "movement" \
		or col.GetAnim(idle_id).GetIncomingVelocity() >= 1.8 or col.GetAnim(idle_id).GetOutgoingVelocity() >= 1.8:
		print("CHECK FAIL: GetIdleMovementAnimID → ", idle_id); ok = false

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает** (Expected: `AnimCollection.cs` не найден)

- [ ] **Шаг 3: реализация `src/gpf/AnimCollection.cs`** (каркас; `GenerateAutoAnims` — заглушка до задачи 6):

```csharp
using Godot;
using System.Collections.Generic;

namespace Gpf
{
    // Порт AnimCollection (animcollection.{hpp,cpp}): квадранты, загрузка библиотеки,
    // _PrepareAnim-обогащение. CrudeSelection — отдельным куском (задача 7).
    public partial class AnimCollection : RefCounted
    {
        // e_FunctionType (gamedefines.hpp:93-108), int-иды для моста
        public const int FnNone = 0; public const int FnMovement = 1; public const int FnBallControl = 2;
        public const int FnTrap = 3; public const int FnShortPass = 4; public const int FnLongPass = 5;
        public const int FnHighPass = 6; public const int FnHeader = 7; public const int FnShot = 8;
        public const int FnDeflect = 9; public const int FnCatch = 10; public const int FnInterfere = 11;
        public const int FnTrip = 12; public const int FnSliding = 13; public const int FnSpecial = 14;

        public struct Quadrant
        {
            public int Id;
            public Vector3 Position;
            public int VelocityId;
            public float Angle;
        }

        private readonly List<Animation> _animations = new();
        private readonly List<Quadrant> _quadrants = new();
        private readonly AnimationApplier _applier = new();
        private int _idleMovementAnimId = -1;

        // animcollection.cpp:57-58
        private const float MaxIncomingBallDirectionDeviation = 0.25f * Mathf.Pi;
        private const float MaxOutgoingBallDirectionDeviation = 0.25f * Mathf.Pi;

        public AnimCollection()
        {
            // Квадранты (animcollection.cpp:61-106): idle + 3 скорости × 11 углов
            _quadrants.Add(new Quadrant { Id = 0, VelocityId = Velo.IdVelIdle, Angle = 0, Position = Vector3.Zero });
            float[] angles =
            {
                0f, 20f, 45f, 90f, 135f, 179f, -20f, -45f, -90f, -135f, -179f,
            };
            int id = 1;
            for (int velocityId = 1; velocityId < 4; velocityId++)
            {
                foreach (float deg in angles)
                {
                    float angle = Mathf.Pi / 180f * deg;
                    _quadrants.Add(new Quadrant
                    {
                        Id = id,
                        VelocityId = velocityId,
                        Angle = angle,
                        Position = BluntMath.GetRotated2D(new Vector3(0, -1, 0), angle)
                                   * Velo.EnumToFloatVelocity(velocityId),
                    });
                    id++;
                }
            }
        }

        public int GetAnimationCount() => _animations.Count;
        public Animation GetAnim(int index) => _animations[index];
        internal List<Animation> Animations => _animations;
        public int GetQuadrantCount() => _quadrants.Count;
        public float GetQuadrantAngle(int id) => _quadrants[id].Angle;
        public int GetQuadrantVelocityId(int id) => _quadrants[id].VelocityId;
        public Vector3 GetQuadrantPosition(int id) => _quadrants[id].Position;
        internal Quadrant GetQuadrant(int id) => _quadrants[id];
        public int GetIdleMovementAnimID() => _idleMovementAnimId;

        // Порт AnimCollection::Load (animcollection.cpp:354-487).
        public void Load(string animationsRoot, Skeleton3D utilitySkeleton)
        {
            _animations.Clear();
            _idleMovementAnimId = -1;

            var files = new List<string>();
            ScanAnimFiles(animationsRoot, files);
            files.Sort(System.StringComparer.Ordinal); // контракт детерминизма (в C++ порядок ФС)

            // Ветка templates + GenerateAutoAnims (animcollection.cpp:384-419) — задача 6.
            LoadTemplatesAndGenerate(animationsRoot, utilitySkeleton);

            // «Все остальные» (animcollection.cpp:422-476): без templates/ и luxury, каждый ×2
            foreach (string file in files)
            {
                if (file.Contains("luxury") || file.Contains("templates")) continue; // :437
                for (int mirror = 0; mirror < 2; mirror++) // :444-449
                {
                    var animation = new Animation();
                    if (!animation.LoadFromFile(file))
                    {
                        GD.PushError($"Gpf.AnimCollection: не загрузился {file}");
                        continue;
                    }
                    if (mirror == 1) animation.Mirror();
                    PrepareAnim(animation, utilitySkeleton);
                }
            }

            for (int i = 0; i < _animations.Count; i++)
            {
                var a = _animations[i];
                if (a.GetAnimType() == "movement" && a.GetIncomingVelocity() < 1.8f && a.GetOutgoingVelocity() < 1.8f)
                {
                    _idleMovementAnimId = i; // фолбэк humanoidbase.cpp:1416
                    break;
                }
            }
        }

        // Задача 6 наполняет; сейчас — пусто, чтобы каркас собирался и тестировался.
        private void LoadTemplatesAndGenerate(string animationsRoot, Skeleton3D utilitySkeleton) { }

        private static void ScanAnimFiles(string dir, List<string> outFiles)
        {
            using var d = DirAccess.Open(dir);
            if (d == null) return;
            d.ListDirBegin();
            for (string f = d.GetNext(); f != ""; f = d.GetNext())
            {
                string path = dir + "/" + f;
                if (d.CurrentIsDir()) { if (!f.StartsWith(".")) ScanAnimFiles(path, outFiles); }
                else if (f.EndsWith(".anim")) outFiles.Add(path);
            }
            d.ListDirEnd();
        }

        // Порт _PrepareAnim (animcollection.cpp:1171-1209).
        private void PrepareAnim(Animation animation, Skeleton3D utilitySkeleton)
        {
            bool isTouch = animation.GetTouchCount() > 0;
            string type = animation.GetAnimType();
            bool touchless = type == "movement" || type == "trip" || type == "special";
            if (isTouch == touchless) // :1178-1179
                GD.PushWarning($"Gpf.AnimCollection: invalid ball touch for animtype: {animation.GetName()}");

            float expectedFrameCount = CalculateAnimDifficulty(animation, out float absDiff); // :1182
            _ = expectedFrameCount; // Slowdown не портируется — вызов закомментирован в оригинале (:1186)
            animation.SetVariable("animdifficultyfactor",
                absDiff.ToString(System.Globalization.CultureInfo.InvariantCulture));

            int touchFrame = AddExtraTouches(animation, utilitySkeleton); // :1189
            animation.SetVariable("touchframe", touchFrame.ToString());

            int quadrantId = GetQuadrantID(animation, animation.GetOutgoingMovement(), animation.GetOutgoingAngle()); // :1195-1197
            animation.SetVariable("quadrant_id", quadrantId.ToString());

            _animations.Add(animation);
        }

        // Живая часть AddExtraTouches (animcollection.cpp:883-911; хвост за
        // «return animTouchFrame; // XDEBUG disable this» мёртв и не портирован).
        // Приближение: «части тела» = глобальные позы 13 костей утилитарного скелета
        // (в C++ — Geometry-сегменты player.object, прикреплённые к тем же узлам).
        private int AddExtraTouches(Animation animation, Skeleton3D skel)
        {
            if (animation.GetTouchCount() == 0) return -1; // animTouchFrame default (:885)

            Vector3 animBallPos = animation.GetTouchPosition(0);
            int animTouchFrame = animation.GetTouchFrame(0);

            _applier.Apply(skel, animation, animTouchFrame, 0f); // :892

            string closest = "";
            float closestDistance = 100f; // :895
            for (int b = 0; b < skel.GetBoneCount(); b++)
            {
                string boneName = skel.GetBoneName(b);
                if (boneName == "player") continue;
                float distance = (animBallPos - skel.GetBoneGlobalPose(b).Origin).Length();
                if (distance < closestDistance)
                {
                    closestDistance = distance;
                    closest = boneName;
                }
            }
            animation.SetVariable("touch_bodypart", closest); // :909
            return animTouchFrame; // :911 — дальше в оригинале мёртвый код
        }

        // Порт CalculateAnimDifficulty (animcollection.cpp:977-1033).
        private static float CalculateAnimDifficulty(Animation animation, out float absoluteDifficulty)
        {
            bool isTouch = animation.GetTouchCount() > 0;

            float bodyDirDifficulty = Mathf.Clamp(Mathf.Abs(
                BluntMath.GetAngle2D(animation.GetIncomingBodyDirection(), animation.GetOutgoingBodyDirection()) / Mathf.Pi), 0f, 1f);
            float directionDifficulty = Mathf.Clamp(Mathf.Abs(
                BluntMath.GetAngle2D(new Vector3(0, -1, 0), animation.GetOutgoingDirection()) / Mathf.Pi), 0f, 1f);

            float veloChangeDifficulty = Mathf.Clamp(
                Mathf.Abs(animation.GetIncomingVelocity() - animation.GetOutgoingVelocity()) / Velo.Sprint, 0f, 1f);
            float accelDifficulty = Mathf.Clamp(
                (animation.GetOutgoingVelocity() - animation.GetIncomingVelocity()) / Velo.Sprint, 0f, 1f);
            float veloDifficulty = veloChangeDifficulty * 0.5f + accelDifficulty * 0.5f; // :988

            float averageVelocity = Mathf.Clamp(
                (animation.GetIncomingVelocity() + animation.GetOutgoingVelocity()) / (Velo.Sprint * 2f), 0f, 1f);
            float movementDifficulty = Mathf.Clamp(
                (animation.GetIncomingMovement() - animation.GetOutgoingMovement()).Length() / Velo.Sprint, 0f, 1f)
                * Mathf.Pow(averageVelocity, 2f);

            const float bodyDirW = 0.5f, directionW = 1.0f, veloW = 1.0f, movementW = 4.0f; // :994-997
            float result = (bodyDirDifficulty * bodyDirW + directionDifficulty * directionW +
                            veloDifficulty * veloW + movementDifficulty * movementW)
                           / (bodyDirW + directionW + veloW + movementW);

            float expectedFrameCount = 20f + result * 80f; // :1006
            absoluteDifficulty = Mathf.Clamp(result, 0f, 1f); // :1015

            if (isTouch) { expectedFrameCount *= 1.1f; expectedFrameCount += 4f; } // :1017-1020
            absoluteDifficulty *= 0.88f;             // :1022
            if (isTouch) absoluteDifficulty += 0.12f; // :1023

            expectedFrameCount = Mathf.Clamp(expectedFrameCount,
                1, animation.GetFrameCount() - 1 + 16); // :1031 (GetEffectiveFrameCount() + 16)
            return expectedFrameCount;
        }

        // Порт GetQuadrantID (animcollection.cpp:865-880); animation/angle не используются — как в оригинале.
        public int GetQuadrantID(Animation animation, Vector3 movement, float angle)
        {
            Vector3 adaptedMovement = BluntMath.GetNormalized(movement, Vector3.Zero)
                                      * Velo.RangeVelocity(movement.Length());
            int quadrantId = 0;
            float shortestDistance = 100000.0f;
            foreach (var q in _quadrants)
            {
                float distance = (adaptedMovement - q.Position).Length();
                if (distance < shortestDistance)
                {
                    shortestDistance = distance;
                    quadrantId = q.Id;
                }
            }
            return quadrantId;
        }

        // Порт _CheckFunctionType (animcollection.cpp:1211-1275); строки типов — defString
        // (animcollection.cpp:35-55). Header в switch оригинала отсутствует → false.
        internal static bool CheckFunctionType(string animType, int queryFunctionTypeId) => queryFunctionTypeId switch
        {
            FnMovement => animType == "movement",
            FnBallControl => animType == "ballcontrol",
            FnTrap => animType == "trap",
            FnShortPass => animType == "shortpass",
            FnLongPass => animType == "longpass",
            FnHighPass => animType == "highpass",
            FnShot => animType == "shot",
            FnDeflect => animType == "deflect",
            FnCatch => animType == "catch",
            FnInterfere => animType == "interfere",
            FnTrip => animType == "trip",
            FnSliding => animType == "sliding",
            FnSpecial => animType == "special",
            _ => false,
        };
    }
}
```

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build`, `--import`, `check_gpf_collection.gd` → `CHECK PASS`.
  Если время загрузки > ~20 с — зафиксировать в выводе, но не оптимизировать в этой задаче.
  Если `quadrant_id` walk/045 не 19 или зеркала не 14 — НЕ подгонять тест: проверить знаковую
  конвенцию `GetAngle2D`/`FixAngle` (самое вероятное место ошибки порта).

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/AnimCollection.cs tests/check_gpf_collection.gd tests/check_gpf_collection.gd.uid
git commit -m "feat(gpf): AnimCollection каркас — квадранты, файловая загрузка ×2, _PrepareAnim"
```

---

### Задача 6: `GenerateAutoAnims` — вариации из templates

**Files:**
- Modify: `src/gpf/AnimCollection.cs`
- Modify: `tests/check_gpf_collection.gd` (дополнить)

**Interfaces:**
- Consumes: задачи 2–5 (`Clone`, `SetKeyFrame`, `ClearTrackKeys`, `GetInterpolatedValuesAt`, дескрипторы).
- Produces: `LoadTemplatesAndGenerate` наполняется; коллекция после Load = `2×283 + 2×A` клипов,
  где `A` — число легальных автогенов; `internal static void GenerateAutoAnims(List<Animation> templates, List<Animation> autoAnims)`.

**Порт `GenerateAutoAnims` (`animcollection.cpp:125-352`) — дословно:** таблица углов `GetAngle`
(`:125-160`); константы `leanAmount=0.001f, frameCount=25, margin=0.01f` (`:164-166`); правила
легальности `:182-231` (только незакомментированные!); генерация: `gen = Clone(t1)`, имя-автоген,
`priority=1`, по каждому треку — очистка и ребилд ключей интерполяцией t1→t2 с bias-кривой
(`:294-304`), для body (n==1) — доворот `angleQuat` + **кумулятивный** lean (`movementChangeMPS *=`
внутри кадрового цикла — известная странность оригинала, портировать как есть, `:315`), для root
(n==0) — накопление `cumulativePosition` + высота (`:320-326`); `DirtyCache`; проверки
`gen.GetIncomingVelocity()==anim1.GetIncomingVelocity()` и outgoing==t2 (в C++ assert, `:337-338` —
у нас `GD.PushError` + счётчик в тесте).

**Ветка Load (`:384-419`):** загрузить `templates/*.anim` (наши 10 файлов, сортировка ordinal),
`GenerateAutoAnims` → для каждого автогена: **сначала** `Clone()`+`Mirror()`+`PrepareAnim`, **затем**
оригинал+`PrepareAnim` (порядок `:408-419` — зеркало первым, в отличие от файловой ветки!).
Templates в C++ грузятся без football-extension — у нас extension интегрирован, но
movement-шаблоны касаний не имеют, различие пустое.

- [ ] **Шаг 1: расширить тест** — добавить в конец `_initialize` в `check_gpf_collection.gd` (перед финальным print), заменив прежнюю проверку `!= 566` на блок ниже:

```gdscript
	# --- после задачи 6: 566 файловых + 2×A автогенов ---
	var total: int = col.GetAnimationCount()
	if total <= 566 or (total - 566) % 2 != 0:
		print("CHECK FAIL: размер коллекции с автогенами → ", total); ok = false
	var autogen_count := 0
	var autogen_bad_velo := 0
	var autogen_first_mirror_ok := true
	var seen_first_autogen := false
	for i in range(col.GetAnimationCount()):
		var anim = col.GetAnim(i)
		var nm: String = anim.GetName()
		if nm.begins_with("autogen"):
			autogen_count += 1
			if not seen_first_autogen:
				seen_first_autogen = true
				# порядок animcollection.cpp:408-419: зеркало ПЕРВЫМ
				autogen_first_mirror_ok = nm.ends_with("_mirror")
			if anim.GetVariable("priority") != "1":
				print("CHECK FAIL: автоген без priority=1: ", nm); ok = false
			if anim.GetAnimType() != "movement":
				print("CHECK FAIL: автоген не movement: ", nm); ok = false
			if anim.GetFrameCount() != 25:
				print("CHECK FAIL: автоген не 25 кадров: ", nm, " → ", anim.GetFrameCount()); ok = false
	if autogen_count != total - 566:
		print("CHECK FAIL: autogen_count ", autogen_count, " ≠ total-566 ", total - 566); ok = false
	if autogen_count == 0:
		print("CHECK FAIL: автогены не сгенерировались"); ok = false
	if not autogen_first_mirror_ok:
		print("CHECK FAIL: первый автоген — не зеркало (порядок :408-419)"); ok = false
	print("[collection] autogen: ", autogen_count / 2, " легальных вариаций (×2 зеркала)")
```

Плюс в C#-реализации завести счётчик нарушений velocity-инвариантов автогенов (`GD.PushError` при
несовпадении) — тест упадёт по `CHECK FAIL`-строке ниже, добавить:

```gdscript
	if col.GetAutoAnimVelocityMismatchCount() != 0:
		print("CHECK FAIL: автогены с расхождением скоростей: ", col.GetAutoAnimVelocityMismatchCount()); ok = false
```

- [ ] **Шаг 2: убедиться, что тест падает** (коллекция = 566, `GetAutoAnimVelocityMismatchCount` нет → скрипт-ошибка/FAIL)

- [ ] **Шаг 3: реализация** — в `AnimCollection.cs`:

```csharp
        private int _autoAnimVelocityMismatchCount;
        public int GetAutoAnimVelocityMismatchCount() => _autoAnimVelocityMismatchCount;

        // animcollection.cpp:125-160
        private static float GetAngle(int directionId) => directionId switch
        {
            0 => 0.0f,
            1 => 0.25f * Mathf.Pi,
            2 => -0.25f * Mathf.Pi,
            3 => 0.50f * Mathf.Pi,
            4 => -0.50f * Mathf.Pi,
            5 => 0.75f * Mathf.Pi,
            6 => -0.75f * Mathf.Pi,
            7 => 0.99f * Mathf.Pi,
            8 => -0.99f * Mathf.Pi,
            _ => 0.0f,
        };

        // Порт ветки Load для templates (animcollection.cpp:384-419).
        private void LoadTemplatesAndGenerate(string animationsRoot, Skeleton3D utilitySkeleton)
        {
            var templateFiles = new List<string>();
            ScanAnimFiles(animationsRoot + "/templates", templateFiles);
            templateFiles.Sort(System.StringComparer.Ordinal);
            if (templateFiles.Count == 0) return;

            var templates = new List<Animation>();
            foreach (string f in templateFiles)
            {
                var t = new Animation();
                if (t.LoadFromFile(f)) templates.Add(t);
            }

            var autoAnims = new List<Animation>();
            GenerateAutoAnims(templates, autoAnims);

            foreach (var auto in autoAnims) // :408-419 — зеркало первым, затем оригинал
            {
                var mirrored = auto.Clone();
                mirrored.Mirror();
                PrepareAnim(mirrored, utilitySkeleton);
                PrepareAnim(auto, utilitySkeleton);
            }
        }

        // Порт GenerateAutoAnims (animcollection.cpp:162-352). Дословно, включая кумулятивный
        // lean-эффект movementChangeMPS внутри кадрового цикла body (:315) — так в оригинале.
        internal void GenerateAutoAnims(List<Animation> templates, List<Animation> autoAnims)
        {
            const float leanAmount = 0.001f; // :164
            const int frameCount = 25;       // :165
            const float margin = 0.01f;      // :166

            for (int t1 = 0; t1 < templates.Count; t1++)
            for (int t2 = 0; t2 < templates.Count; t2++)
            {
                Animation anim1 = templates[t1];
                Animation anim2 = templates[t2];

                for (int direction = 0; direction < 9; direction++)
                {
                    float angle = GetAngle(direction);
                    float incomingVelocityT1 = anim1.GetIncomingVelocity();
                    float outgoingVelocityT2 = anim2.GetOutgoingVelocity();
                    float incomingBodyAngleT1 = anim1.GetIncomingBodyAngle();
                    float outgoingBodyAngleT2 = anim2.GetOutgoingBodyAngle();

                    bool legalAnim = true;

                    int incomingVeloId = Velo.GetVelocityID(Velo.FloatToEnumVelocity(incomingVelocityT1));
                    int outgoingVeloId = Velo.GetVelocityID(Velo.FloatToEnumVelocity(outgoingVelocityT2));
                    float averageVeloFactor = BluntMath.NormalizedClamp(incomingVeloId + outgoingVeloId, 0, 6);

                    // max acceleration (:189-190)
                    int veloIdDiff = outgoingVeloId - incomingVeloId;
                    if (veloIdDiff > 1) legalAnim = false;

                    // max deceleration через dot (:193-196)
                    float dot = new Vector3(0, -1, 0).Dot(BluntMath.GetRotated2D(new Vector3(0, -1, 0), angle));
                    int veloIdDiffDotted = Mathf.RoundToInt(outgoingVeloId * dot - incomingVeloId);
                    if (veloIdDiffDotted < -3) legalAnim = false;

                    // :198 sprint→dribble с развёрнутым корпусом
                    if (incomingVeloId == 3 && outgoingVeloId == 1 &&
                        (Mathf.Abs(outgoingBodyAngleT2) > 0.25f * Mathf.Pi + margin ||
                         Mathf.Abs(angle) > 0.25f * Mathf.Pi + margin)) legalAnim = false;

                    // :202 движение→движение с углом > 90°
                    if (incomingVeloId > 0 && outgoingVeloId > 0 &&
                        Mathf.Abs(angle) > 0.50f * Mathf.Pi + margin) legalAnim = false;

                    // :211-212 быстрые связки с углом > 45°
                    if (incomingVeloId + outgoingVeloId > 5 && Mathf.Abs(angle) > 0.25f * Mathf.Pi + margin) legalAnim = false;
                    if (incomingVeloId + outgoingVeloId > 4 && Mathf.Abs(angle) > 0.25f * Mathf.Pi + margin) legalAnim = false;

                    // :217-218 суммарный поворот > 180°
                    float bodyAngleDelta = BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi,
                        outgoingBodyAngleT2 - incomingBodyAngleT1);
                    if (Mathf.Abs(angle + bodyAngleDelta) > 1.0f * Mathf.Pi + margin) legalAnim = false;

                    const float animSpeedFactor = 1.0f; // :233

                    if (!legalAnim) continue;

                    Animation gen = anim1.Clone(); // :237
                    gen.SetName("autogen [v" + Velo.GetVelocityID(Velo.FloatToEnumVelocity(incomingVelocityT1))
                        + " b" + (int)(incomingBodyAngleT1 / Mathf.Pi * 180f)
                        + "] => [v" + Velo.GetVelocityID(Velo.FloatToEnumVelocity(outgoingVelocityT2))
                        + " b" + (int)(outgoingBodyAngleT2 / Mathf.Pi * 180f)
                        + " a" + (int)(angle / Mathf.Pi * 180f) + "]"); // :238
                    gen.SetVariable("priority", "1"); // :239

                    for (int n = 0; n < gen.GetTrackCount(); n++)
                    {
                        gen.ClearTrackKeys(n); // :246

                        Vector3 cumulativePosition = Vector3.Zero;
                        int prevFrame = 0;
                        Vector3 outgoingMovement = BluntMath.GetRotated2D(anim2.GetOutgoingMovement(), angle); // :255
                        Vector3 movementChangeMps = (outgoingMovement - anim1.GetIncomingMovement()) * (100.0f / frameCount); // :257

                        // сбор ключей обоих шаблонов (:262-276)
                        var keyFrames = new SortedSet<int>();
                        foreach (var kv in anim1.TrackKeys(n)) keyFrames.Add(kv.Key);
                        foreach (var kv in anim2.TrackKeys(n)) keyFrames.Add(kv.Key);
                        if (n == 0)
                        {
                            keyFrames.Add(1);
                            keyFrames.Add(23);
                            for (int i = 2; i < frameCount - 2; i += 4) keyFrames.Add(i); // :273
                        }

                        foreach (int frame in keyFrames) // :281-332
                        {
                            float targetFrame = frame * (1.0f / animSpeedFactor);

                            anim1.GetInterpolatedValuesAt(n, frame, out Quaternion orientationT1, out Vector3 positionT1);
                            anim2.GetInterpolatedValuesAt(n, frame, out Quaternion orientationT2, out Vector3 positionT2);
                            if (n == 0) { orientationT1 = Quaternion.Identity; orientationT2 = Quaternion.Identity; } // getOrientation=false (:289)

                            float origBias = Mathf.Clamp(frame - 1.0f, 0.0f, frameCount - 3.0f) / (frameCount - 3.0f); // :295
                            float bias = Mathf.Pow(origBias,
                                1.0f * (0.3f + 0.4f * averageVeloFactor +
                                        0.3f * BluntMath.NormalizedClamp(movementChangeMps.Length(), 0.0f, 20.0f))); // :302
                            bias = BluntMath.Curve(bias, 0.7f); // :304
                            Quaternion orientation = QuatUtil.Slerp(orientationT1, bias, orientationT2); // :306

                            if (n == 1) // body (:308-318)
                            {
                                Quaternion angleQuat = QuatUtil.AngleAxis(
                                    angle * Mathf.Pow(bias * 0.7f + origBias * 0.3f, 1.0f), new Vector3(0, 0, 1)); // :310
                                orientation = angleQuat * orientation;

                                movementChangeMps *= 0.5f + 0.5f *
                                    ((anim1.GetIncomingMovement() * (1.0f - bias) + outgoingMovement * bias).Length()
                                     / Velo.Sprint); // :315 — кумулятивно по кадрам, как в оригинале
                                Quaternion leanQuat = QuatUtil.AngleAxis(
                                    movementChangeMps.Length() * leanAmount * (0.5f + 0.5f * Mathf.Sin(origBias * Mathf.Pi)),
                                    BluntMath.GetRotated2D(new Vector3(0, 1, 0),
                                        BluntMath.GetAngle2D(BluntMath.GetNormalized(movementChangeMps, Vector3.Zero)))); // :316
                                orientation = leanQuat * orientation;
                            }

                            float height = 0.0f;
                            if (n == 0) // player (:321-326)
                            {
                                cumulativePosition +=
                                    anim1.GetIncomingMovement() * ((frame - prevFrame) * 0.01f) * (1.0f - bias) +
                                    outgoingMovement * ((frame - prevFrame) * 0.01f) * bias;
                                height = positionT1.Z * (1.0f - bias) + positionT2.Z * bias;
                            }

                            gen.SetKeyFrame(gen.GetTrackName(n), (int)Mathf.Floor(targetFrame), orientation,
                                cumulativePosition * (1.0f / animSpeedFactor) + new Vector3(0, 0, height)); // :328

                            prevFrame = frame;
                        }
                    }

                    gen.DirtyCache(); // :335

                    // :337-338 — в C++ assert
                    if (gen.GetIncomingVelocity() != anim1.GetIncomingVelocity() ||
                        gen.GetOutgoingVelocity() != anim2.GetOutgoingVelocity())
                    {
                        _autoAnimVelocityMismatchCount++;
                        GD.PushError($"Gpf.AnimCollection: автоген с расхождением скоростей: {gen.GetName()}");
                    }

                    autoAnims.Add(gen);
                }
            }

            GD.Print($"[gpf] GenerateAutoAnims: {autoAnims.Count} автогенов");
        }
```

Примечание к `keyFrames`: `SortedSet` заменяет `list.sort(); list.unique()` (`:275-276`) 1:1.
`GetInterpolatedValuesAt` для n==0 возвращает и ориентацию — оригинал зовёт с `getOrientation=false`
и оставляет `QUATERNION_IDENTITY` (`:286-291`); мы явно перетираем Identity после вызова.

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build` + `check_gpf_collection.gd` → `CHECK PASS`;
  в выводе — число автогенов. Записать это число в вывод коммита (это «золотое» число фазы; при
  10 шаблонах кандидатов 10×10×9=900, легальных — меньше). Регресс остальных gpf-тестов.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/AnimCollection.cs tests/check_gpf_collection.gd
git commit -m "feat(gpf): GenerateAutoAnims — вариации из templates (легальность, lean, зеркала)"
```

---

### Задача 7: `CrudeSelection` — булев фильтр по запросу

**Files:**
- Create: `src/gpf/CrudeSelectionQuery.cs`
- Modify: `src/gpf/AnimCollection.cs`
- Test: `tests/check_gpf_crude.gd`

**Interfaces:**
- Consumes: задачи 1–6.
- Produces (для задачи 8, 10):
  - `public partial class CrudeSelectionQuery : RefCounted` — все поля `CrudeSelectionQuery`
    (`animcollection.hpp:106-164`) как публичные C#-свойства с теми же дефолтами конструктора
    (`hpp:107-120`): `bool ByFunctionType; int FunctionTypeId; bool ByFoot; int FootId = 0;
    bool HeedForcedFoot; int StrongFootId = 1; bool BySide; Vector3 LookAtVecRel;
    bool AllowLastDitchAnims; bool ByIncomingVelocity; bool IncomingVelocityStrict;
    bool IncomingVelocityNoDribbleToIdle; bool IncomingVelocityNoDribbleToSprint;
    bool IncomingVelocityForceLinearity; int IncomingVelocityId; bool ByOutgoingVelocity;
    int OutgoingVelocityId; bool ByPickupBall; bool PickupBall = true;
    bool ByIncomingBodyDirection; Vector3 IncomingBodyDirection; bool IncomingBodyDirectionStrict;
    bool IncomingBodyDirectionForceLinearity; bool ByIncomingBallDirection;
    Vector3 IncomingBallDirection; bool ByOutgoingBallDirection; Vector3 OutgoingBallDirection;
    bool ByTripType; int TripType` + свойства-запросы: `public void SetProperty(string name, string value)`,
    `public string GetProperty(string name)` (дефолт `""` — семантика `Properties::Get`).
  - `public void AnimCollection.CrudeSelection(Godot.Collections.Array<int> dataSet, CrudeSelectionQuery query)`
    — порт `animcollection.cpp:494-863`; наполняет dataSet индексами (`internal`-перегрузка с
    `List<int>` для C#-вызовов задачи 8).

**Верность порта — построчно по секциям** (`animcollection.cpp`): TYPE `:510-514`; INCOMING
VELOCITY `:529-575` (нестрогая матрица запретов + NoDribbleTo* + ForceLinearity с «dribble==walk»
приведением `:557-559`); OUTGOING VELOCITY `:585-589`; CULL WRONG ROTATIONAL SIDE `:594-623` —
**bug-for-bug**: в `:619` оригинал складывает enum-сторону с углом (`fabs(queryIncomingToFenceSide +
fenceToOutgoingAngle)`), портировать как `Mathf.Abs((int)queryIncomingToFenceSide +
fenceToOutgoingAngle)` (иды: left=0, right=1 — `gamedefines.hpp:81-83`) с комментарием; RETAIN BALL
`:640-647`; LAST DITCH `:652-658`; INCOMING BODY ANGLE `:663-752` (margin `0.06π`; при
query idle-velocity секция пропускается; для клипов idle-входа — своя ветка `:737-747`);
INCOMING BALL DIRECTION `:757-786` (Z ×0.4 и нормализация обеих сторон; отсутствие тега у
подходящего типа — `GD.PushError` + `selectAnim=false` вместо фатала `:761`; дефолт девиации
`0.25π`, для deflect `0.4π` `:779-782`); OUTGOING BALL DIRECTION `:791-807`; PROPERTIES `:812-819`
(incoming_special_state строгое сравнение; retain-хак с deflect; specialvar1/2 через `AtoF`);
TRIP TYPE `:824-828` (`AtoI(round(AtoF))`); FORCED FOOT `:834-857` (forcedfoot strong/weak +
touchfoot + поправка на зеркальность через `GetCurrentFootId`).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# CrudeSelection: свойства-фильтры проверяются на живой коллекции повторной валидацией результата.

func _initialize() -> void:
	var ok := true
	var col = load("res://src/gpf/AnimCollection.cs").new()
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)
	col.Load("res://assets/gpf/animations", skel)
	var QueryScript := load("res://src/gpf/CrudeSelectionQuery.cs")

	# 1) movement + incoming idle strict + body dir вперёд strict:
	var q1 = QueryScript.new()
	q1.ByFunctionType = true
	q1.FunctionTypeId = 1 # FnMovement
	q1.ByIncomingVelocity = true
	q1.IncomingVelocityId = 0
	q1.IncomingVelocityStrict = true
	q1.ByIncomingBodyDirection = true
	q1.IncomingBodyDirectionStrict = true
	q1.IncomingBodyDirection = Vector3(0, -1, 0)
	var ds1: Array[int] = []
	col.CrudeSelection(ds1, q1)
	if ds1.is_empty():
		print("CHECK FAIL: q1 пуст"); ok = false
	for i in ds1:
		var a = col.GetAnim(i)
		if a.GetAnimType() != "movement":
			print("CHECK FAIL: q1 не-movement: ", a.GetName()); ok = false; break
		if a.GetIncomingVelocity() >= 1.8:
			print("CHECK FAIL: q1 не-idle вход: ", a.GetName()); ok = false; break

	# 2) то же, но incoming walk strict → в выборке нет idle-входов и нет клипов с бОльшим
	# углом корпуса, чем у запроса (:687-692)
	var q2 = QueryScript.new()
	q2.ByFunctionType = true
	q2.FunctionTypeId = 1
	q2.ByIncomingVelocity = true
	q2.IncomingVelocityId = 2
	q2.IncomingVelocityStrict = true
	q2.ByIncomingBodyDirection = true
	q2.IncomingBodyDirectionStrict = true
	q2.IncomingBodyDirection = Vector3(0, -1, 0)
	var ds2: Array[int] = []
	col.CrudeSelection(ds2, q2)
	if ds2.is_empty():
		print("CHECK FAIL: q2 пуст"); ok = false
	for i in ds2:
		var a = col.GetAnim(i)
		var vid: int = load("res://src/gpf/Velo.cs").FloatToEnumVelocity(a.GetIncomingVelocity())
		if vid != 2:
			print("CHECK FAIL: q2 strict нарушен: ", a.GetName(), " vid=", vid); ok = false; break

	# strict уже, чем нестрогий запрос
	var q2l = QueryScript.new()
	q2l.ByFunctionType = true
	q2l.FunctionTypeId = 1
	q2l.ByIncomingVelocity = true
	q2l.IncomingVelocityId = 2
	q2l.IncomingVelocityStrict = false
	var ds2l: Array[int] = []
	col.CrudeSelection(ds2l, q2l)
	if ds2l.size() < ds2.size():
		print("CHECK FAIL: нестрогий уже строгого: ", ds2l.size(), " < ", ds2.size()); ok = false
	# нестрогая матрица (:540-544): walk-запрос не пускает idle-входы
	for i in ds2l:
		if col.GetAnim(i).GetIncomingVelocity() < 1.8:
			print("CHECK FAIL: q2l пропустил idle-вход"); ok = false; break

	# 3) ballcontrol + incoming ball direction: девиация ≤ 0.25pi (или лимит из тега клипа)
	var BM = load("res://src/gpf/BluntMath.cs")
	var q3 = QueryScript.new()
	q3.ByFunctionType = true
	q3.FunctionTypeId = 2 # FnBallControl
	q3.ByIncomingBallDirection = true
	q3.IncomingBallDirection = Vector3(0, -1, 0)
	var ds3: Array[int] = []
	col.CrudeSelection(ds3, q3)
	if ds3.is_empty():
		print("CHECK FAIL: q3 пуст"); ok = false
	for i in ds3:
		var a = col.GetAnim(i)
		var bd: Vector3 = BM.GetVectorFromString(a.GetVariable("incomingballdirection"))
		if bd.length() == 0.0:
			continue # клип без тега отфильтрован ошибкой — сюда не попадает
		bd.z *= 0.4
		bd = bd.normalized()
		var adapted := Vector3(0, -1, 0)
		var dev: float = absf(BM.GetAngle2D(adapted, bd))
		var max_dev: float = absf(BM.AtoF(a.GetVariable("incomingballdirection_maxdeviation")) * PI)
		if max_dev == 0.0:
			max_dev = 0.25 * PI
		if dev > max_dev + 1.0e-4:
			print("CHECK FAIL: q3 девиация ", dev, " > ", max_dev, ": ", a.GetName()); ok = false; break

	# 4) lastditch по умолчанию отсечены
	for i in ds1:
		if col.GetAnim(i).GetVariable("lastditch") == "true":
			print("CHECK FAIL: lastditch в выборке без allowLastDitchAnims"); ok = false; break

	# 5) trip по типу: каждый выбранный имеет triptype == 1
	var q5 = QueryScript.new()
	q5.ByFunctionType = true
	q5.FunctionTypeId = 12 # FnTrip
	q5.ByTripType = true
	q5.TripType = 1
	var ds5: Array[int] = []
	col.CrudeSelection(ds5, q5)
	for i in ds5:
		if int(round(BM.AtoF(col.GetAnim(i).GetVariable("triptype")))) != 1:
			print("CHECK FAIL: q5 triptype ≠ 1: ", col.GetAnim(i).GetName()); ok = false; break

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

Примечание: `CrudeSelection` для GDScript принимает обычный `Array` (мост не строг к типизированным
массивам): публичная сигнатура — `CrudeSelection(Godot.Collections.Array dataSet, CrudeSelectionQuery query)`,
наполняющая массив int-ами; внутренняя (`internal void CrudeSelectionInternal(List<int>, ...)`) —
для задач 8/10. Если типизированный `Array[int]` через мост не примется — заменить в тесте на
нетипизированный `var ds1 := []`.

- [ ] **Шаг 2: убедиться, что тест падает** (Expected: нет `CrudeSelectionQuery.cs`)

- [ ] **Шаг 3: реализация**

`src/gpf/CrudeSelectionQuery.cs` — все поля из Interfaces выше как `public ... { get; set; }` c
дефолтами конструктора `animcollection.hpp:107-120`, плюс:

```csharp
        private readonly System.Collections.Generic.Dictionary<string, string> _properties = new();
        public void SetProperty(string name, string value) => _properties[name] = value;
        public string GetProperty(string name) => _properties.TryGetValue(name, out var v) ? v : "";
```

`AnimCollection.CrudeSelectionInternal` — порт `animcollection.cpp:494-863` одним линейным проходом.
Скелет (секции раскрываются по строкам из «Верность порта», каждая с if (selectAnim)-обёрткой как
в оригинале; ниже — секции с неочевидными местами, остальные механические):

```csharp
        internal void CrudeSelectionInternal(List<int> dataSet, CrudeSelectionQuery query)
        {
            for (int i = 0; i < _animations.Count; i++)
            {
                Animation anim = _animations[i];
                string animType = anim.GetAnimType();
                bool selectAnim = true;

                // TYPE (:510-514)
                if (selectAnim && query.ByFunctionType &&
                    !CheckFunctionType(animType, query.FunctionTypeId)) selectAnim = false;

                // INCOMING VELOCITY (:529-575)
                if (selectAnim && query.ByIncomingVelocity)
                {
                    int animIn = Velo.FloatToEnumVelocity(anim.GetIncomingVelocity());
                    if (!query.IncomingVelocityStrict)
                    {
                        if (query.IncomingVelocityNoDribbleToIdle &&
                            animIn == Velo.IdVelIdle && query.IncomingVelocityId == Velo.IdVelDribble) selectAnim = false;
                        if (animIn == Velo.IdVelIdle && query.IncomingVelocityId == Velo.IdVelWalk) selectAnim = false;
                        if (animIn == Velo.IdVelIdle && query.IncomingVelocityId == Velo.IdVelSprint) selectAnim = false;
                        if (animIn == Velo.IdVelDribble && query.IncomingVelocityId == Velo.IdVelIdle) selectAnim = false;
                        if (animIn == Velo.IdVelWalk && query.IncomingVelocityId == Velo.IdVelIdle) selectAnim = false;
                        if (animIn == Velo.IdVelSprint && query.IncomingVelocityId == Velo.IdVelIdle) selectAnim = false;
                        if (query.IncomingVelocityNoDribbleToSprint &&
                            animIn == Velo.IdVelSprint && query.IncomingVelocityId == Velo.IdVelDribble) selectAnim = false;

                        if (query.IncomingVelocityForceLinearity) // :550-563
                        {
                            float animInF = Velo.RangeVelocity(anim.GetIncomingVelocity());
                            float animOutF = Velo.RangeVelocity(anim.GetOutgoingVelocity());
                            float queryF = Velo.EnumToFloatVelocity(query.IncomingVelocityId);
                            // dribble считается walk (:557-559)
                            if (Velo.FloatToEnumVelocity(animInF) == Velo.IdVelDribble) animInF = Velo.Walk;
                            if (Velo.FloatToEnumVelocity(animOutF) == Velo.IdVelDribble) animOutF = Velo.Walk;
                            if (Velo.FloatToEnumVelocity(queryF) == Velo.IdVelDribble) queryF = Velo.Walk;
                            if (animInF > Mathf.Max(queryF, animOutF)) selectAnim = false;
                            if (animInF < Mathf.Min(queryF, animOutF)) selectAnim = false;
                        }
                    }
                    else if (animIn != query.IncomingVelocityId) selectAnim = false; // :567
                }

                // OUTGOING VELOCITY (:585-589)
                if (selectAnim && query.ByOutgoingVelocity &&
                    Velo.FloatToEnumVelocity(anim.GetOutgoingVelocity()) != query.OutgoingVelocityId) selectAnim = false;

                // CULL WRONG ROTATIONAL SIDE (:594-623)
                if (selectAnim && query.BySide)
                {
                    Vector3 animIncomingDirection = anim.GetIncomingBodyDirection();
                    Vector3 animOutgoingDirection = BluntMath.GetRotated2D(
                        anim.GetOutgoingDirection(), anim.GetOutgoingBodyAngle()); // :600
                    float animTurnAngle = BluntMath.GetAngle2D(animOutgoingDirection, animIncomingDirection);
                    Vector3 fencedDirection = BluntMath.GetRotated2D(query.LookAtVecRel, Mathf.Pi); // :604

                    if (Mathf.Abs(animTurnAngle) > 0.06f * Mathf.Pi) // :606
                    {
                        int animSide = animTurnAngle > 0 ? 0 : 1; // e_Side: left=0/right=1
                        float animInToFence = BluntMath.GetAngle2D(fencedDirection, animIncomingDirection);
                        float queryInToFence = BluntMath.GetAngle2D(fencedDirection, query.IncomingBodyDirection);
                        float fenceToOut = BluntMath.GetAngle2D(animOutgoingDirection, fencedDirection);
                        int animInToFenceSide = animInToFence > 0 ? 0 : 1;
                        int queryInToFenceSide = queryInToFence > 0 ? 0 : 1;
                        int fenceToOutSide = fenceToOut > 0 ? 0 : 1;

                        if (animInToFenceSide == animSide && fenceToOutSide == animSide &&
                            Mathf.Abs(animInToFence + fenceToOut) < Mathf.Pi) selectAnim = false; // :618
                        // :619 bug-for-bug: оригинал складывает enum-сторону (int) с радианами
                        if (queryInToFenceSide == animSide && fenceToOutSide == animSide &&
                            Mathf.Abs(queryInToFenceSide + fenceToOut) < Mathf.Pi) selectAnim = false;
                    }
                }

                // RETAIN BALL (:640-647), LAST DITCH (:652-658)
                if (selectAnim && query.ByPickupBall)
                {
                    string retain = anim.GetVariable("outgoing_retain_state");
                    if ((retain == "" && query.PickupBall) || (retain != "" && !query.PickupBall)) selectAnim = false;
                }
                if (selectAnim && !query.AllowLastDitchAnims && anim.GetVariable("lastditch") == "true") selectAnim = false;

                // INCOMING BODY ANGLE (:663-752)
                if (selectAnim && query.ByIncomingBodyDirection &&
                    !(query.ByIncomingVelocity && query.IncomingVelocityId == Velo.IdVelIdle))
                {
                    const float marginRadians = 0.06f * Mathf.Pi; // :667
                    if (Velo.FloatToEnumVelocity(anim.GetIncomingVelocity()) != Velo.IdVelIdle)
                    {
                        Vector3 incomingBodyDir = anim.GetIncomingBodyDirection();
                        // :687-692: вход клипа не «шире» текущего
                        if (Mathf.Abs(BluntMath.FixAngle(BluntMath.GetAngle2D(anim.GetIncomingBodyDirection()))) >
                            Mathf.Abs(BluntMath.FixAngle(BluntMath.GetAngle2D(query.IncomingBodyDirection))) + marginRadians)
                            selectAnim = false;

                        if (selectAnim)
                        {
                            Vector3 outgoingBodyDir = BluntMath.GetRotated2D(new Vector3(0, -1, 0),
                                anim.GetOutgoingBodyAngle() + anim.GetOutgoingAngle()); // :697
                            if (query.IncomingBodyDirectionStrict) // :709-713
                            {
                                if (Mathf.Abs(BluntMath.GetAngle2D(incomingBodyDir, query.IncomingBodyDirection)) > marginRadians)
                                    selectAnim = false;
                            }
                            else if (Mathf.Abs(BluntMath.GetAngle2D(incomingBodyDir, query.IncomingBodyDirection)) >
                                     0.5f * Mathf.Pi + marginRadians) selectAnim = false;

                            if (selectAnim && query.IncomingBodyDirectionForceLinearity) // :718-732
                            {
                                float shortestAngle1 = BluntMath.GetAngle2D(incomingBodyDir, outgoingBodyDir);
                                float shortestAngle2 = BluntMath.GetAngle2D(incomingBodyDir, query.IncomingBodyDirection);
                                if ((shortestAngle1 > marginRadians && shortestAngle2 > marginRadians) ||
                                    (shortestAngle1 < -marginRadians && shortestAngle2 < -marginRadians)) selectAnim = false;
                                if (Mathf.Abs(shortestAngle1) + Mathf.Abs(shortestAngle2) > Mathf.Pi + marginRadians)
                                    selectAnim = false;
                            }
                        }
                    }
                    else // клип с idle-входом (:737-747)
                    {
                        if (query.IncomingBodyDirectionStrict)
                        {
                            if (Mathf.Abs(BluntMath.GetAngle2D(new Vector3(0, -1, 0), query.IncomingBodyDirection)) >
                                marginRadians) selectAnim = false;
                        }
                        else if (Mathf.Abs(BluntMath.GetAngle2D(new Vector3(0, -1, 0), query.IncomingBodyDirection)) >
                                 0.25f * Mathf.Pi + marginRadians) selectAnim = false;
                    }
                }

                // INCOMING BALL DIRECTION (:757-786)
                if (selectAnim && query.ByIncomingBallDirection)
                {
                    Vector3 animBallDirection = BluntMath.GetVectorFromString(anim.GetVariable("incomingballdirection"));
                    if (animBallDirection.Length() < 0.1f)
                    {
                        GD.PushError($"Gpf.AnimCollection: {anim.GetName()} missing incoming ball direction"); // :761 (в C++ фатал)
                        selectAnim = false;
                    }
                    else if (query.IncomingBallDirection.Length() != 0.0f)
                    {
                        animBallDirection.Z *= 0.4f; // :766
                        animBallDirection = animBallDirection.Normalized();
                        Vector3 adapted = query.IncomingBallDirection;
                        adapted.Z *= 0.4f;
                        adapted = adapted.Normalized();
                        float ballDirectionAngle = Mathf.Abs(BluntMath.GetAngle2D(adapted, animBallDirection));
                        float maxDeviation = Mathf.Abs(
                            BluntMath.AtoF(anim.GetVariable("incomingballdirection_maxdeviation")) * Mathf.Pi); // :778
                        if (maxDeviation == 0.0f)
                        {
                            maxDeviation = MaxIncomingBallDirectionDeviation;
                            if (animType == "deflect") maxDeviation = 0.4f * Mathf.Pi; // :781
                        }
                        if (ballDirectionAngle > maxDeviation) selectAnim = false;
                    }
                }

                // OUTGOING BALL DIRECTION (:791-807)
                if (selectAnim && query.ByOutgoingBallDirection)
                {
                    Vector3 animBallDirection = BluntMath.GetVectorFromString(anim.GetVariable("balldirection"));
                    animBallDirection = BluntMath.GetNormalized(animBallDirection, Vector3.Zero); // :794
                    float ballDirectionAngle = Mathf.Abs(BluntMath.GetAngle2D(
                        BluntMath.GetNormalized(BluntMath.Get2D(query.OutgoingBallDirection), animBallDirection),
                        animBallDirection)); // :797
                    float maxDeviation = Mathf.Abs(
                        BluntMath.AtoF(anim.GetVariable("outgoingballdirection_maxdeviation")) * Mathf.Pi);
                    if (maxDeviation == 0.0f) maxDeviation = MaxOutgoingBallDirectionDeviation;
                    if (ballDirectionAngle > maxDeviation) selectAnim = false;
                }

                // PROPERTIES (:812-819)
                if (selectAnim)
                {
                    if (query.GetProperty("incoming_special_state") != anim.GetVariable("incoming_special_state"))
                        selectAnim = false;
                    bool queryRetain = query.GetProperty("incoming_retain_state") != "";
                    bool animRetain = anim.GetVariable("incoming_retain_state") != "";
                    if ((query.FunctionTypeId == FnDeflect || queryRetain != animRetain) &&
                        query.GetProperty("incoming_retain_state") != anim.GetVariable("incoming_retain_state"))
                        selectAnim = false;
                    if (BluntMath.AtoF(query.GetProperty("specialvar1")) != BluntMath.AtoF(anim.GetVariable("specialvar1")))
                        selectAnim = false;
                    if (BluntMath.AtoF(query.GetProperty("specialvar2")) != BluntMath.AtoF(anim.GetVariable("specialvar2")))
                        selectAnim = false;
                }

                // TRIP TYPE (:824-828)
                if (selectAnim && query.ByTripType &&
                    Mathf.RoundToInt(BluntMath.AtoF(anim.GetVariable("triptype"))) != query.TripType) selectAnim = false;

                // FORCED FOOT (:834-857)
                if (selectAnim && query.HeedForcedFoot)
                {
                    string forcedFoot = anim.GetVariable("forcedfoot");
                    int which = forcedFoot == "strong" ? 1 : forcedFoot == "weak" ? 2 : 0;
                    if (which != 0)
                    {
                        int animFoot = anim.GetVariable("touchfoot") == "left" ? 0 : 1; // :843-845
                        if (anim.GetCurrentFootId() == 0) animFoot = animFoot == 0 ? 1 : 0; // :848-850 зеркальные
                        if (which == 1 && query.StrongFootId != animFoot) selectAnim = false;
                        if (which == 2 && query.StrongFootId == animFoot) selectAnim = false;
                    }
                }

                if (selectAnim) dataSet.Add(i); // :860
            }
        }
```

Публичная мост-обёртка:

```csharp
        public void CrudeSelection(Godot.Collections.Array dataSet, CrudeSelectionQuery query)
        {
            var list = new List<int>();
            CrudeSelectionInternal(list, query);
            foreach (int i in list) dataSet.Add(i);
        }
```

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build`, `--import`, `check_gpf_crude.gd` → `CHECK PASS`; регресс `check_gpf_collection.gd`.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/CrudeSelectionQuery.cs src/gpf/AnimCollection.cs tests/check_gpf_crude.gd tests/check_gpf_crude.gd.uid
git commit -m "feat(gpf): CrudeSelection — булев фильтр запроса (bug-for-bug к :619)"
```

---

### Задача 8: `Gpf.AnimSelector` — цепочка stable_sort-предикатов и выбор клипа

**Files:**
- Create: `src/gpf/AnimSelector.cs`
- Test: `tests/check_gpf_selector.gd`

**Interfaces:**
- Consumes: задачи 1–7.
- Produces (для задачи 10):
  - `public partial class AnimSelector : RefCounted`
  - `public void Setup(AnimCollection anims)`
  - `public int SelectMovementAnim(Vector3 position, float angle, int enumVelocityId,
    float floatVelocity, Vector3 relBodyDirectionVec, int footId, Vector3 desiredDirectionWorld,
    float desiredVelocityFloat, bool useDesiredLookAt, Vector3 desiredLookAt)` → индекс клипа
    в коллекции или −1 (порт movement-пути `HumanoidBase::SelectAnim`, `humanoidbase.cpp:1374-1496`).
  - `public Godot.Collections.Array SelectMovementDataSet(...те же параметры...)` — весь
    отранжированный датасет (для тестов).
  - `public Vector3 ForceIntoAllowedBodyDirectionVec(Vector3 src)` / `public float
    ForceIntoAllowedBodyDirectionAngle(float angle)` / `public Vector3
    ForceIntoPreferredDirectionVec(Vector3 src)` / `public float ForceIntoPreferredDirectionAngle(float angle)`
    — порт `humanoidbase.cpp:2547-2606` с таблицами из конструктора `humanoidbase.cpp:63-97`.
  - `public static float CalculateBiasForFastCornering(Vector3 currentMovement, Vector3
    desiredMovement, float veloPow, float bias)` — порт `humanoid_utils.cpp:53-66`.
  - `internal static void StableSort(List<int> data, Func<int, int, bool> less)` — обязательная
    замена `std::stable_sort`.

**Порт цепочки (`humanoidbase.cpp:1425-1496`, только movement-путь):**
1. `relDesiredDirection = desiredDirection.GetRotated2D(-spatialState.angle)`;
   `SetMovementSimilarityPredicate(relDesiredDirection, FloatToEnum(desiredVelocityFloat))` (`:1429-1430`;
   cornering bias — `:1823` от `(0, -floatVelocity, 0)`); `SetBodyDirectionSimilarityPredicate(lookAt)`.
2. `_KeepBestDirectionAnims(dataSet, command)` (`:1103-1171`: stable_sort по
   `CompareMovementSimilarity`, у movement baseanim-сортировки нет; erase всех, чей `quadrant_id`
   ≠ квадранту лучшего — strict-ветка); если `useDesiredLookAt` — `_KeepBestBodyDirectionAnims`
   (`:1174-1229`: stable_sort по `CompareBodyDirectionSimilarity`, затем erase по
   `|animLookAngle − bestLookAngle| > 0.06π`).
3. stable_sort по `CompareNumericVariable("idlelevel", 1)` (`:1449-1455`, `:2009-2012`).
4. stable_sort по `CompareFootSimilarity(spatialState.foot)` (`:1457-1462`, `:1779-1787`).
5. stable_sort по `CompareIncomingBodyDirectionSimilarity(relBodyDirectionVec)` (`:1464-1469`, `:1893-1900`).
6. stable_sort по `CompareIncomingVelocitySimilarity(enumVelocity)` (`:1471-1476`, `:1793-1816`).
7. Победитель — `dataSet[0]`.

Крудовый запрос строится как в `:1383-1397` (movement, incoming strict + ForceLinearity по скорости
и корпусу); пустой датасет → фолбэк `GetIdleMovementAnimID()` (`:1412-1417`).

**Предикаты (`humanoidbase.cpp:1779-2012`)** — все как приватные методы с полями-предикатами
(`predicate_*` оригинала), в т.ч. `GetMovementSimilarity` (`:1826-1869`: `desiredMovement *= (1−corneringBias)`,
`value −= |dot| * 4.0` — «любовь к прямым»), `CompareBodyDirectionSimilarity` (`:1906-1965`:
`maxAngleSmuggle = 0.1π`, штраф `0.05` за угол корпуса) — использует `spatialState.position/angle` и
`GetTranslation()` клипа.

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# AnimSelector: стабильность сортировки, ForceInto*-таблицы, cornering bias, выбор клипа.

func feq(a: float, b: float, eps := 1.0e-4) -> bool:
	return absf(a - b) < eps

func _initialize() -> void:
	var ok := true
	var SelScript := load("res://src/gpf/AnimSelector.cs")
	var sel = SelScript.new()

	# ForceInto*-таблицы (humanoidbase.cpp:63-97, 2547-2606)
	var v: Vector3 = sel.ForceIntoAllowedBodyDirectionVec(Vector3(0.1, -1, 0).normalized())
	if not feq(v.x, 0.0) or not feq(v.y, -1.0):
		print("CHECK FAIL: allowed body dir → ", v); ok = false
	if not feq(sel.ForceIntoAllowedBodyDirectionAngle(0.3 * PI), 0.25 * PI):
		print("CHECK FAIL: allowed body angle"); ok = false
	if not feq(sel.ForceIntoPreferredDirectionAngle(0.09 * PI), 0.111 * PI):
		print("CHECK FAIL: preferred angle 0.09pi → 0.111pi (20°)"); ok = false
	if not feq(sel.ForceIntoPreferredDirectionAngle(0.95 * PI), 0.999 * PI):
		print("CHECK FAIL: preferred angle хвост"); ok = false

	# CalculateBiasForFastCornering (humanoid_utils.cpp:53-66):
	# нулевая скорость → 0; сзади на спринте → близко к 1
	if not feq(SelScript.CalculateBiasForFastCornering(Vector3.ZERO, Vector3(0, -5, 0), 1.0, 0.9), 0.0):
		print("CHECK FAIL: cornering bias @idle"); ok = false
	var b_back: float = SelScript.CalculateBiasForFastCornering(Vector3(0, -8, 0), Vector3(0, 8, 0), 1.0, 0.9)
	if b_back < 0.85:
		print("CHECK FAIL: cornering bias разворот на спринте → ", b_back); ok = false

	# Выбор клипа на живой коллекции
	var col = load("res://src/gpf/AnimCollection.cs").new()
	var skel: Skeleton3D = load("res://src/gpf/SkeletonBuilder.cs").new().BuildUtilitySkeleton()
	get_root().add_child(skel)
	col.Load("res://assets/gpf/animations", skel)
	sel.Setup(col)

	# Из idle лицом вперёд, команда «walk вперёд»: клип с idle-входом, движение вперёд
	var idx: int = sel.SelectMovementAnim(
		Vector3.ZERO, 0.0, 0, 0.0, Vector3(0, -1, 0), 1,
		Vector3(0, -1, 0), 5.0, true, Vector3(0, -10, 0))
	if idx < 0:
		print("CHECK FAIL: выбор из idle не дал клипа"); ok = false
	else:
		var a = col.GetAnim(idx)
		print("[selector] idle→walk fwd: ", a.GetName(), " quadrant=", a.GetVariable("quadrant_id"))
		if a.GetAnimType() != "movement":
			print("CHECK FAIL: не movement"); ok = false
		if a.GetIncomingVelocity() >= 1.8:
			print("CHECK FAIL: вход не idle"); ok = false
		var q: int = int(a.GetVariable("quadrant_id"))
		# разгоняемся вперёд: скорость квадранта dribble/walk, |угол| ≤ 20°
		if col.GetQuadrantVelocityId(q) < 1 or col.GetQuadrantVelocityId(q) > 2:
			print("CHECK FAIL: квадрант-скорость → ", col.GetQuadrantVelocityId(q)); ok = false
		if absf(col.GetQuadrantAngle(q)) > 0.12 * PI:
			print("CHECK FAIL: квадрант-угол → ", col.GetQuadrantAngle(q)); ok = false

	# Из walk вперёд, команда «walk вправо-назад» (135°): выбранный клип поворачивает в нужную сторону
	var dir135 := Vector3(0, -1, 0).rotated(Vector3(0, 0, 1), -0.75 * PI)
	var idx2: int = sel.SelectMovementAnim(
		Vector3.ZERO, 0.0, 2, 5.0, Vector3(0, -1, 0), 1,
		dir135, 5.0, true, dir135 * 10.0)
	if idx2 < 0:
		print("CHECK FAIL: выбор поворота не дал клипа"); ok = false
	else:
		var a2 = col.GetAnim(idx2)
		var q2: int = int(a2.GetVariable("quadrant_id"))
		print("[selector] walk→135: ", a2.GetName(), " quadrant angle=", col.GetQuadrantAngle(q2))
		if col.GetQuadrantAngle(q2) > -0.05:
			print("CHECK FAIL: поворот не в ту сторону: угол ", col.GetQuadrantAngle(q2)); ok = false

	# Датасет отранжирован и непуст; повторный вызов детерминирован
	var ds1: Array = sel.SelectMovementDataSet(
		Vector3.ZERO, 0.0, 0, 0.0, Vector3(0, -1, 0), 1, Vector3(0, -1, 0), 5.0, true, Vector3(0, -10, 0))
	var ds2: Array = sel.SelectMovementDataSet(
		Vector3.ZERO, 0.0, 0, 0.0, Vector3(0, -1, 0), 1, Vector3(0, -1, 0), 5.0, true, Vector3(0, -10, 0))
	if ds1.is_empty() or ds1 != ds2:
		print("CHECK FAIL: датасет пуст или недетерминирован"); ok = false

	skel.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

Плюс юнит стабильности сортировки — отдельный C#-путь не нужен: стабильность проверяется косвенно
детерминизмом `ds1 == ds2` и (главное) выбором LINQ `OrderBy` в реализации. В код `StableSort`
добавить комментарий-запрет `List.Sort`.

- [ ] **Шаг 2: убедиться, что тест падает** (Expected: `AnimSelector.cs` не найден)

- [ ] **Шаг 3: реализация `src/gpf/AnimSelector.cs`**

```csharp
using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Gpf
{
    // Порт слоя выбора клипа HumanoidBase (humanoidbase.cpp): ForceInto*-таблицы (:63-97, 2547-2606),
    // предикаты сравнения (:1779-2012), _KeepBest* (:1103-1229), SelectAnim movement-путь (:1374-1496).
    // ВСЕ сортировки — только StableSort (std::stable_sort); List.Sort запрещён (нестабилен).
    public partial class AnimSelector : RefCounted
    {
        private AnimCollection _anims = null!;

        private readonly List<Vector3> _allowedBodyDirVecs = new();
        private readonly List<float> _allowedBodyDirAngles = new();
        private readonly List<Vector3> _preferredDirectionVecs = new();
        private readonly List<float> _preferredDirectionAngles = new();

        // предикаты (humanoidbase.hpp: mutable predicate_*)
        private Vector3 _predRelDesiredDirection;
        private int _predDesiredVelocityId;
        private float _predCorneringBias;
        private Vector3 _predLookAt;
        private string _predNumericVariableName = "";
        private float _predNumericVariableValue;
        private int _predDesiredFootId;
        private Vector3 _predRelIncomingBodyDirection;
        private int _predIncomingVelocityId;
        private Vector3 _spatialPosition;
        private float _spatialAngle;

        public AnimSelector()
        {
            // humanoidbase.cpp:63-97
            var fwd = new Vector3(0, -1, 0);
            foreach (float a in new[] { 0f, -0.25f, 0.25f, -0.75f, 0.75f })
                _allowedBodyDirVecs.Add(BluntMath.GetRotated2D(fwd, a * Mathf.Pi));
            foreach (float a in new[] { 0f, 0.25f, -0.25f, 0.75f, -0.75f })
                _allowedBodyDirAngles.Add(a * Mathf.Pi);
            foreach (float a in new[] { 0f, 0.111f, -0.111f, 0.25f, -0.25f, 0.5f, -0.5f, 0.75f, -0.75f, 0.999f, -0.999f })
            {
                _preferredDirectionVecs.Add(BluntMath.GetRotated2D(fwd, a * Mathf.Pi));
                _preferredDirectionAngles.Add(a * Mathf.Pi);
            }
        }

        public void Setup(AnimCollection anims) => _anims = anims;

        // std::stable_sort → LINQ OrderBy (документированно стабилен). List.Sort НЕ использовать.
        internal static void StableSort(List<int> data, Func<int, int, bool> less)
        {
            var sorted = data.OrderBy(x => x, Comparer<int>.Create(
                (a, b) => less(a, b) ? -1 : less(b, a) ? 1 : 0)).ToList();
            data.Clear();
            data.AddRange(sorted);
        }

        // humanoidbase.cpp:2547-2561
        public Vector3 ForceIntoAllowedBodyDirectionVec(Vector3 src)
        {
            float bestDot = -1.0f;
            int bestIndex = 0;
            for (int i = 0; i < _allowedBodyDirVecs.Count; i++)
            {
                float nDotL = _allowedBodyDirVecs[i].Dot(src);
                if (nDotL > bestDot) { bestDot = nDotL; bestIndex = i; }
            }
            return _allowedBodyDirVecs[bestIndex];
        }

        // humanoidbase.cpp:2563-2576
        public float ForceIntoAllowedBodyDirectionAngle(float angle)
        {
            float bestDiff = 10000.0f;
            int bestIndex = 0;
            for (int i = 0; i < _allowedBodyDirAngles.Count; i++)
            {
                float diff = Mathf.Abs(_allowedBodyDirAngles[i] - angle);
                if (diff < bestDiff) { bestDiff = diff; bestIndex = i; }
            }
            return _allowedBodyDirAngles[bestIndex];
        }

        // humanoidbase.cpp:2578-2591 / :2593-2606 — та же схема по preferred-таблицам
        public Vector3 ForceIntoPreferredDirectionVec(Vector3 src) { /* как AllowedVec по _preferredDirectionVecs */
            float bestDot = -1.0f; int bestIndex = 0;
            for (int i = 0; i < _preferredDirectionVecs.Count; i++)
            { float d = _preferredDirectionVecs[i].Dot(src); if (d > bestDot) { bestDot = d; bestIndex = i; } }
            return _preferredDirectionVecs[bestIndex];
        }
        public float ForceIntoPreferredDirectionAngle(float angle)
        {
            float bestDiff = 10000.0f; int bestIndex = 0;
            for (int i = 0; i < _preferredDirectionAngles.Count; i++)
            { float d = Mathf.Abs(_preferredDirectionAngles[i] - angle); if (d < bestDiff) { bestDiff = d; bestIndex = i; } }
            return _preferredDirectionAngles[bestIndex];
        }

        // humanoid_utils.cpp:53-66
        public static float CalculateBiasForFastCornering(Vector3 currentMovement, Vector3 desiredMovement,
                                                          float veloPow, float bias)
        {
            float angle = BluntMath.GetAngle2D(BluntMath.GetNormalized(desiredMovement, currentMovement), currentMovement);
            float currentMovementBias = Mathf.Sin(Mathf.Abs(angle) - 0.5f * Mathf.Pi) * 0.5f + 0.5f;
            float velocityBias = Mathf.Pow(Mathf.Clamp(currentMovement.Length() / (Velo.Sprint - 0.5f), 0f, 1f), veloPow);
            return velocityBias * currentMovementBias * bias;
        }

        // ---- предикаты (humanoidbase.cpp:1779-2012) ----

        // :1826-1869
        private float GetMovementSimilarity(int animIndex, Vector3 relDesiredDirection, int desiredVelocityId,
                                            float corneringBias)
        {
            Vector3 desiredMovement = relDesiredDirection * Velo.EnumToFloatVelocity(desiredVelocityId);
            Vector3 outgoingDirection = ForceIntoPreferredDirectionVec(_anims.GetAnim(animIndex).GetOutgoingDirection());
            float outgoingVelocity = Velo.RangeVelocity(_anims.GetAnim(animIndex).GetOutgoingVelocity());
            Vector3 outgoingMovement = outgoingDirection * outgoingVelocity;
            desiredMovement *= 1.0f - corneringBias; // :1844
            float value = (desiredMovement - outgoingMovement).Length();
            value -= Mathf.Abs(relDesiredDirection.Dot(outgoingDirection)) * 4.0f; // :1848
            return value;
        }

        private bool CompareMovementSimilarity(int a1, int a2) // :1871-1875
            => GetMovementSimilarity(a1, _predRelDesiredDirection, _predDesiredVelocityId, _predCorneringBias)
             < GetMovementSimilarity(a2, _predRelDesiredDirection, _predDesiredVelocityId, _predCorneringBias);

        private bool CompareNumericVariable(int a1, int a2) // :2009-2012
            => Mathf.Abs(BluntMath.AtoF(_anims.GetAnim(a1).GetVariable(_predNumericVariableName)) - _predNumericVariableValue)
             < Mathf.Abs(BluntMath.AtoF(_anims.GetAnim(a2).GetVariable(_predNumericVariableName)) - _predNumericVariableValue);

        private bool CompareFootSimilarity(int a1, int a2) // :1779-1787
        {
            int one = 1, two = 1;
            if (_anims.GetAnim(a1).GetCurrentFootId() == _predDesiredFootId) one = 0;
            if (_anims.GetAnim(a2).GetCurrentFootId() == _predDesiredFootId) two = 0;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetIncomingVelocity()) == Velo.IdVelIdle) one = 0;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetIncomingVelocity()) == Velo.IdVelIdle) two = 0;
            return one < two;
        }

        private bool CompareIncomingBodyDirectionSimilarity(int a1, int a2) // :1893-1900
        {
            float r1 = Mathf.Abs(BluntMath.GetAngle2D(
                ForceIntoAllowedBodyDirectionVec(_anims.GetAnim(a1).GetIncomingBodyDirection()),
                ForceIntoAllowedBodyDirectionVec(_predRelIncomingBodyDirection))) / Mathf.Pi;
            float r2 = Mathf.Abs(BluntMath.GetAngle2D(
                ForceIntoAllowedBodyDirectionVec(_anims.GetAnim(a2).GetIncomingBodyDirection()),
                ForceIntoAllowedBodyDirectionVec(_predRelIncomingBodyDirection))) / Mathf.Pi;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetIncomingVelocity()) == Velo.IdVelIdle) r1 = 0;
            if (Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetIncomingVelocity()) == Velo.IdVelIdle) r2 = 0;
            return r1 < r2;
        }

        private bool CompareIncomingVelocitySimilarity(int a1, int a2) // :1793-1816
        {
            int currentId = Velo.GetVelocityID(_predIncomingVelocityId);
            int in1 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetIncomingVelocity()));
            int in2 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetIncomingVelocity()));
            float r1 = Mathf.Abs(Mathf.Clamp(in1 - currentId, -3, 3));
            float r2 = Mathf.Abs(Mathf.Clamp(in2 - currentId, -3, 3));
            int out1 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a1).GetOutgoingVelocity()));
            int out2 = Velo.GetVelocityID(Velo.FloatToEnumVelocity(_anims.GetAnim(a2).GetOutgoingVelocity()));
            if (in1 > Mathf.Max(currentId, out1)) r1 += 0.5f;
            if (in1 < Mathf.Min(currentId, out1)) r1 += 0.5f;
            if (in2 > Mathf.Max(currentId, out2)) r2 += 0.5f;
            if (in2 < Mathf.Min(currentId, out2)) r2 += 0.5f;
            return r1 < r2;
        }

        private bool CompareBodyDirectionSimilarity(int i1, int i2) // :1906-1965
        {
            Animation a1 = _anims.GetAnim(i1);
            Animation a2 = _anims.GetAnim(i2);
            const float translationFactor = 1.0f;
            Vector3 relDesired1 = BluntMath.GetNormalized(
                BluntMath.GetRotated2D(_predLookAt - _spatialPosition, -_spatialAngle)
                - a1.GetTranslation() * translationFactor, new Vector3(0, -1, 0));
            Vector3 relDesired2 = BluntMath.GetNormalized(
                BluntMath.GetRotated2D(_predLookAt - _spatialPosition, -_spatialAngle)
                - a2.GetTranslation() * translationFactor, new Vector3(0, -1, 0));

            const float maxAngleSmuggle = 0.1f * Mathf.Pi; // :1945
            float outAngle1 = BluntMath.GetAngle2D(BluntMath.GetRotated2D(a1.GetOutgoingDirection(),
                Mathf.Clamp(BluntMath.GetAngle2D(_predRelDesiredDirection, a1.GetOutgoingDirection()),
                    -maxAngleSmuggle, maxAngleSmuggle)), new Vector3(0, -1, 0));
            float outAngle2 = BluntMath.GetAngle2D(BluntMath.GetRotated2D(a2.GetOutgoingDirection(),
                Mathf.Clamp(BluntMath.GetAngle2D(_predRelDesiredDirection, a2.GetOutgoingDirection()),
                    -maxAngleSmuggle, maxAngleSmuggle)), new Vector3(0, -1, 0));
            Vector3 predictedOut1 = BluntMath.GetRotated2D(a1.GetOutgoingBodyDirection(), outAngle1);
            Vector3 predictedOut2 = BluntMath.GetRotated2D(a2.GetOutgoingBodyDirection(), outAngle2);
            float rating1 = Mathf.Abs(BluntMath.GetAngle2D(predictedOut1, relDesired1));
            float rating2 = Mathf.Abs(BluntMath.GetAngle2D(predictedOut2, relDesired2));
            rating1 += Mathf.Abs(a1.GetOutgoingBodyAngle()) * 0.05f; // :1956
            rating2 += Mathf.Abs(a2.GetOutgoingBodyAngle()) * 0.05f;
            return rating1 < rating2;
        }

        // ---- _KeepBest* (humanoidbase.cpp:1103-1229) ----

        // :1103-1171 (movement-путь: baseanim-сортировки нет)
        private void KeepBestDirectionAnims(List<int> dataSet, bool strict = true, float allowedAngle = 0f,
                                            int allowedVelocitySteps = 0, int forcedQuadrantId = -1)
        {
            if (dataSet.Count == 0) return;
            int bestQuadrantId = forcedQuadrantId;
            if (bestQuadrantId == -1)
            {
                StableSort(dataSet, CompareMovementSimilarity);
                bestQuadrantId = BluntMath.AtoI(_anims.GetAnim(dataSet[0]).GetVariable("quadrant_id"));
            }
            var bestQuadrant = _anims.GetQuadrant(bestQuadrantId);
            for (int k = dataSet.Count - 1; k >= 1; k--) // erase со 2-го элемента (:1134-1135)
            {
                Animation anim = _anims.GetAnim(dataSet[k]);
                int quadrantId = BluntMath.AtoI(anim.GetVariable("quadrant_id"));
                bool keep;
                if (strict) keep = quadrantId == bestQuadrantId;
                else
                {
                    var quadrant = _anims.GetQuadrant(quadrantId);
                    keep = true;
                    if (anim.GetVariable("lastditch") != "true" &&
                        Mathf.Abs(Velo.GetVelocityID(quadrant.VelocityId, true) -
                                  Velo.GetVelocityID(bestQuadrant.VelocityId, true)) > allowedVelocitySteps) keep = false;
                    if (Mathf.Abs(quadrant.Angle - bestQuadrant.Angle) > allowedAngle) keep = false;
                }
                if (!keep) dataSet.RemoveAt(k);
            }
        }

        // :1174-1229 (movement-путь)
        private void KeepBestBodyDirectionAnims(List<int> dataSet, bool strict = true, float allowedAngle = 0f)
        {
            if (dataSet.Count == 0) return;
            StableSort(dataSet, CompareBodyDirectionSimilarity);
            Animation bestAnim = _anims.GetAnim(dataSet[0]);
            float bestLookAngle = ForceIntoAllowedBodyDirectionAngle(bestAnim.GetOutgoingBodyAngle())
                                + ForceIntoPreferredDirectionAngle(bestAnim.GetOutgoingAngle());
            float adaptedAllowedAngle = strict ? 0.06f * Mathf.Pi : allowedAngle; // :1214-1217
            for (int k = dataSet.Count - 1; k >= 1; k--)
            {
                Animation anim = _anims.GetAnim(dataSet[k]);
                float animLookAngle = ForceIntoAllowedBodyDirectionAngle(anim.GetOutgoingBodyAngle())
                                    + ForceIntoPreferredDirectionAngle(anim.GetOutgoingAngle());
                if (Mathf.Abs(animLookAngle - bestLookAngle) > adaptedAllowedAngle) dataSet.RemoveAt(k);
            }
        }

        // ---- SelectAnim movement-путь (humanoidbase.cpp:1374-1496) ----

        internal List<int> SelectMovementInternal(Vector3 position, float angle, int enumVelocityId,
            float floatVelocity, Vector3 relBodyDirectionVec, int footId, Vector3 desiredDirectionWorld,
            float desiredVelocityFloat, bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            _spatialPosition = position;
            _spatialAngle = angle;

            // запрос (:1383-1397); special/retain/vars в лабе пусты
            var query = new CrudeSelectionQuery
            {
                ByFunctionType = true,
                FunctionTypeId = AnimCollection.FnMovement,
                ByIncomingVelocity = true,
                IncomingVelocityId = enumVelocityId,
                IncomingVelocityStrict = true,
                ByIncomingBodyDirection = true,
                IncomingBodyDirectionStrict = true,
                IncomingBodyDirection = relBodyDirectionVec,
                IncomingVelocityForceLinearity = true,
                IncomingBodyDirectionForceLinearity = true,
            };

            var dataSet = new List<int>();
            _anims.CrudeSelectionInternal(dataSet, query);
            if (dataSet.Count == 0) // :1412-1417
            {
                if (_anims.GetIdleMovementAnimID() >= 0) dataSet.Add(_anims.GetIdleMovementAnimID());
                else return dataSet;
            }

            // сортировочная цепочка (:1425-1476)
            Vector3 relDesiredDirection = BluntMath.GetRotated2D(desiredDirectionWorld, -angle); // :1429
            _predRelDesiredDirection = relDesiredDirection;
            _predDesiredVelocityId = Velo.FloatToEnumVelocity(desiredVelocityFloat);
            _predCorneringBias = CalculateBiasForFastCornering(
                new Vector3(0, -1.0f * floatVelocity, 0),
                relDesiredDirection * Velo.EnumToFloatVelocity(_predDesiredVelocityId), 1.0f, 0.9f); // :1823
            _predLookAt = desiredLookAt;

            KeepBestDirectionAnims(dataSet); // :1435
            if (useDesiredLookAt) KeepBestBodyDirectionAnims(dataSet); // :1436

            _predNumericVariableName = "idlelevel"; // :1449-1450
            _predNumericVariableValue = 1;
            StableSort(dataSet, CompareNumericVariable);

            _predDesiredFootId = footId; // :1457
            StableSort(dataSet, CompareFootSimilarity);

            _predRelIncomingBodyDirection = relBodyDirectionVec; // :1464
            StableSort(dataSet, CompareIncomingBodyDirectionSimilarity);

            _predIncomingVelocityId = enumVelocityId; // :1471
            StableSort(dataSet, CompareIncomingVelocitySimilarity);

            return dataSet;
        }

        public int SelectMovementAnim(Vector3 position, float angle, int enumVelocityId, float floatVelocity,
            Vector3 relBodyDirectionVec, int footId, Vector3 desiredDirectionWorld, float desiredVelocityFloat,
            bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            var ds = SelectMovementInternal(position, angle, enumVelocityId, floatVelocity, relBodyDirectionVec,
                footId, desiredDirectionWorld, desiredVelocityFloat, useDesiredLookAt, desiredLookAt);
            return ds.Count > 0 ? ds[0] : -1;
        }

        public Godot.Collections.Array SelectMovementDataSet(Vector3 position, float angle, int enumVelocityId,
            float floatVelocity, Vector3 relBodyDirectionVec, int footId, Vector3 desiredDirectionWorld,
            float desiredVelocityFloat, bool useDesiredLookAt, Vector3 desiredLookAt)
        {
            var result = new Godot.Collections.Array();
            foreach (int i in SelectMovementInternal(position, angle, enumVelocityId, floatVelocity,
                relBodyDirectionVec, footId, desiredDirectionWorld, desiredVelocityFloat, useDesiredLookAt, desiredLookAt))
                result.Add(i);
            return result;
        }
    }
}
```

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build`, `--import`, `check_gpf_selector.gd` → `CHECK PASS`.
  Если «idle→walk fwd» выбирает клип с неожиданным квадрантом — сначала печатать топ-5 датасета
  (имена+квадранты) и сверить руками с семантикой предикатов, только потом менять код.

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/AnimSelector.cs tests/check_gpf_selector.gd tests/check_gpf_selector.gd.uid
git commit -m "feat(gpf): AnimSelector — цепочка stable_sort-предикатов и выбор movement-клипа"
```

---

### Задача 9: `AnimationApplier` — реальный `baseRot` для позиции корня + `basePos` (шов 5)

**Files:**
- Modify: `src/gpf/AnimationApplier.cs`
- Modify: `tests/check_gpf_apply.gd`

**Interfaces:**
- Consumes: фаза 1 (`AnimationApplier`), `BluntMath` (задача 1).
- Produces (для задачи 10): `public void Apply(Skeleton3D skel, Animation anim, int frame,
  float timeOffsetMs, bool noPos = false, float baseRotZ = 0f, Vector3 basePos = default)` —
  при `!noPos` позиция корня доворачивается `Rotate2D(baseRotZ)` (`animation.cpp:413-415`) и
  смещается на `basePos` (`animation.cpp:715`: `SetPosition(position + basePos)`); при `noPos`
  X/Y зануляются, но `basePos` всё равно прибавляется. Из GDScript звать полным списком из 7
  аргументов (мост не видит дефолты).

- [ ] **Шаг 1: дополнить тест** — в `tests/check_gpf_apply.gd` заменить все вызовы `applier.Apply(...)`
  на 7-аргументные (`..., false, 0.0, Vector3.ZERO`) и добавить перед финальным print:

```gdscript
	# --- фаза 2 (шов 5): baseRot вращает позицию корня, basePos смещает ---
	# кадр 12: локальная позиция корня (-0.30, -0.461739, -0.05); baseRot 90° CCW:
	# Rotate2D(v, pi/2) = (-v.y, v.x) → (0.461739, -0.30)
	applier.Apply(skel, anim, 12, 0.0, false, PI / 2.0, Vector3.ZERO)
	if not vec_eq(skel.get_bone_pose_position(root), Vector3(0.461739, -0.30, -0.05)):
		print("CHECK FAIL: baseRot позиция корня → ", skel.get_bone_pose_position(root)); ok = false
	# basePos прибавляется после поворота (animation.cpp:715)
	applier.Apply(skel, anim, 12, 0.0, false, PI / 2.0, Vector3(10, 20, 0))
	if not vec_eq(skel.get_bone_pose_position(root), Vector3(10.461739, 19.70, -0.05)):
		print("CHECK FAIL: basePos → ", skel.get_bone_pose_position(root)); ok = false
	# noPos: X/Y клипа занулены, но basePos остаётся
	applier.Apply(skel, anim, 12, 0.0, true, PI / 2.0, Vector3(10, 20, 0))
	if not vec_eq(skel.get_bone_pose_position(root), Vector3(10, 20, -0.05)):
		print("CHECK FAIL: noPos+basePos → ", skel.get_bone_pose_position(root)); ok = false
```

- [ ] **Шаг 2: убедиться, что тест падает** (7-й аргумент не существует → скрипт-ошибка вызова)

- [ ] **Шаг 3: реализация** — в `AnimationApplier.Apply` заменить обработку `player`-ветки:

```csharp
                if (name == "player")
                {
                    Vector3 pos = anim.SampleRootPosition(frame, timeOffsetMs);
                    if (noPos) { pos.X = 0; pos.Y = 0; }                       // animation.cpp:410-412 (Z остаётся)
                    else pos = BluntMath.GetRotated2D(pos, baseRotZ);           // animation.cpp:413-415 (шов 5)
                    pos += basePos;                                             // animation.cpp:715
                    skel.SetBonePosePosition(idx, pos);
                }
```

сигнатура: `public void Apply(Skeleton3D skel, Animation anim, int frame, float timeOffsetMs,
bool noPos = false, float baseRotZ = 0f, Vector3 basePos = default)`. Убрать TODO-комментарий фазы 1.

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build` + `check_gpf_apply.gd` → `CHECK PASS`;
  регресс `check_gpf_collection.gd` (внутренний Apply в `AddExtraTouches` зовётся 4-аргументно —
  дефолты в C#-вызовах работают).

- [ ] **Шаг 5: коммит**

```bash
git add src/gpf/AnimationApplier.cs tests/check_gpf_apply.gd
git commit -m "feat(gpf): Apply — baseRot для позиции корня + basePos (шов 5 фазы 1)"
```

---

### Задача 10: лаб-сцена `walk_lab` — палочник бегает по командам

**Files:**
- Create: `scenes/lab/walk_lab.tscn` (корень — `WalkLabMain`)
- Create: `src/lab/WalkLabMain.cs`
- Test: `tests/check_gpf_walker.gd`

**Interfaces:**
- Consumes: всё из задач 1–9; `SkeletonBuilder`, `StickmanRenderer`, `AnimationApplier` (фаза 1).
- Produces: сцена `res://scenes/lab/walk_lab.tscn`; тестовый API `WalkLabMain`:
  `public void SetCommand(Vector3 desiredDirectionTheirSpace, int desiredVelocityId)`,
  `public void StepOneFrame()` (детерминированный шаг 10 мс — то же, что физ-тик),
  `public int GetCurrentAnimIndex()`, `public int GetTransitionCount()`,
  `public int GetStateVelocityId()`, `public float GetStateAngle()`, `public Vector3 GetStatePosition()`.
  Существующая `anim_lab.tscn` не меняется.

**Интеграция состояния — ЯВНОЕ УПРОЩЕНИЕ, не порт** (пометить в коде): реальный
`CalculateFactualSpatialState` (`humanoidbase.cpp:1650-1720`) приедет с варпингом в фазе 3. Lite-версия
на смене клипа: `position += Rotate2D(anim.GetTranslation(), angle)`;
`angle = ModulateIntoRange(-π, π, angle + anim.GetOutgoingAngle())`;
`enumVelocityId = FloatToEnumVelocity(anim.GetOutgoingVelocity())`;
`floatVelocity = RangeVelocity(anim.GetOutgoingVelocity())`;
`relBodyDirectionVec = ForceIntoAllowedBodyDirectionVec(Rotate2D((0,-1,0), anim.GetOutgoingBodyAngle()))`;
`footId = anim.GetOutgoingFootId()`. Проигрывание: кадр++ каждые 10 мс,
`Apply(skel, anim, frame, offset, false, angle, position)`; смена клипа при
`frame >= GetFrameCount() - 1`; выбор следующего — `SelectMovementAnim(...)` с командой
(`desiredLookAt = position + desiredDirection * 10`, `useDesiredLookAt = true`), фолбэк —
`GetIdleMovementAnimID()`.

**Управление:** стрелки — направление в «их» пространстве (↑ = вперёд `(0,-1,0)`, комбинации —
диагонали; направление запоминается, не сбрасывается при отпускании); `1/2/3` — dribble/walk/sprint,
`0` — idle. HUD: имя клипа, quadrant_id, состояние (velocity id, угол в градусах), команда; стрелка-меш
над палочником показывает желаемое направление. Камера — сверху-сзади, следит за `position`
(конверсия в Godot-оси — через тот же `GpfSpace`-базис, как маркеры фазы 1).

- [ ] **Шаг 1: написать падающий тест**

```gdscript
extends SceneTree
# Walker: разгон из idle до спринта по команде «вперёд», поворот по команде «вправо».
# Детерминизм: сцена шагается вручную StepOneFrame, физ-тики не нужны.

func _initialize() -> void:
	var ok := true
	var packed: PackedScene = load("res://scenes/lab/walk_lab.tscn")
	if packed == null:
		print("CHECK FAIL: walk_lab.tscn не найден")
		quit(1)
		return
	var lab = packed.instantiate()
	get_root().add_child(lab)

	# Команда: вперёд, спринт. Идём до 4 смен клипа (idle→dribble→walk→sprint максимум по +1 за клип).
	lab.SetCommand(Vector3(0, -1, 0), 3)
	var guard := 0
	while lab.GetTransitionCount() < 4 and guard < 5000:
		lab.StepOneFrame()
		guard += 1
	if guard >= 5000:
		print("CHECK FAIL: 4 смены клипа не случились за 5000 кадров"); ok = false
	if lab.GetStateVelocityId() < 2:
		print("CHECK FAIL: после 4 клипов скорость всё ещё ", lab.GetStateVelocityId()); ok = false
	# Двигаемся вперёд: |угол| мал, позиция ушла в -Y
	if absf(lab.GetStateAngle()) > 0.15 * PI:
		print("CHECK FAIL: угол после разгона → ", lab.GetStateAngle()); ok = false
	var pos: Vector3 = lab.GetStatePosition()
	if pos.y > -1.0:
		print("CHECK FAIL: позиция не ушла вперёд → ", pos); ok = false

	# Поворот направо (в «их» осях право = Rotate2D(вперёд, -pi/2))
	var angle_before: float = lab.GetStateAngle()
	var right := Vector3(0, -1, 0).rotated(Vector3(0, 0, 1), -0.5 * PI)
	lab.SetCommand(right, 2)
	var transitions_before: int = lab.GetTransitionCount()
	guard = 0
	while lab.GetTransitionCount() < transitions_before + 3 and guard < 5000:
		lab.StepOneFrame()
		guard += 1
	var dturn: float = lab.GetStateAngle() - angle_before
	# ModulateIntoRange вручную, углы могли перескочить через -pi
	while dturn > PI: dturn -= TAU
	while dturn < -PI: dturn += TAU
	if dturn > -0.15 * PI:
		print("CHECK FAIL: за 3 клипа не повернул направо: Δ", dturn); ok = false

	# Стоп-команда: скорость спадает
	lab.SetCommand(Vector3(0, -1, 0), 0)
	transitions_before = lab.GetTransitionCount()
	guard = 0
	while lab.GetTransitionCount() < transitions_before + 5 and guard < 8000:
		lab.StepOneFrame()
		guard += 1
	if lab.GetStateVelocityId() > 1:
		print("CHECK FAIL: после стоп-команды скорость → ", lab.GetStateVelocityId()); ok = false

	lab.queue_free()
	print("CHECK PASS" if ok else "CHECK FAIL")
	quit(0 if ok else 1)
```

- [ ] **Шаг 2: убедиться, что тест падает** (сцены нет)

- [ ] **Шаг 3: реализация `src/lab/WalkLabMain.cs`**

```csharp
using Godot;

namespace Gpf.Lab
{
    // Лаб-сцена фазы 2: палочник бегает по командам (направление/скорость), клипы выбирает
    // AnimSelector. Интеграция состояния на смене клипа — УПРОЩЕНИЕ фазы 2 (lite), реальный
    // CalculateFactualSpatialState (humanoidbase.cpp:1650-1720) приедет с варпингом в фазе 3.
    public partial class WalkLabMain : Node3D
    {
        private readonly Gpf.AnimationApplier _applier = new();
        private Gpf.AnimCollection _collection = null!;
        private Gpf.AnimSelector _selector = null!;
        private Skeleton3D _skeleton = null!;
        private Node3D _gpfSpace = null!;
        private Label _label = null!;
        private MeshInstance3D _commandArrow = null!;
        private Camera3D _camera = null!;

        // spatial state lite («их» пространство)
        private Vector3 _position;
        private float _angle;
        private int _velocityId;
        private float _floatVelocity;
        private Vector3 _relBodyDir = new Vector3(0, -1, 0);
        private int _footId = 1;

        // команда
        private Vector3 _desiredDirection = new Vector3(0, -1, 0);
        private int _desiredVelocityId;

        private int _currentAnim = -1;
        private int _frame;
        private double _timeMs;
        private int _transitions;

        public override void _Ready()
        {
            Engine.PhysicsTicksPerSecond = 100; // дисциплина ядра, только в лабе

            var builder = new Gpf.SkeletonBuilder();
            _gpfSpace = builder.BuildAxisWrapper();
            AddChild(_gpfSpace);
            _skeleton = builder.BuildUtilitySkeleton();
            _gpfSpace.AddChild(_skeleton);
            var stickman = new StickmanRenderer();
            _gpfSpace.AddChild(stickman);
            stickman.Setup(_skeleton);

            SetupEnvironment();

            _collection = new Gpf.AnimCollection();
            ulong t0 = Time.GetTicksMsec();
            _collection.Load("res://assets/gpf/animations", _skeleton);
            GD.Print($"[WALK LAB] collection: {_collection.GetAnimationCount()} anims, {Time.GetTicksMsec() - t0} ms");
            _selector = new Gpf.AnimSelector();
            _selector.Setup(_collection);

            _currentAnim = _collection.GetIdleMovementAnimID();
            _frame = 0;
        }

        private void SetupEnvironment()
        {
            var floor = new MeshInstance3D
            {
                Mesh = new PlaneMesh { Size = new Vector2(200, 200) },
                MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.13f, 0.33f, 0.15f) },
            };
            AddChild(floor);
            var light = new DirectionalLight3D();
            light.RotationDegrees = new Vector3(-55, 30, 0);
            AddChild(light);
            _camera = new Camera3D();
            AddChild(_camera);

            _commandArrow = new MeshInstance3D
            {
                Mesh = new BoxMesh { Size = new Vector3(0.06f, 0.06f, 0.7f) },
                MaterialOverride = new StandardMaterial3D
                    { AlbedoColor = new Color(1f, 0.9f, 0.2f), ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded },
            };
            _gpfSpace.AddChild(_commandArrow);

            var canvas = new CanvasLayer();
            AddChild(canvas);
            _label = new Label { Position = new Vector2(16, 12) };
            canvas.AddChild(_label);
        }

        // --- тестовый/входной API ---
        public void SetCommand(Vector3 desiredDirectionTheirSpace, int desiredVelocityId)
        {
            if (desiredDirectionTheirSpace.Length() > 0.01f)
                _desiredDirection = Gpf.BluntMath.GetNormalized(desiredDirectionTheirSpace, new Vector3(0, -1, 0));
            _desiredVelocityId = Mathf.Clamp(desiredVelocityId, 0, 3);
        }

        public int GetCurrentAnimIndex() => _currentAnim;
        public int GetTransitionCount() => _transitions;
        public int GetStateVelocityId() => _velocityId;
        public float GetStateAngle() => _angle;
        public Vector3 GetStatePosition() => _position;

        // Один детерминированный шаг 10 мс (== кадр клипа при 100 Гц).
        public void StepOneFrame()
        {
            if (_currentAnim < 0) return;
            var anim = _collection.GetAnim(_currentAnim);

            _applier.Apply(_skeleton, anim, _frame, 0f, false, _angle, _position);
            _frame++;

            if (_frame >= anim.GetFrameCount() - 1)
                AdvanceToNextAnim(anim);
        }

        private void AdvanceToNextAnim(Gpf.Animation finished)
        {
            // интеграция lite (см. шапку класса)
            _position += Gpf.BluntMath.GetRotated2D(finished.GetTranslation(), _angle);
            _angle = Gpf.BluntMath.ModulateIntoRange(-Mathf.Pi, Mathf.Pi, _angle + finished.GetOutgoingAngle());
            _velocityId = Gpf.Velo.FloatToEnumVelocity(finished.GetOutgoingVelocity());
            _floatVelocity = Gpf.Velo.RangeVelocity(finished.GetOutgoingVelocity());
            _relBodyDir = _selector.ForceIntoAllowedBodyDirectionVec(
                Gpf.BluntMath.GetRotated2D(new Vector3(0, -1, 0), finished.GetOutgoingBodyAngle()));
            _footId = finished.GetOutgoingFootId();

            int next = _selector.SelectMovementAnim(
                _position, _angle, _velocityId, _floatVelocity, _relBodyDir, _footId,
                _desiredDirection, Gpf.Velo.EnumToFloatVelocity(_desiredVelocityId),
                true, _position + _desiredDirection * 10f);
            _currentAnim = next >= 0 ? next : _collection.GetIdleMovementAnimID();
            _frame = 0;
            _transitions++;
        }

        public override void _PhysicsProcess(double delta) => StepOneFrame();

        public override void _Process(double delta)
        {
            if (_currentAnim < 0) return;
            var anim = _collection.GetAnim(_currentAnim);

            // стрелка команды и камера — в «их» пространстве, конверсию делает GpfSpace
            _commandArrow.Position = _position + new Vector3(0, 0, 2.2f);
            _commandArrow.LookAt(_gpfSpace.ToGlobal(_position + new Vector3(0, 0, 2.2f) + _desiredDirection), Vector3.Up);

            Vector3 camTargetTheirs = _position + new Vector3(0, 0, 1f);
            Vector3 camTarget = _gpfSpace.ToGlobal(camTargetTheirs);
            _camera.Position = camTarget + new Vector3(0, 6f, 7f);
            _camera.LookAt(camTarget);

            _label.Text = $"{anim.GetName()}\n"
                + $"quadrant: {anim.GetVariable("quadrant_id")}   frame: {_frame}/{anim.GetFrameCount()}\n"
                + $"state: v={_velocityId} angle={Mathf.RadToDeg(_angle):F0}°   "
                + $"cmd: v={_desiredVelocityId} dir=({_desiredDirection.X:F1},{_desiredDirection.Y:F1})\n"
                + "стрелки — направление, 0/1/2/3 — idle/dribble/walk/sprint";
        }

        public override void _UnhandledKeyInput(InputEvent ev)
        {
            if (ev is not InputEventKey k || !k.Pressed || k.Echo) return;
            Vector3 dir = _desiredDirection;
            switch (k.Keycode)
            {
                case Key.Up: dir = new Vector3(0, -1, 0); break;
                case Key.Down: dir = new Vector3(0, 1, 0); break;
                case Key.Left: dir = new Vector3(-1, 0, 0); break;
                case Key.Right: dir = new Vector3(1, 0, 0); break;
                case Key.Key0: SetCommand(dir, 0); return;
                case Key.Key1: SetCommand(dir, 1); return;
                case Key.Key2: SetCommand(dir, 2); return;
                case Key.Key3: SetCommand(dir, 3); return;
                default: return;
            }
            SetCommand(dir, _desiredVelocityId);
        }
    }
}
```

`scenes/lab/walk_lab.tscn` — минимальная сцена: один корневой узел `Node3D` со скриптом
`res://src/lab/WalkLabMain.cs` (всё остальное строится кодом в `_Ready`, как в `anim_lab.tscn`).

Примечание: `StepOneFrame` из теста и `_PhysicsProcess` не конфликтуют — в headless `-s`-режиме
физ-тики сцены не гоняются (SceneTree-скрипт управляет кадрами сам); в интерактивном запуске
источник шагов — физ-тик 100 Гц.

- [ ] **Шаг 4: собрать и прогнать** — `dotnet build`, `--import`, `check_gpf_walker.gd` → `CHECK PASS`.

- [ ] **Шаг 5: полный регресс** — все `tests/check_gpf_*.gd` по одному → `CHECK PASS`; обе
  headless-команды репо (меню-загрузка и `match.tscn`) — дифф ошибок по категории/тексту против
  baseline, новых категорий быть не должно.

- [ ] **Шаг 6: ручная приёмка (критерий фазы 2 из роадмапа)**

```powershell
& "C:\Users\User\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:\Users\User\Desktop\projects\OpenFootball" res://scenes/lab/walk_lab.tscn
```

Проверить глазами: разгон из idle по ↑+3 (idle→dribble→walk→sprint без телепортов), повороты на
45/90/135 по стрелкам с видимым поворотом корпуса, остановка по 0, отсутствие «лунной походки»
(ноги не скользят), зеркальные клипы включаются (в HUD мелькают `_mirror`). Это ворота приёмки —
без визуального «бегает и выбирает правильный клип» фаза не закрывается.

- [ ] **Шаг 7: коммит**

```bash
git add src/lab/WalkLabMain.cs scenes/lab/walk_lab.tscn tests/check_gpf_walker.gd tests/check_gpf_walker.gd.uid
git commit -m "feat(lab): walk_lab — палочник бегает по командам через AnimSelector"
```

---

### Задача 11: документация — вики, log.md, хуки

**Files:**
- Modify: `docs/wiki/порт-gameplayfootball.md`
- Modify: `docs/wiki/открытые-вопросы.md`
- Modify: `docs/wiki/index.md` (только если менялись названия страниц — иначе не трогать)
- Modify: `log.md` (append-only, в конец)
- Modify: `.claude/hooks/wiki-hint.py` (маппинги новых файлов)

**Interfaces:**
- Consumes: фактическое состояние кода после задач 1–10 (числа, имена, поведение — сверять грепом, не по памяти).

- [ ] **Шаг 1: `docs/wiki/порт-gameplayfootball.md`** — переписать устаревшие утверждения (не «UPDATE:»):
  - Статус: фаза 2 готова (принята визуально), следующая — фаза 3 (варпинг).
  - Структура: добавить `BluntMath.cs`, `Velo.cs`, `AnimCollection.cs`, `CrudeSelectionQuery.cs`,
    `AnimSelector.cs`, `src/lab/WalkLabMain.cs`, `scenes/lab/walk_lab.tscn` с одной строкой на файл.
  - Раздел «Что НЕ портировано в фазе 1» переработать: швы 1–6 закрыты (убрать), добавить «что НЕ
    портировано в фазе 2»: `Slowdown`/`SmoothPositions` (мертвы в оригинале), реальный
    `CalculateFactualSpatialState` (лаба живёт на lite-интеграции — фаза 3), не-movement пути
    `SelectAnim`.
  - Новые инварианты: стабильные сортировки только через `AnimSelector.StableSort`; bug-for-bug
    порт `:619`; кумулятивный lean в `GenerateAutoAnims`; порядок зеркал (файловые:
    оригинал→зеркало; автогены: зеркало→оригинал); `ConvertToStartFacingForwardIfIdle` в load-пути
    (идл-клипы развёрнуты вперёд); квантование скоростей `1.8/4.2/6.0 → 0/3.5/5.0/7.0`.
  - Тесты: перечислить новые check-скрипты одной строкой каждый; «золотое» число автогенов — из
    фактического вывода `check_gpf_collection.gd`.
  - Управление walk_lab (таблица клавиш).
- [ ] **Шаг 2: `docs/wiki/открытые-вопросы.md`** — из раздела «Порт GameplayFootball» удалить два
  закрытых пункта (нормализация direction-тегов; `position.Rotate2D(baseRot)`); добавить актуальные:
  lite-интеграция состояния в walk_lab до фазы 3; `touch_bodypart` считается по костям скелета, а не
  Geometry-сегментам (приближение; пересмотреть при smuggle в фазе 4).
- [ ] **Шаг 3: `log.md`** — одна запись в конец:
  `## [YYYY-MM-DD] веха | Порт GPF фаза 2: AnimCollection` — 3–5 строк: библиотека N клипов
  (файловые ×2 + автогены ×2), CrudeSelection + stable_sort-цепочка, палочник бегает по командам в
  walk_lab; ключевые решения (bug-for-bug, lite-интеграция).
- [ ] **Шаг 4: `.claude/hooks/wiki-hint.py`** — добавить в маппинг новые файлы `src/gpf/*.cs`
  (BluntMath, Velo, AnimCollection, CrudeSelectionQuery, AnimSelector) и `src/lab/WalkLabMain.cs` →
  страница `порт-gameplayfootball`.
- [ ] **Шаг 5: проверка ссылок** — прогнать скилл `wiki-lint` ИЛИ вручную: все `[[ссылки]]` новых
  абзацев указывают на существующие страницы; `константы.md` не трогается (числа порта живут на
  странице порта — они не «настраиваемые», а вербатим из C++).
- [ ] **Шаг 6: коммит**

```bash
git add docs/wiki/порт-gameplayfootball.md docs/wiki/открытые-вопросы.md log.md .claude/hooks/wiki-hint.py
git commit -m "docs(wiki): фаза 2 порта GPF — AnimCollection, выбор клипа, walk_lab"
```

---

## Самопроверка плана (выполнена при написании)

**Покрытие роадмапа (п. 2 фазировки):** загрузка всей библиотеки — задачи 5–6; GenerateAutoAnims —
задача 6; Mirror — задача 4 (+ вызовы в 5–6); квадранты — задача 5; CrudeSelection — задача 7;
цепочка stable_sort-предикатов — задача 8; приёмка «палочник бегает по командам» — задача 10 (шаг 6 —
ручные ворота). Все 6 швов фазы 1 — таблица в шапке + задача на каждый.

**Типовая консистентность между задачами:** `BluntMath.GetRotated2D/GetAngle2D/AtoF/AtoI` (задача 1)
используются в 3–8, 10 с теми же сигнатурами; `Velo.FloatToEnumVelocity → int` везде; иды ног
0/1 и скоростей 0–3 — единые; `CrudeSelectionInternal(List<int>, query)` (задача 7) — то, что зовёт
`AnimSelector` (задача 8); `Apply(..., baseRotZ, basePos)` (задача 9) — то, что зовёт `WalkLabMain`
(задача 10); `GetQuadrant`/`Quadrant.VelocityId` — internal-доступ селектора к коллекции (обе в
namespace `Gpf`, одна сборка).

**Известные риски, заложенные в шаги:** изменение ожиданий meta-теста из-за
`ConvertToStartFacingForwardIfIdle` (задача 4 шаг 5 — процедура пересчёта, слепая подгонка
запрещена); знаковая конвенция `GetAngle2D` (тест задачи 1 пиннит знак, тест задачи 5 пиннит
квадранты 19/14 клипа walk/045 и его зеркала); нестабильность сортировок (запрет `List.Sort`,
детерминизм пиннится в задаче 8); производительность Load (замер печатается в задачах 5 и 10, порог
не ставим — оптимизация не входит в фазу).

