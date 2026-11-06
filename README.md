# rom4ikg2000-lab Tweaks

Личный jailbreak-репозиторий: твики под **rootless** (Dopamine, RootHide, bootstrap в `/var/jb`) и **rootful** (palera1n и др.).

## Добавить источник в Sileo / Zebra

```
https://rom4ikg2000-lab.github.io/repo/
```

- **Sileo:** Sources → Edit → + → вставить URL
- **Zebra:** Sources → + → вставить URL
- Работает и в Cydia/Installer по тому же URL.

## Пакеты

| Пакет | Что делает | iOS |
|---|---|---|
| **WiggleTheme** | «Жидкие» обои экрана блокировки в стиле OriginOS 7 (Wiggle Theme): желе/пружина + водная рябь, Metal-шейдер, акселерометр+гироскоп, alpha-маска | 15–18, A12+ |
| **OriginDroplet** | Интерактивная капля на обоях домашнего экрана: тряска — капля скользит и прыгает, тап по пустому месту — уезжает туда | 15–16 rootless |

В обоих случаях пакет-менеджер сам выберет подходящую архитектуру (`iphoneos-arm64` для rootless, `iphoneos-arm` для rootful).

## Структура

```
repo/
├── OriginDroplet/            # исходники твика (Theos)
├── WiggleTheme/              # исходники твика (Theos + Metal)
├── build-all.sh              # сборка 4 deb (2 твика × 2 схемы) + генерация apt-репо
├── debs/                     # готовые пакеты (то, что качают устройства)
├── dists/stable/             # метаданные apt-репозитория (Packages, Release)
└── .github/workflows/        # CI: пересборка и публикация при пуше исходников
```

## Сборка локально (WSL/Ubuntu, Theos в ~/theos)

```bash
bash build-all.sh
```

Скрипт сам переключает `Architecture` в `control` (arm64/arm), собирает оба твика в обеих схемах и регенерирует `dists/`.

## CI

При пуше изменений в `OriginDroplet/**`, `WiggleTheme/**` или `build-all.sh` GitHub Actions пересобирает пакеты и коммитит свежие `debs/` + `dists/` в `main` — GitHub Pages раздаёт их по ссылке выше.
