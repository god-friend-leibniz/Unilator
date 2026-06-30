import os
import sys
import struct
import json
import re
import html as html_lib
import gzip

try:
    from readmdict import MDX
    HAS_MDICT = True
except ImportError:
    HAS_MDICT = False
    print("ВНИМАНИЕ: Для поддержки форматов .mdx установите библиотеку:")
    print("pip install readmdict\n")


def clean_html(raw_html, keyword):
    # 1. Зачистка невидимого мусора и неразрывных пробелов (они ломали форматирование Кембриджа)
    html = raw_html.replace('&nbsp;', ' ')
    html = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '', html)
    html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.IGNORECASE|re.DOTALL)
    html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.IGNORECASE|re.DOTALL)
    html = re.sub(r'<!--.*?-->', '', html, flags=re.DOTALL)
    
    # Расширенные словари классов
    example_classes = r'ex|example|eg|examp|e|x|sentence|cit|def-ex|phrase|quote|q'
    gram_classes = r'gram|pos|syntax|wordclass|pron|dpron|phonetics|itype|spell|speaker|uk|us|dgram|pos-title|pos-block'
    
    ex_pat = fr'class=["\']?[^"\'>]*\b(?:{example_classes})\b'
    gr_pat = fr'class=["\']?[^"\'>]*\b(?:{gram_classes})\b'

    # 3. Принудительные переносы перед смысловыми блоками
    html = re.sub(r'(<k[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    html = re.sub(r'(</k>)', r'\1\n', html, flags=re.IGNORECASE)
    html = re.sub(r'(<ex[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    html = re.sub(r'(</ex>)', r'\1\n', html, flags=re.IGNORECASE)
    
    html = re.sub(fr'(<[^>]*{ex_pat}[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    html = re.sub(fr'(<[^>]*{gr_pat}[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    
    # 4. Блочные элементы превращаем в переносы строк \n
    html = re.sub(r'(<br\s*/?>|</?p>|</?div>|</?li>|</?blockquote>|<hr>|</?tr>|</?td>|</?table>)', '\n', html, flags=re.IGNORECASE)
    
    raw_lines = html.split('\n')
    structured_data = []
    unique_lines = set()
    
    for line in raw_lines:
        line = line.strip()
        if not line: continue
            
        tag_type = "def" 
        
        # Проверка на заголовки
        if re.search(r'<k[^>]*>', line, re.IGNORECASE) or re.search(r'class=["\']?(?:h|head|title)["\']?', line, re.IGNORECASE):
            tag_type = "h"
            
        # ПРОКАЧАННАЯ ПРОВЕРКА НА ПРИМЕРЫ (Теги, Классы, Буллиты или Темно-синий цвет Кембриджа #0B0B61)
        elif re.search(ex_pat, line, re.IGNORECASE) \
             or re.search(r'<ex>', line, re.IGNORECASE) \
             or re.search(r'color=["\']?(?:green|#008000|#008080|teal|#0B0B61)["\']?', line, re.IGNORECASE) \
             or re.search(r'(▪|•|◆|♦|■|&diams;|&bull;)', line, re.IGNORECASE):
            tag_type = "ex"
            
        # ПРОКАЧАННАЯ ПРОВЕРКА НА ГРАММАТИКУ (Добавлены orange, orangered, darkcyan, #006400 и др.)
        elif re.search(r'<c[^>]*>', line, re.IGNORECASE) \
             or re.search(gr_pat, line, re.IGNORECASE) \
             or re.search(r'color=["\']?(?:gray|#808080|#0000ff|red|#ff0000|orange|orangered|darkcyan|rosybrown|darkslategray|#006400)["\']?', line, re.IGNORECASE):
            tag_type = "gram"
            
        # Эвристика: если строка в курсиве и длинная — это пример
        elif re.search(r'^<[^>]*i[^>]*>.*</i>$', line, re.IGNORECASE) and len(re.sub(r'<[^>]+>', '', line)) > 15:
            tag_type = "ex"
            
        # 5. ИЗВЛЕКАЕМ ЧИСТОЕ ЗНАЧЕНИЕ
        # ФИКС МЮЛЛЕРА (Ударения): Удаляем инлайн-теги (шрифты, жирность, курсив) "в ноль", 
        # чтобы они не разрывали слово изнутри (например, усыновл<font>я</font>ть -> усыновлять)
        inline_tags = r'/?(?:b|i|u|strong|em|font|span|c|a|k)'
        line = re.sub(fr'<{inline_tags}[^>]*>', '', line, flags=re.IGNORECASE)
        
        # Остальные теги (если вдруг остались какие-то экзотические) меняем на пробел
        v = re.sub(r'<[^>]+>', ' ', line) 
        
        v = html_lib.unescape(v)
        v = re.sub(r'\s+', ' ', v).strip() 
        # Удаляем знаки препинания И ОРИГИНАЛЬНЫЕ БУЛЛИТЫ КЕМБРИДЖА с начала строки!
        v = re.sub(r'^[,:;.\-~▪•◆♦■]+\s*', '', v) 
        
        if len(v) < 2 and v.lower() != keyword.lower():
            continue
            
        if v not in unique_lines:
            unique_lines.add(v)
            structured_data.append({"t": tag_type, "v": v})
            
    return json.dumps(structured_data, ensure_ascii=False)


def stardict_generator(idx_path, dict_path, is_dz=False):
    """Генератор StarDict"""
    with open(idx_path, 'rb') as f:
        idx_data = f.read()

    if is_dz:
        with gzip.open(dict_path, 'rb') as f:
            dict_data = f.read()
    else:
        with open(dict_path, 'rb') as f:
            dict_data = f.read()

    ptr = 0
    total_length = len(idx_data)
    while ptr < total_length:
        end = idx_data.find(b'\0', ptr)
        if end == -1: break
        
        word = idx_data[ptr:end].decode('utf-8', errors='ignore')
        ptr = end + 1
        
        if ptr + 8 > total_length: break
        
        offset, size = struct.unpack('>II', idx_data[ptr:ptr+8])
        ptr += 8
        
        raw_html = dict_data[offset:offset+size].decode('utf-8', errors='ignore')
        yield word, raw_html


def mdict_generator(mdx_path):
    """Генератор MDict"""
    if not HAS_MDICT:
        return
    mdx = MDX(mdx_path)
    for key, value in mdx.items():
        word = key.decode('utf-8', errors='ignore')
        raw_html = value.decode('utf-8', errors='ignore')
        yield word, raw_html


def process_and_save(base_name, entries_generator, out_dict, out_idx):
    """Писатель JSON-блоков"""
    with open(out_dict, 'wb') as f_out_dict, open(out_idx, 'wb') as f_out_idx:
        current_offset = 0
        word_count = 0
        
        for word, raw_html in entries_generator:
            clean_json_str = clean_html(raw_html, word)
            payload_bytes = clean_json_str.encode('utf-8')
            payload_size = len(payload_bytes)
            
            if payload_size == 0 or clean_json_str == "[]":
                continue
            
            f_out_dict.write(payload_bytes)
            f_out_idx.write(word.encode('utf-8') + b'\0')
            f_out_idx.write(struct.pack('>II', current_offset, payload_size))
            
            current_offset += payload_size
            word_count += 1
            
            if word_count % 50000 == 0:
                print(f"    -> Обработано {word_count} слов...")

    print(f"    => Успешно: {os.path.basename(out_dict)} ({current_offset / 1024 / 1024:.2f} MB, {word_count} слов)\n")


def process_dictionary(base_name):
    # Очищаем переданное имя от возможных расширений
    base_name = re.sub(r'(\.idx|\.dict\.dz|\.dict|\.mdx)$', '', base_name, flags=re.IGNORECASE)
    
    # ЗАЩИТА: Игнорируем файлы, которые уже были обработаны
    if base_name.endswith('_clean'):
        print(f"    Пропуск {base_name}: этот файл уже был очищен ранее.")
        return
    
    out_idx = os.path.join("clean", f"{base_name}_clean.idx")
    out_dict = os.path.join("clean", f"{base_name}_clean.dict")
    
    mdx_path = f"{base_name}.mdx"
    dict_path = f"{base_name}.dict"
    idx_path = f"{base_name}.idx"
    dz_path = f"{base_name}.dict.dz"

    print(f"Конвертация {base_name}...")
    
    if os.path.exists(mdx_path):
        print(f"    Формат: MDict (.mdx)")
        process_and_save(base_name, mdict_generator(mdx_path), out_dict, out_idx)
    elif os.path.exists(dz_path) and os.path.exists(idx_path):
        print(f"    Формат: StarDict сжатый (.dict.dz)")
        process_and_save(base_name, stardict_generator(idx_path, dz_path, is_dz=True), out_dict, out_idx)
    elif os.path.exists(dict_path) and os.path.exists(idx_path):
        print(f"    Формат: StarDict (.dict)")
        process_and_save(base_name, stardict_generator(idx_path, dict_path, is_dz=False), out_dict, out_idx)
    else:
        print(f"    Пропуск {base_name}: исходные файлы не найдены.")


if __name__ == "__main__":
    dictionaries_to_process = sys.argv[1:]
    
    if not dictionaries_to_process:
        print("В парсер не переданы файлы для обработки.")
        sys.exit(0)
        
    print(f"Запуск Универсального Парсера для {len(dictionaries_to_process)} баз...")
    os.makedirs("clean", exist_ok=True)

    for d in dictionaries_to_process:
        process_dictionary(d)
        
    print("Парсинг завершен!")
