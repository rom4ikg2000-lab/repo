# rom4ikg2000-lab Tweaks

Мой репозиторий с твиками для iOS. Есть пакеты для rootless и rootful jailbreak.

## Добавить репозиторий

```
https://rom4ikg2000-lab.github.io/repo/
```

В Sileo открой Sources → Edit → + и вставь ссылку. В Zebra: Sources → +.

## Твики

- **WiggleTheme** — обои для экрана блокировки с эффектом желе и водной рябью. Реагируют на движение телефона. iOS 15–18, A12+.
- **OriginDroplet** — капля на домашнем экране, которая двигается при тряске телефона и перемещается по нажатию на пустое место.

Оба твика собраны для rootless (`iphoneos-arm64`) и rootful (`iphoneos-arm`).

## Сборка

Нужны Linux или WSL, Theos и инструменты для сборки Debian-пакетов. По умолчанию скрипт ищет Theos в `~/theos`; другой путь можно указать через переменную `THEOS`.

```bash
bash build-all.sh
```

Скрипт собирает оба твика для rootless и rootful, сохраняет пакеты в `debs/` и обновляет метаданные в `dists/`.

GitHub Actions пересобирает пакеты при изменениях в исходниках твиков или `build-all.sh`. Репозиторий доступен через GitHub Pages.
