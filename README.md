# rom4ikg2000-lab Tweaks

Личный репозиторий с jailbreak твиками для iOS. В репозитории собраны пакеты для rootless и rootful джейлбрейка.

## Добавить репозиторий

```text
https://rom4ikg2000-lab.github.io/repo/
```

Для Sileo: Sources → Edit → +, вставьте ссылку.
Для Zebra: Sources → +.

## Доступные твики

- WiggleTheme — "жидкие" обои для экрана блокировки с эффектом желе и ряби. Эффект реагирует на движение устройства, наклон и встряску.
- Поддерживаются архитектуры: `iphoneos-arm64` (rootless) и `iphoneos-arm` (rootful).

## Сборка

Для сборки нужен Linux/WSL, Theos и инструменты для сборки Debian-пакетов. По умолчанию скрипт ищет Theos в `~/theos`.

```bash
bash build-all.sh
```

Скрипт собирает пакеты, сохраняет их в папку `debs/` и обновляет метаданные репозитория в `dists/`.

## Автоматическая сборка

GitHub Actions автоматически пересобирает пакеты при изменениях в исходниках твиков или в `build-all.sh`.

## Разработка

```bash
cd WiggleTheme
make package FINALPACKAGE=1
```

Для rootful сборки:

```bash
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootful
```

## Примечание

Репозиторий поддерживает установку через стандартные менеджеры пакетов, совместимые с Debian-репозиториями.
