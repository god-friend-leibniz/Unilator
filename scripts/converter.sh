#!/bin/bash

ASSETS_DIR="/Users/maxwell/itmo/Scheise/offline_dict/assets"
CONVERTER_SCRIPT="$(pwd)/parser.py"

echo "=== Шаг 1: Подготовка и Распаковка архивов ==="
cd "$ASSETS_DIR" || {
    echo "Ошибка: Папка $ASSETS_DIR не найдена!"
    exit 1
}

mkdir -p clean

for archive in *.tar.bz2 *.tar.gz; do
    if [ -f "$archive" ]; then
        echo "📦 Распаковываем архив: $archive"
        tar -xf "$archive"
    fi
done

for archive in *.zip; do
    if [ -f "$archive" ]; then
        echo "📦 Распаковываем архив: $archive"
        unzip -q "$archive"
    fi
done

echo ""
echo "=== Шаг 2: Вытаскиваем файлы из подпапок ==="
find . -mindepth 2 -name "clean" -prune -o -type f \( -name "*.dict" -o -name "*.idx" -o -name "*.dict.dz" -o -name "*.mdx" \) -exec mv {} . \;
find . -mindepth 1 -name "clean" -prune -o -type d -empty -delete
echo "✨ Файлы перемещены в корень."

echo ""
echo "=== Шаг 3: Распаковка .dict.dz в .dict ==="
if command -v dictunzip &>/dev/null; then
    for dz_file in *.dict.dz; do
        if [ -f "$dz_file" ]; then
            echo "🗜 Распаковываем $dz_file -> .dict"
            dictunzip "$dz_file"
        fi
    done
fi

echo ""
echo "=== Шаг 4: Поиск файлов для парсера ==="
FILES_TO_PROCESS=()

#Каждая база обязана иметь либо .idx (StarDict), либо .mdx (MDict)

for file in *.idx .mdx; do
    if [ -f "$file" ]; then
        base="${file%.}"
        if [ ! -f "clean/${base}_clean.dict" ]; then
            FILES_TO_PROCESS+=("$base")
        fi
    fi
done

if [ ${#FILES_TO_PROCESS[@]} -eq 0 ]; then
    echo "✅ Все словари уже обработаны! Нет новых файлов."
    exit 0
fi

echo "🚀 Найдены базы для обработки: ${FILES_TO_PROCESS[*]}"

if [ -f "$CONVERTER_SCRIPT" ]; then
    # Передаем массив имен в Python
    ipy python "$CONVERTER_SCRIPT" "${FILES_TO_PROCESS[@]}"
else
    echo "❌ Ошибка: Файл $CONVERTER_SCRIPT не найден!"
fi

echo ""
echo "=== 🎉 Все операции успешно завершены! ==="
