# OriginDroplet

Интерактивная «капля» на обоях рабочего стола в стиле OriginOS 7 (vivo) — твик для джейлбрейка.

**Цель:** iPhone X, rootless-джейлбрейк (Dopamine / RootHide), iOS 15–16, arm64.

## Что делает

- **Трясёшь телефон** → капля «срывается», скользит по наклону (гравитация берётся с акселерометра), прыгает от стенок экрана и останавливается в новом месте.
- **Тапаешь по пустому месту на рабочем столе** → капля пружинкой уезжает в точку тапа.
- Капля лежит **на обоях, под иконками** — тапы по иконкам её не двигают, свайпы страниц работают как раньше.
- Последнее место капли **запоминается** и восстанавливается после респринга.
- Вид: рисованная водой капля (CoreGraphics, без картинок) или **свой PNG** (путь в настройках).

## Настройки

Появятся в **Настройки → OriginDroplet**:

| Параметр | Что делает |
|---|---|
| Включено | мастер-выключатель |
| Двигать от тряски | вкл/выкл реакции на встряску |
| Двигать по тапу | вкл/выкл перемещения к точке тапа |
| Размер капли | 16–96 pt |
| Чувствительность к тряске | порог по ускорению (g), меньше = чувствительнее |
| Прыгучесть | упругость отскока от краёв экрана |
| Путь к PNG | своя картинка вместо рисованной капли |
| Подробные логи | логи в Console (`[OriginDroplet]`) |

Настройки подхватываются на лету (до ~0.5 с), респринг не нужен.

## Как это устроено

- `Tweak.x`: хуки `SBHomeScreenView` (вставка капли над вьюхой обоев) и `SBIconListView` (детект тапа по пустому месту).
- Физика — `UIDynamicAnimator`: гравитация, столкновения с границами экрана, упругость.
- Тряска — `CMMotionManager` (акселерометр, 30 Гц, порог из настроек).
- Настройки — обычный PreferenceLoader-плагин без кода, ключи в `com.origindroplet.defaults`.

## Сборка (Theos)

> **Важно:** команды выполняются в терминале **WSL (Ubuntu)**, не в PowerShell — путь `/mnt/c/...` существует только внутри WSL. Theos в этой машине уже настроен (`~/theos`, SDK 16.5, ldid).

Нужен Theos с iOS SDK. На Windows удобнее всего WSL (Ubuntu):

```bash
# 1. Зависимости (внутри WSL)
sudo apt update
sudo apt install -y build-essential fakeroot rsync perl git unzip ncurses-term

# 2. Theos
mkdir -p ~/theos && git clone --recursive https://github.com/theos/theos.git ~/theos
# SDK (если ещё нет)
curl -L https://github.com/theos/sdks/archive/master.zip -o sdks.zip
unzip sdks.zip && mv sdks-master/iphone* ~/theos/sdks/ && rm -rf sdks-master sdks.zip
echo 'export THEOS=~/theos' >> ~/.bashrc && source ~/.bashrc

# 3. Сборка (папка проекта видна в WSL по пути /mnt/c/...)
cd /mnt/c/Users/SKIBIDIST/Documents/rustra1n/repo/OriginDroplet
make package FINALPACKAGE=1              # rootless (по умолчанию)
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootful   # rootful
# или всё сразу (оба твика, обе схемы + apt-репо): ../build-all.sh
```

Получится `packages/com.rom4ik.origindroplet_0.1.0_iphoneos-arm64.deb`.

## Установка

**Вариант 1 — по SSH** (на телефоне включён OpenSSH, твик-бандлы rootless ставятся в `/var/jb`):

```bash
export THEOS_DEVICE_IP=<IP телефона> THEOS_DEVICE_PORT=22
make install
```

**Вариант 2 — руками:** скинь `.deb` на телефон (AirDrop-через-облако/Filza), открой в Filza → Install → Respring.

После респринга: Настройки → OriginDroplet.

## Если что-то не так

- **Капля не появилась.** Включи «Подробные логи», посмотри Console (или `idevicesyslog`): если `droplet installed ... wallpaper nil` — на твоей iOS обои лежат не там, где ожидается; скажи версию iOS, поправлю поиск вьюхи.
- **Тряска не срабатывает.** Уменьши «Чувствительность» (порог) в настройках; проверь, что «Двигать от тряски» включено.
- **Капля двигается по тапу мимо.** Это точка считается в координатах домашнего экрана — на всякий случай пришли лог из Console.
- **Хочу вернуть как было** — выключи тумблер или удали пакет (`dpkg -r com.rom4ik.origindroplet`).

## Файлы проекта

```
OriginDroplet/
├── Makefile                  # Theos, rootless-схема, arm64
├── control                   # метаданные пакета (Architecture: iphoneos-arm64)
├── OriginDroplet.plist       # фильтр: грузится только в SpringBoard
├── Tweak.x                   # весь код твика
├── layout/Library/PreferenceLoader/Preferences/Origindroplet.plist
│                             # страница настроек; в rootless-схеме Theos сам
│                             # добавляет префикс /var/jb ко всем путям
└── packages/*.deb            # готовый пакет после make package
```

> Если вдруг собирать под rootful-джейлбрейк: убери `THEOS_PACKAGE_SCHEME = rootless` из Makefile и поменяй `Architecture` в `control` на `iphoneos-arm`.
