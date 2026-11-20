# Welcome to Defold

This project was created from the "empty" project template.

The settings in ["game.project"](defold://open?path=/game.project) are all the default. A bootstrap empty ["main.collection"](defold://open?path=/scripts/main.collection) is included.

Check out [the documentation pages](https://defold.com/learn) for examples, tutorials, manuals and API docs.

If you run into trouble, help is available in [our forum](https://forum.defold.com).

Happy Defolding!

---# defoldgame

## Локация и персонаж

Сцена `scripts/main.collection` использует обычные 3D-координаты: X и Z
задают положение на полу, Y — высоту. Персонаж начинает в (0, 0, 0).
Для расстановки перемещай объект `character` в плоскости XZ,
сохраняя Y = 0 и единичный масштаб.

Локация подключена через `scripts/location.go` →
`assets/locations/bar/bar.model` → `bar.glb`. Размер пола — 12 × 10,
высота стен — 3.2. В `bar.model` назначены три материала исходной модели:
пол, деревянный каркас и стены. Цветовые текстуры извлечены из GLB
в `assets/locations/bar/textures`; серый цвет стен сохранён в отдельной
одноцветной текстуре. `bar.material` использует стандартное освещение
Defold и повторение текстур по UV.

Положение изометрической камеры задано в коллекции,
параметры — в `scripts/isometric.camera`. Клики преобразуются в координаты
пола без ограничения границами комнаты.

## Сборка из PyCharm

В списке рядом с зелёной стрелкой выбери `Defold Build` для сборки или
`Defold Build & Run` для сборки с запуском игры. Результат сборки и ошибки
выводятся в окно Run. При ошибке сборки игра не запускается.

Конфигурации вызывают `tools/defold.ps1`, который использует Bob и Java из
установленного Defold. Открывать редактор Defold для сборки не требуется.
Результат сохраняется в `build/pycharm`, отдельно от сборки редактора.

По умолчанию установка Defold ищется по пути `../../Defold` относительно
проекта. При переносе проекта задай переменную окружения `DEFOLD_HOME`
с путём к каталогу Defold, содержащему `config` и `packages`.
Для запуска используется dmengine той же версии из локального кэша Defold.

Успешная сборка проверяет компиляцию и используемые ресурсы. Поведение игры
и ошибки, возникающие во время выполнения Lua, проверяй запуском игры.
