# Godot Top-Down Template (Шаблон для создания игр с видом сверху)

Шаблон проекта для создания игр с видом сверху (top-down) в Godot 4.3+ с поддержкой GDScript и C#.

## 📋 Содержание

- [Системные требования](#системные-требования)
- [Быстрый старт](#быстрый-старт)
- [Структура проекта](#структура-проекта)
- [Сцены и их назначение](#сцены-и-их-назначение)
- [Параметры геймплейных элементов](#параметры-геймплейных-элементов)
- [Система управления](#система-управления)
- [Физические слои](#физические-слои)
- [Расширение шаблона](#расширение-шаблона)
- [Лучшие практики](#лучшие-практики)
- [Архитектурные правила](#архитектурные-правила)
- [Решение проблем](#решение-проблем)

## Системные требования

### Для GDScript (по умолчанию):
- **Godot Engine 4.3** или новее ([скачать здесь](https://godotengine.org/download))
- **Операционная система**: Windows 7+, macOS 10.12+, или Linux
- **Видеокарта**: Поддержка OpenGL 3.3 / OpenGL ES 3.0 (большинство систем с 2012 года и новее)
- **Оперативная память**: минимум 2 ГБ
- **Место на диске**: около 50 МБ для проекта

### Для C# (опционально):
- **Godot Engine 4.3 .NET** или новее ([скачать здесь](https://godotengine.org/download)) - версия с поддержкой C#
- **.NET SDK 6.0** или новее ([скачать здесь](https://dotnet.microsoft.com/download/dotnet/6.0))
- Остальные требования такие же как для GDScript

### Рекомендуемые требования:
- **Godot Engine 4.3+** стабильная версия
- 4 ГБ оперативной памяти
- Современная видеокарта с поддержкой OpenGL 4.5+

## Быстрый старт

### Способ 1: Клонирование репозитория (рекомендуется)

1. **Установите Git** (если еще не установлен):
   - Windows: [Git for Windows](https://git-scm.com/download/win)
   - macOS: `brew install git` или [Git for macOS](https://git-scm.com/download/mac)
   - Linux: `sudo apt-get install git` (Ubuntu/Debian) или `sudo yum install git` (Fedora/CentOS)

2. **Клонируйте репозиторий**:
   ```bash
   git clone https://github.com/Jhon-Crow/godot-topdown-template.git
   cd godot-topdown-template
   ```

3. **Откройте проект в Godot**:
   - Запустите Godot Engine
   - Нажмите кнопку "Импортировать" (Import)
   - Перейдите в папку `godot-topdown-template`
   - Выберите файл `project.godot`
   - Нажмите "Импортировать и редактировать" (Import & Edit)

4. **Запустите проект**:
   - Нажмите **F5** или кнопку ▶ (Play) в правом верхнем углу редактора
   - Игра должна запуститься с главной сценой

### Способ 2: Загрузка ZIP-архива

1. **Скачайте проект**:
   - Перейдите на [главную страницу репозитория](https://github.com/Jhon-Crow/godot-topdown-template)
   - Нажмите зеленую кнопку "Code"
   - Выберите "Download ZIP"

2. **Распакуйте архив**:
   - Распакуйте скачанный ZIP-файл в удобное место
   - Рекомендуется использовать путь без кириллицы и пробелов

3. **Откройте в Godot** (см. шаги 3-4 из Способа 1)

### Первый запуск

После открытия проекта вы увидите:
- **Main.tscn** - главная сцена, которая запускается при нажатии F5
- **TestTier.tscn** - тестовый полигон для стрельбы, где можно опробовать механики

**Управление по умолчанию**:
- **WASD** или **Стрелки** - движение персонажа
- **Левая кнопка мыши** - стрельба в направлении курсора
- **ESC** - пауза / меню настроек

### Использование C# версии (опционально)

Для использования C# версии сцен:
1. Откройте проект в Godot Engine .NET (версия с поддержкой C#)
2. Откройте `scenes/levels/csharp/TestTier.tscn` и нажмите F6 для запуска
3. Или замените ссылки на сцены в вашем проекте на C# версии из папок `csharp/`

## Структура проекта

```
godot-topdown-template/
├── project.godot          # Конфигурация проекта Godot
├── GodotTopDownTemplate.csproj  # C# проект (опционально)
├── GodotTopDownTemplate.sln     # Visual Studio решение (опционально)
├── icon.svg               # Иконка проекта
│
├── scenes/                # Все игровые сцены (.tscn файлы)
│   ├── main/              # Главные сцены
│   │   └── Main.tscn      # Главная точка входа (запускается по F5)
│   ├── levels/            # Игровые уровни
│   │   ├── TestTier.tscn  # Тестовый полигон (GDScript)
│   │   └── csharp/        # C# альтернативные сцены
│   │       └── TestTier.tscn  # Тестовый полигон (C#)
│   ├── characters/        # Персонажи
│   │   ├── Player.tscn    # Игрок (GDScript)
│   │   └── csharp/        # C# альтернативные сцены
│   │       └── Player.tscn    # Игрок (C#)
│   ├── projectiles/       # Снаряды
│   │   ├── Bullet.tscn    # Пуля (GDScript)
│   │   └── csharp/        # C# альтернативные сцены
│   │       └── Bullet.tscn    # Пуля (C#)
│   ├── objects/           # Игровые объекты
│   │   ├── Target.tscn    # Мишень (GDScript)
│   │   └── csharp/        # C# альтернативные сцены
│   │       └── Target.tscn    # Мишень (C#)
│   └── ui/                # Интерфейс пользователя
│       ├── PauseMenu.tscn       # Меню паузы
│       └── ControlsMenu.tscn    # Меню переназначения клавиш
│
├── scripts/               # GDScript файлы (.gd) - основная реализация
│   ├── main.gd            # Скрипт главной сцены
│   ├── autoload/          # Автозагружаемые скрипты (синглтоны)
│   │   └── input_settings.gd  # Менеджер настроек управления
│   ├── levels/            # Скрипты уровней
│   │   └── test_tier.gd   # Скрипт тестового полигона
│   ├── characters/        # Скрипты персонажей
│   │   └── player.gd      # Движение и стрельба игрока
│   ├── projectiles/       # Скрипты снарядов
│   │   └── bullet.gd      # Поведение пули
│   ├── objects/           # Скрипты объектов
│   │   └── target.gd      # Реакция мишени на попадание
│   ├── ui/                # Скрипты интерфейса
│   │   ├── pause_menu.gd       # Контроллер меню паузы
│   │   └── controls_menu.gd    # Контроллер переназначения клавиш
│   └── utils/             # Вспомогательные скрипты
│
├── Scripts/               # C# скрипты (.cs) - опциональная реализация
│   ├── Interfaces/        # Интерфейсы
│   │   └── IDamageable.cs # Интерфейс системы урона
│   ├── AbstractClasses/   # Абстрактные классы
│   │   ├── BaseCharacter.cs # Базовый класс персонажей
│   │   └── BaseWeapon.cs    # Базовый класс оружия
│   ├── Components/        # Переиспользуемые компоненты
│   │   └── HealthComponent.cs # Компонент здоровья
│   ├── Data/              # Ресурсы данных
│   │   ├── WeaponData.cs  # Конфигурация оружия
│   │   └── BulletData.cs  # Конфигурация снарядов
│   ├── Characters/        # Реализации персонажей
│   │   └── Player.cs      # Контроллер игрока
│   ├── Projectiles/       # Реализации снарядов
│   │   └── Bullet.cs      # Снаряд
│   └── Objects/           # Игровые объекты
│       └── Enemy.cs       # Враг/мишень
│
├── assets/                # Игровые ресурсы
│   ├── sprites/           # 2D спрайты и текстуры
│   ├── audio/             # Звуковые эффекты и музыка
│   └── fonts/             # Шрифты
│
└── addons/                # Сторонние плагины Godot
```

## Сцены и их назначение

### Main.tscn - Главная сцена

**Назначение**: Точка входа в игру, запускается при нажатии F5.

**Использование**:
- Место для главного меню
- Загрузчик других сцен
- Инициализация глобальных систем

**Как изменить главную сцену**:
1. Откройте **Проект > Настройки проекта** (Project > Project Settings)
2. Перейдите в раздел **Application > Run**
3. Измените параметр **Main Scene** на нужную сцену

### TestTier.tscn - Тестовый полигон

**Назначение**: Полноценный тестовый уровень для отработки механик стрельбы и движения.

**Особенности**:
- Закрытая арена с непроходимыми стенами
- Препятствия для укрытия и тестирования движения
- Зона с мишенями для стрельбы
- Готовая настройка коллизий

**Структура сцены**:
```
TestTier
├── Environment          # Окружение
│   ├── Background      # Темно-зеленый фон (1280x720)
│   ├── Floor           # Светло-зеленый пол
│   ├── Walls           # Коричневые стены с коллизией
│   ├── Obstacles       # Препятствия
│   ├── Targets         # Красные мишени
│   └── TargetArea      # Метка зоны мишеней
├── Entities            # Сущности
│   └── Player          # Экземпляр игрока
└── CanvasLayer         # UI
    └── UI              # HUD с названием уровня
```

**Как запустить**:
1. Откройте `scenes/levels/TestTier.tscn` в редакторе
2. Нажмите **F6** для запуска текущей сцены
3. Используйте WASD для движения и ЛКМ для стрельбы

### Player.tscn - Игрок

**Назначение**: Управляемый персонаж с плавным физическим движением.

**Компоненты**:
- **CharacterBody2D** - корневой узел для физического движения
- **CollisionShape2D** - круглая коллизия (радиус 16 пикселей)
- **Sprite2D** - спрайт персонажа (можно заменить на свой)
- **Camera2D** - камера, плавно следующая за игроком

**Система движения**: Основана на ускорении и трении для плавного управления без рывков. Диагональное движение нормализовано для предотвращения повышенной скорости.

**Система стрельбы**: Игрок стреляет пулями в направлении курсора мыши при нажатии ЛКМ. Пули создаются со смещением от центра игрока в направлении стрельбы.

### Bullet.tscn - Пуля

**Назначение**: Снаряд для системы стрельбы.

**Компоненты**:
- **Area2D** - корневой узел для детектирования столкновений
- **CircleShape2D** - точная форма попадания (радиус 4 пикселя)
- **Sprite2D** - желтый спрайт пули (можно заменить)

**Поведение**:
- Движется с постоянной скоростью в заданном направлении
- Автоматически уничтожается при столкновении
- Удаляется через заданное время жизни (защита от бесконечных пуль)

### Target.tscn - Мишень

**Назначение**: Стреляемая мишень, реагирующая на попадания.

**Компоненты**:
- **Area2D** - корневой узел для детектирования попаданий
- **Sprite2D** - визуальный спрайт мишени

**Поведение**:
- Меняет цвет при попадании (красный → зеленый)
- Автоматически восстанавливается после задержки
- Опционально может уничтожаться при попадании

### PauseMenu.tscn - Меню паузы

**Назначение**: Меню паузы, появляющееся при нажатии ESC.

**Функции**:
- **Resume** (Продолжить) - возврат к игре
- **Controls** (Управление) - открытие меню переназначения клавиш
- **Quit** (Выход) - выход из игры

**Как работает**:
- Ставит игру на паузу (`get_tree().paused = true`)
- Открывается по нажатию ESC во время игры
- Встроено в TestTier для демонстрации

### ControlsMenu.tscn - Меню управления

**Назначение**: Интерфейс переназначения клавиш управления.

**Функции**:
- Отображает все доступные для переназначения действия
- Показывает текущие назначенные клавиши
- Позволяет переназначить любую клавишу
- Детектирует конфликты клавиш
- Сохраняет настройки в файл `user://input_settings.cfg`

**Переназначаемые действия**:
| Действие | Клавиша по умолчанию | Описание |
|----------|---------------------|----------|
| Move Up | W | Движение вверх |
| Move Down | S | Движение вниз |
| Move Left | A | Движение влево |
| Move Right | D | Движение вправо |
| Shoot | Левая кнопка мыши | Стрельба к курсору |
| Pause | Escape | Пауза/меню |

**Как использовать**:
1. Нажмите ESC для открытия меню паузы
2. Нажмите "Controls" для открытия меню управления
3. Кликните на любую кнопку действия
4. Нажмите желаемую новую клавишу (или ESC для отмены)
5. Нажмите "Apply" для сохранения изменений
6. Нажмите "Reset" для сброса к настройкам по умолчанию

## Параметры геймплейных элементов

### Player (Игрок) - scripts/characters/player.gd

Все параметры настраиваются в **Инспекторе** (Inspector) при выборе узла Player в сцене.

#### Параметры движения

| Параметр | Тип | По умолчанию | Описание | Влияние на геймплей |
|----------|-----|--------------|----------|---------------------|
| `max_speed` | float | 200.0 | Максимальная скорость движения (пикселей/секунду) | Чем выше значение, тем быстрее бегает персонаж. 200 - умеренная скорость, 400+ - очень быстро |
| `acceleration` | float | 1200.0 | Скорость разгона до максимальной скорости | Чем выше, тем резче персонаж начинает движение. Низкие значения (300-500) = плавный разгон, высокие (1500+) = мгновенный старт |
| `friction` | float | 1000.0 | Скорость торможения при отпускании клавиш | Чем выше, тем резче персонаж останавливается. Низкие значения (200-400) = скольжение, высокие (1500+) = мгновенная остановка |

**Примеры настроек для разных стилей игр**:

- **Аркадный шутер** (резкое управление):
  - `max_speed = 250`
  - `acceleration = 2000`
  - `friction = 1500`

- **Реалистичное управление** (инерция):
  - `max_speed = 180`
  - `acceleration = 400`
  - `friction = 300`

- **Быстрый экшен** (высокая мобильность):
  - `max_speed = 350`
  - `acceleration = 1800`
  - `friction = 1200`

#### Параметры стрельбы

| Параметр | Тип | По умолчанию | Описание | Влияние на геймплей |
|----------|-----|--------------|----------|---------------------|
| `bullet_scene` | PackedScene | Bullet.tscn | Сцена пули для создания | Можно заменить на свою сцену пули с другим поведением/внешним видом |
| `bullet_spawn_offset` | float | 20.0 | Смещение точки появления пули от центра игрока (пикселей) | Определяет, где появляется пуля. 20 = перед игроком, 0 = в центре игрока |

**Как изменить**:
1. Откройте сцену Player.tscn или уровень с игроком
2. Выберите узел Player в дереве сцены
3. В панели Inspector справа найдите раздел "Script Variables"
4. Измените нужные значения
5. Нажмите Ctrl+S для сохранения сцены

### Bullet (Пуля) - scripts/projectiles/bullet.gd

| Параметр | Тип | По умолчанию | Описание | Влияние на геймплей |
|----------|-----|--------------|----------|---------------------|
| `speed` | float | 600.0 | Скорость полета пули (пикселей/секунду) | Чем выше, тем быстрее летит пуля. 300 = медленно, 1000+ = очень быстро |
| `lifetime` | float | 3.0 | Максимальное время жизни пули (секунд) | Через это время пуля автоматически уничтожается, даже если ни во что не попала |

**Переменная (устанавливается из кода)**:
- `direction: Vector2` - направление движения пули (устанавливается игроком при выстреле)

**Примеры настроек**:

- **Медленная пуля** (как файрбол):
  - `speed = 300`
  - `lifetime = 5.0`

- **Быстрая пуля** (как лазер):
  - `speed = 1200`
  - `lifetime = 2.0`

- **Обычная пуля**:
  - `speed = 600`
  - `lifetime = 3.0`

### Target (Мишень) - scripts/objects/target.gd

| Параметр | Тип | По умолчанию | Описание | Влияние на геймплей |
|----------|-----|--------------|----------|---------------------|
| `hit_color` | Color | Зеленый | Цвет мишени при попадании | Визуальная индикация попадания. По умолчанию зеленый (0.2, 0.8, 0.2) |
| `normal_color` | Color | Красный | Обычный цвет мишени | Цвет в исходном состоянии. По умолчанию красный (0.9, 0.2, 0.2) |
| `destroy_on_hit` | bool | false | Уничтожать мишень при попадании | false = мишень восстанавливается, true = мишень исчезает |
| `respawn_delay` | float | 2.0 | Задержка перед восстановлением/уничтожением (секунд) | Время, через которое мишень либо восстанавливается (если destroy_on_hit = false), либо уничтожается (если true) |

**Примеры настроек**:

- **Тренировочная мишень** (восстанавливается):
  - `destroy_on_hit = false`
  - `respawn_delay = 2.0`
  - Мишень можно стрелять многократно

- **Разрушаемая мишень**:
  - `destroy_on_hit = true`
  - `respawn_delay = 1.0`
  - Мишень исчезает после попадания

- **Быстро восстанавливающаяся мишень**:
  - `destroy_on_hit = false`
  - `respawn_delay = 0.5`
  - Для интенсивной практики стрельбы

### InputSettings (Настройки управления) - scripts/autoload/input_settings.gd

Это синглтон (autoload), который автоматически загружается при старте игры.

**Константы**:
- `SETTINGS_PATH = "user://input_settings.cfg"` - путь к файлу сохранения настроек

**Переменные**:
- `remappable_actions: Array[String]` - список действий, доступных для переназначения

**Методы для использования в других скриптах**:

```gdscript
# Получить отображаемое имя действия
InputSettings.get_action_display_name("move_up")  # Вернет "Move Up"

# Получить текущую назначенную клавишу
InputSettings.get_action_key_name("shoot")  # Вернет "Left Mouse"

# Установить новую клавишу для действия
var new_event = InputEventKey.new()
new_event.physical_keycode = KEY_SPACE
InputSettings.set_action_key("shoot", new_event)

# Сбросить все настройки к значениям по умолчанию
InputSettings.reset_to_defaults()

# Сохранить настройки в файл
InputSettings.save_settings()

# Проверить конфликт клавиш
var conflict = InputSettings.check_key_conflict(event, "move_up")
if conflict != "":
    print("Конфликт с действием: ", conflict)
```

**Сигналы**:
- `controls_changed` - испускается при изменении настроек управления

## Система управления

### Настроенные действия ввода (Input Actions)

Все действия настраиваются в **Проект > Настройки проекта > Карта ввода** (Project > Project Settings > Input Map).

| Действие | Клавиши по умолчанию | Назначение |
|----------|----------------------|------------|
| `move_up` | W, Стрелка вверх | Движение персонажа вверх |
| `move_down` | S, Стрелка вниз | Движение персонажа вниз |
| `move_left` | A, Стрелка влево | Движение персонажа влево |
| `move_right` | D, Стрелка вправо | Движение персонажа вправо |
| `shoot` | Левая кнопка мыши | Стрельба к курсору |
| `pause` | Escape | Открытие меню паузы |

### Как добавить новое действие

**Пример**: Добавим действие для бега (sprint)

1. **В настройках проекта**:
   - Откройте **Проект > Настройки проекта** (Project > Project Settings)
   - Перейдите на вкладку **Карта ввода** (Input Map)
   - Введите имя действия `sprint` в поле в верхней части
   - Нажмите **Добавить** (Add)
   - Кликните на "+" справа от `sprint`
   - Нажмите клавишу Shift
   - Нажмите **OK**

2. **В коде игрока** (scripts/characters/player.gd):
   ```gdscript
   # Добавьте параметр
   @export var sprint_multiplier: float = 1.5

   # Измените метод _physics_process
   func _physics_process(delta: float) -> void:
       var input_direction := _get_input_direction()

       # Определяем текущую максимальную скорость
       var current_max_speed = max_speed
       if Input.is_action_pressed("sprint"):
           current_max_speed *= sprint_multiplier

       if input_direction != Vector2.ZERO:
           velocity = velocity.move_toward(input_direction * current_max_speed, acceleration * delta)
       else:
           velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

       move_and_slide()
   ```

3. **Добавьте в переназначаемые действия** (опционально):
   - Откройте `scripts/autoload/input_settings.gd`
   - Добавьте `"sprint"` в массив `remappable_actions`
   - Добавьте обработку в методе `get_action_display_name`:
   ```gdscript
   "sprint":
       return "Sprint"
   ```

## Физические слои

Godot использует слои коллизий для определения того, какие объекты могут взаимодействовать друг с другом.

### Настроенные слои

Слои настраиваются в **Проект > Настройки проекта > Имена слоев > 2D физика** (Project > Project Settings > Layer Names > 2D Physics).

| Слой | Название | Назначение | Примеры |
|------|----------|------------|---------|
| 1 | player | Игрок | Персонаж игрока |
| 2 | enemies | Враги | Враждебные NPC, монстры |
| 3 | obstacles | Препятствия | Стены, барьеры, непроходимые объекты |
| 4 | pickups | Подбираемые предметы | Монеты, здоровье, оружие |
| 5 | projectiles | Снаряды | Пули, ракеты, магические снаряды |
| 6 | targets | Мишени | Стреляемые мишени, интерактивные объекты |

### Как работают слои

Каждый физический объект (CharacterBody2D, Area2D, StaticBody2D и т.д.) имеет:

1. **Collision Layer** (Слой коллизии) - на каком слое находится объект
2. **Collision Mask** (Маска коллизии) - с какими слоями объект может взаимодействовать

**Пример настройки игрока**:
- **Collision Layer** = 1 (player) - игрок находится на слое игрока
- **Collision Mask** = 4 (obstacles) + 8 (pickups) - игрок видит препятствия и подбираемые предметы

**Пример настройки пули**:
- **Collision Layer** = 5 (projectiles) - пуля находится на слое снарядов
- **Collision Mask** = 4 (obstacles) + 32 (targets) - пуля видит стены и мишени

### Как настроить коллизии для нового объекта

**Пример**: Создаем подбираемую монету

1. Создайте сцену с узлом Area2D
2. Выберите узел Area2D
3. В Inspector найдите раздел **Collision**
4. **Collision Layer**: Включите только слой 4 (pickups)
5. **Collision Mask**: Включите только слой 1 (player) - монета будет детектировать игрока

**В скрипте монеты**:
```gdscript
extends Area2D

func _ready() -> void:
    # Слушаем вход в область
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
    # Если это игрок (находится на слое player)
    if body is CharacterBody2D:
        print("Игрок подобрал монету!")
        queue_free()  # Удаляем монету
```

### Таблица взаимодействий

| Объект | Слой | Маска | Взаимодействует с |
|--------|------|-------|-------------------|
| Игрок | 1 (player) | 4 (obstacles) + 8 (pickups) | Стены, предметы |
| Враг | 2 (enemies) | 1 (player) + 4 (obstacles) | Игрок, стены |
| Стена | 3 (obstacles) | - | Ничего (статичная) |
| Монета | 4 (pickups) | 1 (player) | Игрок |
| Пуля | 5 (projectiles) | 4 (obstacles) + 32 (targets) | Стены, мишени |
| Мишень | 6 (targets) | 16 (projectiles) | Пули |

## Расширение шаблона

### Добавление нового уровня

**Шаг за шагом**:

1. **Создайте файл сцены**:
   - Кликните правой кнопкой на папку `scenes/levels/`
   - Выберите **Создать новую сцену** (New Scene)
   - Сохраните как `scenes/levels/MyLevel.tscn`

2. **Настройте структуру**:
   ```
   MyLevel (Node2D)
   ├── Environment (Node2D)
   │   ├── Background (Sprite2D/ColorRect)
   │   ├── Walls (Node2D)
   │   │   └── Wall1 (StaticBody2D + CollisionShape2D)
   │   └── Objects (Node2D)
   ├── Entities (Node2D)
   │   └── Player (экземпляр Player.tscn)
   └── CanvasLayer
       └── UI (Control)
   ```

3. **Создайте скрипт уровня**:
   - Создайте файл `scripts/levels/my_level.gd`
   - Прикрепите к корневому узлу MyLevel

   ```gdscript
   extends Node2D
   ## My custom game level

   func _ready() -> void:
       print("Level loaded!")
       # Инициализация уровня

   func _process(delta: float) -> void:
       # Логика уровня
       pass
   ```

4. **Добавьте игрока**:
   - Перетащите `scenes/characters/Player.tscn` в узел Entities
   - Установите его position в желаемую стартовую позицию

5. **Добавьте стены**:
   - Создайте StaticBody2D под Walls
   - Добавьте CollisionShape2D
   - Установите **Collision Layer** = 3 (obstacles)
   - Добавьте визуальный спрайт или ColorRect

6. **Запустите уровень**:
   - Откройте MyLevel.tscn
   - Нажмите F6 для запуска текущей сцены

### Добавление нового персонажа (врага)

**Шаг за шагом**:

1. **Создайте сцену**:
   - Создайте `scenes/characters/Enemy.tscn`
   - Корневой узел: CharacterBody2D

2. **Добавьте компоненты**:
   ```
   Enemy (CharacterBody2D)
   ├── CollisionShape2D (форма коллизии)
   ├── Sprite2D (визуальный спрайт)
   └── DetectionArea (Area2D) - для детектирования игрока
       └── CollisionShape2D
   ```

3. **Настройте коллизии**:
   - **Enemy (CharacterBody2D)**:
     - Collision Layer: 2 (enemies)
     - Collision Mask: 1 (player) + 4 (obstacles)
   - **DetectionArea (Area2D)**:
     - Collision Layer: 2 (enemies)
     - Collision Mask: 1 (player)

4. **Создайте скрипт** `scripts/characters/enemy.gd`:
   ```gdscript
   extends CharacterBody2D
   ## Basic enemy that follows the player

   @export var move_speed: float = 100.0
   @export var detection_range: float = 200.0

   @onready var detection_area: Area2D = $DetectionArea

   var player: CharacterBody2D = null

   func _ready() -> void:
       # Настраиваем зону детектирования
       detection_area.body_entered.connect(_on_detection_entered)
       detection_area.body_exited.connect(_on_detection_exited)

   func _physics_process(delta: float) -> void:
       if player:
           # Двигаемся к игроку
           var direction = (player.global_position - global_position).normalized()
           velocity = direction * move_speed
           move_and_slide()

   func _on_detection_entered(body: Node2D) -> void:
       if body is CharacterBody2D and body.collision_layer & 1:  # Проверяем слой player
           player = body

   func _on_detection_exited(body: Node2D) -> void:
       if body == player:
           player = null
   ```

5. **Используйте на уровне**:
   - Перетащите Enemy.tscn на ваш уровень
   - Настройте параметры в Inspector

### Добавление нового типа снаряда

**Пример**: Создадим медленный огненный шар

1. **Создайте сцену**:
   - Скопируйте `scenes/projectiles/Bullet.tscn`
   - Сохраните как `scenes/projectiles/Fireball.tscn`

2. **Измените визуал**:
   - Измените спрайт на красный/оранжевый
   - Увеличьте размер коллизии (например, радиус 8)

3. **Создайте скрипт** `scripts/projectiles/fireball.gd`:
   ```gdscript
   extends Area2D
   ## Fireball projectile with explosion effect

   @export var speed: float = 300.0  # Медленнее обычной пули
   @export var lifetime: float = 5.0
   @export var explosion_radius: float = 50.0

   var direction: Vector2 = Vector2.RIGHT
   var _time_alive: float = 0.0

   func _ready() -> void:
       body_entered.connect(_on_body_entered)
       area_entered.connect(_on_area_entered)

   func _physics_process(delta: float) -> void:
       position += direction * speed * delta
       _time_alive += delta
       if _time_alive >= lifetime:
           _explode()

   func _on_body_entered(body: Node2D) -> void:
       _explode()

   func _on_area_entered(area: Area2D) -> void:
       if area.has_method("on_hit"):
           area.on_hit()
       _explode()

   func _explode() -> void:
       # Создаем область взрыва
       var explosion_area = Area2D.new()
       var shape = CircleShape2D.new()
       shape.radius = explosion_radius
       var collision = CollisionShape2D.new()
       collision.shape = shape
       explosion_area.add_child(collision)
       explosion_area.global_position = global_position
       get_tree().current_scene.add_child(explosion_area)

       # Находим всех врагов в радиусе
       explosion_area.collision_mask = 2  # enemies layer
       await get_tree().process_frame
       var bodies = explosion_area.get_overlapping_bodies()
       for body in bodies:
           if body.has_method("take_damage"):
               body.take_damage(50)

       explosion_area.queue_free()
       queue_free()
   ```

4. **Используйте в игроке**:
   - Откройте Player.tscn
   - В Inspector измените `bullet_scene` на Fireball.tscn

### Добавление автозагрузки (Autoload/Singleton)

Автозагрузки используются для глобальных систем (менеджеры, настройки и т.д.)

**Пример**: Создадим менеджер счета

1. **Создайте скрипт** `scripts/autoload/score_manager.gd`:
   ```gdscript
   extends Node
   ## Global score manager

   signal score_changed(new_score: int)

   var score: int = 0:
       set(value):
           score = value
           score_changed.emit(score)

   func add_score(amount: int) -> void:
       score += amount

   func reset_score() -> void:
       score = 0

   func get_score() -> int:
       return score
   ```

2. **Добавьте в автозагрузку**:
   - Откройте **Проект > Настройки проекта** (Project > Project Settings)
   - Перейдите на вкладку **Autoload**
   - Нажмите на значок папки справа
   - Выберите `scripts/autoload/score_manager.gd`
   - В поле **Node Name** введите `ScoreManager`
   - Нажмите **Добавить** (Add)

3. **Используйте в любом скрипте**:
   ```gdscript
   # В скрипте врага при уничтожении
   func die() -> void:
       ScoreManager.add_score(100)
       queue_free()

   # В UI для отображения счета
   func _ready() -> void:
       ScoreManager.score_changed.connect(_on_score_changed)
       _update_score_label()

   func _on_score_changed(new_score: int) -> void:
       _update_score_label()

   func _update_score_label() -> void:
       $ScoreLabel.text = "Score: " + str(ScoreManager.get_score())
   ```

### Добавление UI элемента

**Пример**: Создадим полоску здоровья

1. **Создайте сцену** `scenes/ui/HealthBar.tscn`:
   ```
   HealthBar (Control)
   ├── Background (ColorRect) - темный фон
   └── Bar (ProgressBar) - индикатор здоровья
   ```

2. **Создайте скрипт** `scripts/ui/health_bar.gd`:
   ```gdscript
   extends Control
   ## Health bar UI component

   @onready var progress_bar: ProgressBar = $Bar

   func _ready() -> void:
       update_health(100, 100)

   func update_health(current: int, maximum: int) -> void:
       progress_bar.max_value = maximum
       progress_bar.value = current

       # Меняем цвет в зависимости от здоровья
       var health_percent = float(current) / float(maximum)
       if health_percent > 0.5:
           progress_bar.modulate = Color.GREEN
       elif health_percent > 0.25:
           progress_bar.modulate = Color.YELLOW
       else:
           progress_bar.modulate = Color.RED
   ```

3. **Добавьте здоровье игроку** (в scripts/characters/player.gd):
   ```gdscript
   @export var max_health: int = 100
   var current_health: int = max_health

   signal health_changed(current: int, maximum: int)

   func _ready() -> void:
       # ... существующий код
       health_changed.emit(current_health, max_health)

   func take_damage(amount: int) -> void:
       current_health -= amount
       if current_health < 0:
           current_health = 0
       health_changed.emit(current_health, max_health)

       if current_health <= 0:
           die()

   func die() -> void:
       print("Player died!")
       # Логика смерти
   ```

4. **Добавьте на уровень**:
   - Добавьте HealthBar.tscn как дочерний узел CanvasLayer
   - В скрипте уровня свяжите игрока и health bar:
   ```gdscript
   @onready var player: CharacterBody2D = $Entities/Player
   @onready var health_bar: Control = $CanvasLayer/HealthBar

   func _ready() -> void:
       player.health_changed.connect(health_bar.update_health)
   ```

### Добавление прогрессбара ограниченному активируемому предмету

Если активируемый предмет имеет ограниченное использование (заряды или время), над игроком должен отображаться прогрессбар. Компонент `ActiveItemProgressBar` поддерживает два режима:

- **Сегментированный** (`SEGMENTED`) — для предметов с ограниченным количеством зарядов (делениями). Пример: наручи телепортации (6 зарядов).
- **Непрерывный** (`CONTINUOUS`) — для предметов с ограниченным временем использования. Пример: предмет с таймером.

#### Правила отображения

1. Если предмет имеет ограниченные заряды — показывать сегментированный прогрессбар с количеством делений = количество зарядов.
2. Если предмет имеет ограниченное время — показывать непрерывный прогрессбар.
3. Во время активного использования (работает таймер предмета) — постоянно отображать прогрессбар.
4. Если предмет с ограниченными зарядами (дискретные активации) — прогрессбар всегда виден пока предмет экипирован.
5. **Предпочтительно не показывать отдельный прогрессбар если есть возможность использовать встроенный визуальный эффект.** Например, если у предмета есть собственный визуальный элемент (луч, щит, ореол), предупреждение об окончании времени лучше реализовать через мигание этого элемента, а не через дополнительный прогрессбар. Пример: очки траектории — луч мигает последние 2 секунды вместо отображения таймер-бара (Issue #1049).

#### Использование компонента (GDScript)

```gdscript
# В скрипте игрока или предмета:

# 1. Показать сегментированный прогрессбар (заряды)
_show_active_item_charge_bar(current_charges, max_charges)

# 2. Показать непрерывный прогрессбар (время)
_show_active_item_timer_bar(time_remaining, max_time)

# 3. Обновить значение
_update_active_item_bar(new_value)

# 4. Скрыть прогрессбар
_hide_active_item_bar()
```

#### Использование в C# (Player.cs)

Для C# версии игрока прогрессбар рисуется через `_Draw()`:

```csharp
// В _Draw():
if (_teleportBracersEquipped)
{
    DrawTeleportChargeBar();
}
```

Метод `DrawTeleportChargeBar()` рисует сегментированную полоску зарядов над игроком. Цвет меняется в зависимости от оставшихся зарядов:
- **Зелёный** — больше 50% зарядов
- **Жёлтый** — от 25% до 50%
- **Красный** — менее 25%

#### Пример: Добавление нового предмета с зарядами

1. Добавьте тип в `ActiveItemType` enum в `active_item_manager.gd`
2. Добавьте данные предмета в `ACTIVE_ITEM_DATA`
3. В скрипте игрока инициализируйте прогрессбар при экипировке:
   ```gdscript
   func _init_my_item() -> void:
       # ... логика инициализации ...
       _show_active_item_charge_bar(max_charges, max_charges)

   func _use_item_charge() -> void:
       current_charges -= 1
       _update_active_item_bar(float(current_charges))
   ```
4. Напишите тесты в `tests/unit/`

## Лучшие практики

### Именование файлов и папок

1. **Используйте snake_case** для всех файлов и папок:
   ✅ `player_character.gd`, `main_menu.tscn`
   ❌ `PlayerCharacter.gd`, `MainMenu.tscn`

2. **Группируйте по типу и функции**:
   ```
   scenes/
   ├── characters/    # Все персонажи
   ├── levels/        # Все уровни
   └── ui/            # Весь интерфейс

   scripts/
   ├── characters/    # Скрипты персонажей
   ├── levels/        # Скрипты уровней
   └── ui/            # Скрипты UI
   ```

3. **Соответствие имен**: Файлы сцен и скриптов должны соответствовать:
   - Сцена: `scenes/characters/Player.tscn`
   - Скрипт: `scripts/characters/player.gd`

### Организация кода

1. **Используйте @export для настраиваемых параметров**:
   ```gdscript
   # ✅ Хорошо - параметр виден в Inspector
   @export var max_speed: float = 200.0

   # ❌ Плохо - параметр спрятан в коде
   var max_speed: float = 200.0
   ```

2. **Документируйте с помощью комментариев ##**:
   ```gdscript
   extends CharacterBody2D
   ## Player character controller for top-down movement.
   ##
   ## This script handles player movement, shooting, and health.

   ## Maximum movement speed in pixels per second.
   @export var max_speed: float = 200.0
   ```

3. **Порядок в скрипте**:
   ```gdscript
   # 1. Extends
   extends CharacterBody2D

   # 2. Документация класса
   ## Class documentation

   # 3. Сигналы
   signal health_changed(value: int)

   # 4. Экспортируемые переменные
   @export var max_speed: float = 200.0

   # 5. Публичные переменные
   var velocity: Vector2 = Vector2.ZERO

   # 6. Приватные переменные (с подчеркиванием)
   var _is_dead: bool = false

   # 7. @onready переменные
   @onready var sprite: Sprite2D = $Sprite2D

   # 8. Встроенные методы (_ready, _process и т.д.)
   func _ready() -> void:
       pass

   # 9. Публичные методы
   func take_damage(amount: int) -> void:
       pass

   # 10. Приватные методы (с подчеркиванием)
   func _calculate_movement() -> Vector2:
       pass
   ```

4. **Используйте типизацию**:
   ```gdscript
   # ✅ Хорошо - явные типы
   var health: int = 100
   var speed: float = 200.0
   var player: CharacterBody2D = null

   func get_direction() -> Vector2:
       return Vector2.ZERO

   # ❌ Плохо - без типов
   var health = 100
   var speed = 200.0

   func get_direction():
       return Vector2.ZERO
   ```

### Работа со сценами

1. **Модульная структура**:
   ```
   Level
   ├── Environment  # Все статическое окружение
   ├── Entities     # Все динамические сущности
   └── UI           # Весь интерфейс
   ```

2. **Используйте инстансы сцен** вместо дублирования:
   - Создайте сцену врага один раз
   - Размещайте инстансы этой сцены на уровнях
   - Изменения в оригинальной сцене автоматически применятся везде

3. **Используйте @onready** для ссылок на узлы:
   ```gdscript
   # ✅ Хорошо - загружается в _ready автоматически
   @onready var sprite: Sprite2D = $Sprite2D
   @onready var collision: CollisionShape2D = $CollisionShape2D

   # ❌ Плохо - нужно вручную загружать в _ready
   var sprite: Sprite2D
   var collision: CollisionShape2D

   func _ready() -> void:
       sprite = $Sprite2D
       collision = $CollisionShape2D
   ```

### Физика и коллизии

1. **CharacterBody2D для управляемых персонажей**:
   - Используйте для игрока, врагов
   - Используйте `move_and_slide()` для плавного движения
   - Автоматическая обработка столкновений

2. **Area2D для триггеров и снарядов**:
   - Используйте для пуль, зон урона, подбираемых предметов
   - Детектирует вход/выход других объектов
   - Не блокирует движение

3. **StaticBody2D для неподвижных объектов**:
   - Используйте для стен, препятствий
   - Не движется, только блокирует

4. **Правильно настраивайте слои**:
   - Объект должен быть на ОДНОМ слое (Layer)
   - Объект может видеть НЕСКОЛЬКО слоев (Mask)

### Оптимизация

1. **Используйте процессы по необходимости**:
   ```gdscript
   # Если не нужен _process, не создавайте его
   # Выключайте обработку, когда не нужно
   func disable_processing() -> void:
       set_process(false)
       set_physics_process(false)
   ```

2. **Удаляйте ненужные объекты**:
   ```gdscript
   # Пули, эффекты и т.д. должны удалять себя
   func _on_lifetime_exceeded() -> void:
       queue_free()  # ✅ Безопасное удаление
   ```

3. **Используйте object pooling для частых объектов**:
   - Вместо создания/удаления пуль каждый раз
   - Создайте пул пуль и переиспользуйте их

## Архитектурные правила

### Разделение ответственности

1. **Один скрипт = одна ответственность**:
   - `player.gd` - только логика игрока
   - `bullet.gd` - только логика пули
   - `game_manager.gd` - только управление игрой

2. **Используйте сигналы для коммуникации**:
   ```gdscript
   # ✅ Хорошо - слабая связь через сигналы
   # В player.gd
   signal died

   func take_damage(amount: int) -> void:
       health -= amount
       if health <= 0:
           died.emit()

   # В game_manager.gd
   func _ready() -> void:
       player.died.connect(_on_player_died)

   # ❌ Плохо - прямая зависимость
   # В player.gd
   func take_damage(amount: int) -> void:
       health -= amount
       if health <= 0:
           GameManager.player_died()  # Прямая связь
   ```

3. **Автозагрузки для глобальных систем**:
   - Используйте для менеджеров (GameManager, ScoreManager)
   - Используйте для настроек (InputSettings, AudioSettings)
   - НЕ используйте для обычной игровой логики

### Иерархия сцен

1. **Принцип композиции**:
   ```
   Player
   ├── Sprite2D          # Визуал
   ├── CollisionShape2D  # Физика
   ├── HealthComponent   # Компонент здоровья (можно переиспользовать)
   └── WeaponComponent   # Компонент оружия (можно переиспользовать)
   ```

2. **Переиспользуемые компоненты**:
   - Создайте `scenes/components/HealthComponent.tscn`
   - Используйте в игроке, врагах и т.д.
   - Изменения в компоненте затронут все объекты

### Управление состоянием

1. **Используйте перечисления (enum) для состояний**:
   ```gdscript
   enum State {
       IDLE,
       MOVING,
       ATTACKING,
       DEAD
   }

   var current_state: State = State.IDLE

   func _physics_process(delta: float) -> void:
       match current_state:
           State.IDLE:
               _process_idle(delta)
           State.MOVING:
               _process_moving(delta)
           State.ATTACKING:
               _process_attacking(delta)
           State.DEAD:
               return  # Ничего не делаем
   ```

2. **Машина состояний для сложного поведения**:
   - Создайте отдельные узлы для каждого состояния
   - Переключайтесь между ними через менеджер

### Данные и конфигурация

1. **Используйте Resources для данных**:
   ```gdscript
   # weapon_data.gd
   extends Resource
   class_name WeaponData

   @export var weapon_name: String
   @export var damage: int
   @export var fire_rate: float
   @export var bullet_scene: PackedScene
   ```

   Создайте `.tres` файлы в `assets/data/weapons/`:
   - `pistol.tres`
   - `shotgun.tres`
   - `rifle.tres`

2. **Конфигурационные файлы для настроек**:
   ```gdscript
   # Сохранение настроек
   var config = ConfigFile.new()
   config.set_value("graphics", "fullscreen", true)
   config.set_value("audio", "master_volume", 0.8)
   config.save("user://settings.cfg")

   # Загрузка настроек
   var config = ConfigFile.new()
   config.load("user://settings.cfg")
   var fullscreen = config.get_value("graphics", "fullscreen", false)
   ```

### Обработка ошибок

1. **Проверяйте на null**:
   ```gdscript
   func shoot() -> void:
       if bullet_scene == null:
           push_error("Bullet scene not set!")
           return

       var bullet = bullet_scene.instantiate()
       # ...
   ```

2. **Используйте assert для проверки условий**:
   ```gdscript
   func _ready() -> void:
       assert(max_speed > 0, "Max speed must be positive!")
       assert(sprite != null, "Sprite node not found!")
   ```

### Производительность

1. **Группируйте объекты**:
   ```gdscript
   # Добавьте объекты в группу
   add_to_group("enemies")
   add_to_group("damageable")

   # Найдите все объекты группы
   var enemies = get_tree().get_nodes_in_group("enemies")
   for enemy in enemies:
       enemy.take_damage(10)
   ```

2. **Используйте caching для частых операций**:
   ```gdscript
   # ❌ Плохо - поиск каждый кадр
   func _process(delta: float) -> void:
       var player = get_tree().get_first_node_in_group("player")
       look_at(player.position)

   # ✅ Хорошо - кешируем ссылку
   var _player: Node2D = null

   func _ready() -> void:
       _player = get_tree().get_first_node_in_group("player")

   func _process(delta: float) -> void:
       if _player:
           look_at(_player.position)
   ```

### Ограничения размера скриптов

Для поддержания читаемости и модульности кода:
- **Целевой максимум**: 800 строк на скрипт
- **Порог предупреждения**: 800 строк (рекомендуется рефакторинг)
- **Идеально**: менее 300 строк на скрипт

При превышении этих лимитов рассмотрите извлечение функциональности в переиспользуемые компоненты.

> **Примечание**: Некоторые существующие скрипты (например, `enemy.gd`) превышают эти лимиты из-за исторической сложности.
> Директория `scripts/components/` предоставляет паттерны переиспользуемых компонентов для постепенного рефакторинга.
> См. `HealthComponent`, `AmmoComponent`, `VisionComponent` и `CoverComponent` в качестве примеров.

### Компонентная архитектура

Проект использует компонентную архитектуру для переиспользуемой функциональности:

```
scripts/
├── components/           # Переиспользуемые компоненты
│   ├── health_component.gd      # Управление здоровьем
│   ├── ammo_component.gd        # Система боеприпасов
│   ├── vision_component.gd      # Обнаружение прямой видимости
│   └── cover_component.gd       # Обнаружение/оценка укрытия
├── ai/
│   ├── states/           # Состояния машины состояний ИИ
│   │   ├── enemy_state.gd       # Базовый класс состояния
│   │   ├── idle_state.gd        # Поведение ожидания/патруля
│   │   └── pursuing_state.gd    # Поведение преследования
│   ├── goap_action.gd    # Базовый класс действий GOAP
│   ├── goap_planner.gd   # Планировщик GOAP
│   └── enemy_actions.gd  # Специфичные для врагов действия GOAP
└── autoload/             # Глобальные синглтоны
```

### Паттерн машины состояний ИИ

Для сложного поведения ИИ используйте паттерн машины состояний:

```gdscript
class_name IdleState
extends EnemyState

func enter() -> void:
    # Вызывается при входе в это состояние
    pass

func process(delta: float) -> EnemyState:
    # Возвращает новое состояние для перехода, или null чтобы остаться
    if enemy._can_see_player:
        return CombatState.new(enemy)
    return null

func exit() -> void:
    # Вызывается при выходе из этого состояния
    pass
```

### CI проверки архитектуры

Проект включает автоматические проверки архитектуры (`.github/workflows/architecture-check.yml`):

- **Лимиты размера скриптов**: Проверяет максимум 800 строк на скрипт
- **Объявления class_name**: Убеждается, что компоненты правильно именованы
- **Структура папок**: Проверяет наличие необходимых директорий
- **Соглашения именования**: Проверяет snake_case для GDScript файлов
- **Паттерны связанности**: Предупреждает о потенциально тесной связанности

## Решение проблем

### Проект не открывается

**Проблема**: Godot не может открыть проект

**Решения**:
1. Убедитесь, что используете Godot 4.3 или новее
2. Проверьте, что файл `project.godot` существует
3. Попробуйте удалить папку `.godot` и переоткрыть проект
4. Проверьте права доступа к папке проекта

### Коллизии не работают

**Проблема**: Объекты проходят сквозь стены

**Решения**:
1. Проверьте Collision Layer и Collision Mask
2. Убедитесь, что у объектов есть CollisionShape2D
3. Убедитесь, что форма коллизии не пустая
4. Для CharacterBody2D используйте `move_and_slide()`

### Пули не попадают в мишени

**Проблема**: Пули пролетают сквозь мишени

**Решения**:
1. Пуля (Area2D):
   - Collision Layer: 5 (projectiles)
   - Collision Mask: 6 (targets) + 4 (obstacles)
2. Мишень (Area2D):
   - Collision Layer: 6 (targets)
   - Collision Mask: 5 (projectiles)
3. Убедитесь, что пуля имеет метод `area_entered.connect()`
4. Убедитесь, что мишень имеет метод `on_hit()`

### Низкая производительность

**Проблема**: Игра тормозит

**Решения**:
1. Откройте **Debug > Profiler** для анализа
2. Проверьте количество активных объектов (особенно пуль)
3. Удаляйте объекты, вышедшие за пределы экрана
4. Используйте `queue_free()` вместо удаления сразу
5. Отключите ненужные процессы с `set_process(false)`

### Управление не работает

**Проблема**: Персонаж не реагирует на клавиши

**Решения**:
1. Проверьте **Проект > Настройки проекта > Input Map**
2. Убедитесь, что действия правильно названы (`move_up`, `move_down` и т.д.)
3. Проверьте, что скрипт прикреплен к персонажу
4. Убедитесь, что `_physics_process` вызывается
5. Проверьте, что игра не на паузе (`get_tree().paused`)

### Настройки управления не сохраняются

**Проблема**: После перезапуска настройки клавиш сбрасываются

**Решения**:
1. Убедитесь, что InputSettings в автозагрузке
2. Проверьте, что путь `user://` доступен для записи
3. Кликните "Apply" перед выходом из меню управления
4. Проверьте консоль на ошибки сохранения

## Дополнительные ресурсы

### Официальная документация Godot
- [Godot 4 Documentation](https://docs.godotengine.org/en/stable/)
- [GDScript Reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)
- [2D Movement](https://docs.godotengine.org/en/stable/tutorials/2d/2d_movement.html)

### Обучающие материалы
- [Godot Tutorials](https://docs.godotengine.org/en/stable/community/tutorials.html)
- [GDQuest - Free Godot Tutorials](https://www.gdquest.com/)
- [HeartBeast - Godot Tutorials (YouTube)](https://www.youtube.com/c/uheartbeast)

### Сообщество
- [Godot Forum](https://forum.godotengine.org/)
- [Godot Discord](https://discord.gg/zH7NUgz)
- [Reddit r/godot](https://www.reddit.com/r/godot/)

## Лицензия

См. файл [LICENSE](LICENSE) для получения подробной информации.

---

**Версия шаблона**: 1.0
**Совместимость**: Godot 4.3+
**Последнее обновление**: 2026-01-11
