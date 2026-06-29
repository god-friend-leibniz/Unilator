#!/bin/bash

# Укажите путь к папке с вашими скачанными словарями
ASSETS_DIR="/Users/maxwell/itmo/Scheise/offline_dict/assets"
# Путь к Python-конвертеру
CONVERTER_SCRIPT="$(pwd)/parser.py"

echo "=== Шаг 1: Подготовка и Распаковка архивов ==="
cd "$ASSETS_DIR" || {
    echo "Ошибка: Папка $ASSETS_DIR не найдена!"
    exit 1
}

# Создаем папку clean, если ее нет
mkdir -p clean

# Распаковываем tar.bz2 и tar.gz
for archive in *.tar.bz2 *.tar.gz; do
    if [ -f "$archive" ]; then
        echo "📦 Распаковываем архив: $archive"
        tar -xf "$archive"
    fi
done

# Распаковываем zip архивы
for archive in *.zip; do
    if [ -f "$archive" ]; then
        echo "📦 Распаковываем архив: $archive"
        unzip -q "$archive"
    fi
done

echo ""
echo "=== Шаг 2: Вытаскиваем файлы из подпапок ==="
# Ищем файлы в подпапках (mindepth 2), ИГНОРИРУЯ папку clean (-prune)
find . -mindepth 2 -name "clean" -prune -o -type f \( -name "*.dict" -o -name "*.idx" -o -name "*.dict.dz" -o -name "*.mdx" \) -exec mv {} . \;

# Удаляем пустые папки (кроме clean)
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
else
    echo "⚠️ Утилита dictunzip не установлена. Пропускаем..."
fi

echo ""
echo "=== Шаг 4: Конвертация MDX через PyGlossary ==="
for mdx_file in *.mdx; do
    if [ -f "$mdx_file" ]; then
        base="${mdx_file%.mdx}"
        if [ ! -f "${base}.dict" ]; then
            echo "🔄 Конвертируем $mdx_file в StarDict формат..."
            # Pyglossary для формата StarDict требует на выходе указать .ifo файл
            ipy pyglossary "$mdx_file" "${base}.ifo" --write-format=Stardict
        else
            echo "⏭️  $mdx_file уже имеет соответствующий .dict файл, пропускаем."
        fi
    fi
done

echo ""
echo "=== Шаг 5: Поиск новых файлов для парсера ==="
# Собираем словари, которых еще нет в папке clean
FILES_TO_PROCESS=()

for dict_file in *.dict; do
    if [ -f "$dict_file" ]; then
        base="${dict_file%.dict}"
        # Проверяем, есть ли уже готовый чистый файл в папке clean/
        if [ ! -f "clean/${base}_clean.dict" ]; then
            FILES_TO_PROCESS+=("$base")
        fi
    fi
done

if [ ${#FILES_TO_PROCESS[@]} -eq 0 ]; then
    echo "✅ Все словари уже обработаны! Нет новых файлов."
    exit 0
fi

echo "🚀 Найдены новые словари для обработки: ${FILES_TO_PROCESS[*]}"

if [ -f "$CONVERTER_SCRIPT" ]; then
    # Запускаем парсер и передаем ему список базовых имен файлов
    python3 "$CONVERTER_SCRIPT" "${FILES_TO_PROCESS[@]}"
else
    echo "❌ Ошибка: Файл $CONVERTER_SCRIPT не найден!"
fi

echo ""
echo "=== 🎉 Все операции успешно завершены! ==="
