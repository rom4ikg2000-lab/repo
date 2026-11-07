#!/usr/bin/env bash
# Сборка WiggleTheme под rootless и rootful + генерация apt-репозитория
# для Sileo/Zebra (dists/stable/...).
#
# Запуск в WSL: bash build-all.sh   (Theos в ~/theos; export THEOS=... если иначе)
set -euo pipefail

export THEOS="${THEOS:-$HOME/theos}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEBS="$ROOT/debs"
mkdir -p "$DEBS"

set_arch() { # $1 = каталог твика, $2 = архитектура для control
  sed -i "s/^Architecture:.*/Architecture: $2/" "$ROOT/$1/control"
}

build() { # $1 = каталог, $2 = схема, $3 = архитектура
  local dir="$1" scheme="$2" arch="$3"
  echo ">>> $dir [$scheme]"
  set_arch "$dir" "$arch"
  cd "$ROOT/$dir"
  rm -rf .theos
  make package FINALPACKAGE=1 "THEOS_PACKAGE_SCHEME=$scheme" >/dev/null
  cp packages/*.deb "$DEBS/"
  rm -rf .theos packages
  cd "$ROOT"
}

# rootful — это ПУСТАЯ схема в Theos (модуль только у rootless), поэтому ""
build WiggleTheme    rootless iphoneos-arm64
build WiggleTheme    ""       iphoneos-arm

echo ">>> apt-репозиторий (Packages/Release)"
cd "$ROOT"
mkdir -p dists/stable/main/binary-iphoneos-arm64 dists/stable/main/binary-iphoneos-arm
rm -f dists/stable/main/binary-iphoneos-arm*/Packages*
dpkg-scanpackages --multiversion debs /dev/null > dists/stable/main/binary-iphoneos-arm64/Packages
cp dists/stable/main/binary-iphoneos-arm64/Packages dists/stable/main/binary-iphoneos-arm/Packages
for f in dists/stable/main/binary-iphoneos-arm64/Packages dists/stable/main/binary-iphoneos-arm/Packages; do
  bzip2 -kf "$f"
  gzip -kf "$f"
done

hash_section() { # $1 = MD5Sum | SHA1 | SHA256, остальные — файлы
  local algo="$1"; shift
  echo "$algo:"
  local cmd rel h size
  case "$algo" in
    MD5Sum) cmd=md5sum ;;
    SHA1)   cmd=sha1sum ;;
    SHA256) cmd=sha256sum ;;
  esac
  for f in "$@"; do
    rel="${f#dists/stable/}"
    h=$("$cmd" "$f" | cut -d' ' -f1)
    size=$(stat -c%s "$f")
    echo " $h $size $rel"
  done
}

PKGS=$(find dists -name 'Packages*' | sort)
{
  echo "Origin: rom4ikg2000-lab"
  echo "Label: rom4ikg2000-lab Tweaks"
  echo "Suite: stable"
  echo "Codename: stable"
  echo "Version: 1.0"
  echo "Architectures: iphoneos-arm iphoneos-arm64"
  echo "Components: main"
  echo "Description: Personal tweak repository (rootless + rootful)"
  echo "Date: $(date -R)"
  echo
  hash_section MD5Sum  $PKGS
  echo
  hash_section SHA1    $PKGS
  echo
  hash_section SHA256  $PKGS
} > dists/stable/Release

# Flat repository metadata for package managers using the repository URL directly.
cp dists/stable/main/binary-iphoneos-arm64/Packages ./Packages
cp dists/stable/main/binary-iphoneos-arm64/Packages.gz ./Packages.gz
cp dists/stable/main/binary-iphoneos-arm64/Packages.bz2 ./Packages.bz2
{
  sed '/^MD5Sum:/,$d' dists/stable/Release
  for algo in MD5Sum SHA1 SHA256; do
    echo "$algo:"
    case "$algo" in MD5Sum) cmd=md5sum ;; SHA1) cmd=sha1sum ;; SHA256) cmd=sha256sum ;; esac
    for f in Packages Packages.gz Packages.bz2; do
      echo " $("$cmd" "$f" | cut -d' ' -f1) $(stat -c%s "$f") $f"
    done
    echo
  done
} > Release

echo ">>> Готово. Пакеты:"
ls -la "$DEBS"
