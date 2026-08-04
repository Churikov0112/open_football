# Команды прогона оракула

Status: reference
Type: notes

Заполняется по мере готовности сторон. Потребители: тикеты 02 (трасса), 03 (порт), 07 (приёмка).

## Эталон-exe (форк GameplayFootball, ветка `oracle`)

Сборка (cmake из VS 2022 BuildTools; vcpkg лежит в `C:/dev/vcpkg`, тулчейн уже в кэше `build/`):

```bash
"C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe" --build "C:/Users/User/Desktop/projects/GameplayFootball/build" --parallel --config Release
```

Прогон (рабочий каталог обязан содержать `data/`, то есть `build/Release`):

```bash
cd "C:/Users/User/Desktop/projects/GameplayFootball/build/Release" && ./gameplayfootball.exe oracle.config
```

`oracle.config` версионирован в форке как `data/oracle.config` и попадает в `build/Release` вместе с
остальным `data/`. Ключи:

| Ключ | Значение сейчас |
|---|---|
| `oracle_scenario` | `C:/Users/User/Desktop/projects/OpenFootball/tests/scenarios/walk_line.txt` |
| `oracle_trace` | `C:/Users/User/Desktop/projects/OpenFootball/out/ref.csv` |
| `oracle_manifest` | `C:/Users/User/Desktop/projects/OpenFootball/out/ref_manifest.csv` |

Второй конфиг, `rng_probe.config` (тоже версионирован в `data/`), гоняет сценарий с касаниями мяча и
пишет в `out/rng_ref.csv` — им проверяется только повторяемость эталона, с портом он не сравнивается:

```bash
cd "C:/Users/User/Desktop/projects/GameplayFootball/build/Release" && ./gameplayfootball.exe rng_probe.config
```

Каталог `out/` в репозитории порта должен существовать: писатель файлы создаёт, каталоги — нет.
Содержимое `out/` не версионируется.

Сценарии лежат в репозитории **порта** (`tests/scenarios/`), эталон получает путь ключом конфига.
Пример обоих выходных файлов с разбором — [trace-example.md](./trace-example.md).

**Вывод идёт в `build/Release/log.txt`**, не в консоль: exe собран с подсистемой WIN32 (`CMakeLists.txt`,
`add_executable(... WIN32 ...)`), так что `printf` некуда девать. Строки оракула ищутся так:

```bash
grep "Oracle::" "C:/Users/User/Desktop/projects/GameplayFootball/build/Release/log.txt"
```

Коды возврата: `0` — прогон дошёл до `ticks`; `1` — ошибка разбора сценария либо не наступило условие
нулевого тика за 3000 тиков (причина печатается в `log.txt` последней строкой).

Прогон без `oracle_scenario` ведёт себя как ветка `windows` — меню, клавиатура, ожидание человека:

```bash
cd "C:/Users/User/Desktop/projects/GameplayFootball/build/Release" && ./gameplayfootball.exe football.config
```

## Порт

Пути — абсолютные либо относительно корня репозитория порта. Каталог `out/` должен существовать.

```bash
"C:/Users/User/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:/Users/User/Desktop/projects/OpenFootball" --headless -s res://tools/run_scenario.gd -- tests/scenarios/walk_line.txt out/ref.csv out/port.csv out/port_manifest.csv
```

Аргументы после `--`: сценарий, **трасса эталона**, выходная трасса, выходной манифест. Трасса
эталона здесь вход: из её первой строки берутся стартовые позиция и угол игрока и позиция мяча.
Отсюда жёсткий порядок цикла — сначала прогон эталона, потом прогон порта, потом дифф.

Коды возврата: `0` — прогон дошёл до `ticks`; `1` — ошибка сценария, входной трассы или не наступило
условие нулевого тика; `2` — не хватает аргументов. При ошибке причина печатается строкой
`ORACLE FAIL: ...`.

Приёмка харнесса порта — `tests/check_gpf_trace.gd`, запускается обычным способом:

```bash
"C:/Users/User/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:/Users/User/Desktop/projects/OpenFootball" --headless -s res://tests/check_gpf_trace.gd
```

Интерактивный запуск лабы (`scenes/lab/ball_lab.tscn`) этим не затронут: оракул-режим включается
только вызовом `SetupOracle`.

## Дифф

Манифесты коллекции — первый вопрос оракула; пока они не сошлись, построчный дифф трасс не имеет
смысла.

```bash
"C:/Users/User/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:/Users/User/Desktop/projects/OpenFootball" --headless -s res://tools/manifest_diff.gd -- out/ref_manifest.csv out/port_manifest.csv
```

Коды возврата: `0` — совпали; `1` — разошлись по составу или по порядку; `2` — не хватает аргументов
или файл не читается. Вердикт на реальной паре — [manifest-verdict.md](./manifest-verdict.md).

Дифф трасс по дискретным полям — первый разошедшийся тик. Ту же проверку манифестов он делает своей
первой стадией, логика общая и живёт в `tools/oracle_manifest.gd`:

```bash
"C:/Users/User/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:/Users/User/Desktop/projects/OpenFootball" --headless -s res://tools/trace_diff.gd -- out/ref.csv out/port.csv out/ref_manifest.csv out/port_manifest.csv tools/trace_whitelist.txt
```

Аргументы после `--`: трасса эталона, трасса порта, манифест эталона, манифест порта, белый список.
Коды возврата: `0` — дискретные поля совпали; `1` — расхождение, расхождение манифестов либо переезд
контроля; `2` — не хватает аргументов, файл не читается или трасса сломана.

Приёмка обоих инструментов (манифесты и трассы, синтетика в самом тесте):

```bash
"C:/Users/User/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe" --path "C:/Users/User/Desktop/projects/OpenFootball" --headless -s res://tests/check_trace_diff.gd
```

Непрерывный слой (позиции, углы, смаггл, начало роста) — тикет 06, дописывается в те же файлы.
