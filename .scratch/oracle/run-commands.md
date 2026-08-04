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

Тикет 03.

## Дифф

Тикеты 04–06.
