# Asset Credits

| Asset | Source | Author | License | Notes |
|---|---|---|---|---|
| assets/models/footballer.glb | Adobe Mixamo | Adobe | Mixamo (royalty-free) | Модель + idle/run, собрано в игровую форму .glb; сырые FBX не распространяются |

## GameplayFootball animation dataset (assets/gpf/)

- Источник: GameplayFootball, © Bastiaan Konings Schuiling. Данные взяты из форка FootballCPP (github.com/Churikov0112/FootballCPP); первоисточник-форк — github.com/vi3itor/GameplayFootball.
- Файлы: `assets/gpf/animations/**` (293 `.anim` + 3 `.anim.util`), `assets/gpf/player.object`.
- Лицензия: Apache License 2.0 — текст в `assets/gpf/LICENSE-GameplayFootball`.
- Клубные лого/киты из оригинала НЕ копировались (трейдмарки).

## Модель игрока-заглушки (assets/models/gpf_fullbody.glb)

- Источник: та же GameplayFootball, Apache 2.0 (лицензия там же). Геометрия и веса —
  `data/media/objects/players/models/fullbody.ase`, текстуры кожи, бутс и подошв —
  `data/media/objects/players/textures/{skin.jpg,shoe.jpg,shoe_sole.jpg}`.
- Собирается `tools/build_gpf_fullbody.py` из локальной копии оригинала (в репозиторий
  сам `.ase` не кладётся, только результат сборки).
- Кит (футболка/шорты/гетры) **не из оригинала**: клубные формы `databases/default/images_teams/`
  — трейдмарки, не берём. Текстура кита рисуется скриптом по раскладке, документированной
  в `databases/default/template_kit.png`.
