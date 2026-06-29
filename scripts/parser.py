import os
import sys
import struct
import json
import re
import html as html_lib

def clean_html(raw_html, keyword):
    # 1. Тотальная зачистка невидимого мусора и скриптов
    html = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '', raw_html)
    html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.IGNORECASE|re.DOTALL)
    html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.IGNORECASE|re.DOTALL)
    html = re.sub(r'<!--.*?-->', '', html, flags=re.DOTALL)
    
    # 2. ИЗОЛЯЦИЯ СЕМАНТИЧЕСКИХ БЛОКОВ
    html = re.sub(r'(<k[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    html = re.sub(r'(</k>)', r'\1\n', html, flags=re.IGNORECASE)
    html = re.sub(r'(<ex[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    html = re.sub(r'(</ex>)', r'\1\n', html, flags=re.IGNORECASE)
    html = re.sub(r'(<(?:div|span)[^>]*class=["\']?ex(?:ample)?["\']?[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    html = re.sub(r'(<c[^>]*>)', r'\n\1', html, flags=re.IGNORECASE)
    html = re.sub(r'(</c>)', r'\1\n', html, flags=re.IGNORECASE)
    
    # 3. Блочные элементы и маркеры словаря превращаем в переносы строк \n
    html = re.sub(r'(<br\s*/?>|</?p>|</?div>|</?li>|</?blockquote>|<hr>|</?tr>|</?td>|</?table>|▪|•|◆|♦|■)', '\n', html, flags=re.IGNORECASE)
    
    # Разбиваем на сырые строки для анализа
    raw_lines = html.split('\n')
    
    structured_data = []
    unique_lines = set()
    
    for line in raw_lines:
        line = line.strip()
        if not line:
            continue
            
        # 4. ОПРЕДЕЛЯЕМ ТИП БЛОКА (t) на основе оставшихся HTML-тегов
        tag_type = "def" # По умолчанию - Определение
        
        if re.search(r'<k[^>]*>', line, re.IGNORECASE):
            tag_type = "h" 
        elif re.search(r'<(ex|span|div)[^>]*class=["\']?ex(?:ample)?["\']?[^>]*>', line, re.IGNORECASE) or re.search(r'<ex>', line, re.IGNORECASE):
            tag_type = "ex" 
        elif re.search(r'<c[^>]*>', line, re.IGNORECASE) or re.search(r'class=["\']?(?:gram|pos|syntax|wordclass)["\']?', line, re.IGNORECASE):
            tag_type = "gram" 
            
        # 5. ИЗВЛЕКАЕМ ЧИСТОЕ ЗНАЧЕНИЕ (v)
        v = re.sub(r'<[^>]+>', '', line) 
        v = html_lib.unescape(v)         
        v = re.sub(r'\s+', ' ', v).strip() 
        v = re.sub(r'^[,:;.\-~]+\s*', '', v) 
        
        # Защита от мусора
        if len(v) < 2 and v.lower() != keyword.lower():
            continue
            
        # Защита от дубликатов
        if v not in unique_lines:
            unique_lines.add(v)
            structured_data.append({"t": tag_type, "v": v})
            
    return json.dumps(structured_data, ensure_ascii=False)

def process_dictionary(base_name):
    # Файлы лежат в текущей директории (откуда bash запустил скрипт)
    idx_path = f"{base_name}.idx"
    dict_path = f"{base_name}.dict"
    
    # Сохраняем результат в папку clean
    out_idx = os.path.join("clean", f"{base_name}_clean.idx")
    out_dict = os.path.join("clean", f"{base_name}_clean.dict")
    
    if not os.path.exists(idx_path) or not os.path.exists(dict_path):
        print(f"Пропуск {base_name}: исходные файлы (.idx или .dict) не найдены.")
        return

    print(f"Конвертация {base_name}...")
    
    with open(idx_path, 'rb') as f:
        idx_data = f.read()

    entries = []
    ptr = 0
    while ptr < len(idx_data):
        end = idx_data.find(b'\0', ptr)
        if end == -1: break
        word = idx_data[ptr:end].decode('utf-8', errors='ignore')
        ptr = end + 1
        if ptr + 8 > len(idx_data): break
        offset, size = struct.unpack('>II', idx_data[ptr:ptr+8])
        ptr += 8
        entries.append((word, offset, size))

    with open(dict_path, 'rb') as f_in, \
         open(out_dict, 'wb') as f_out_dict, \
         open(out_idx, 'wb') as f_out_idx:
         
        current_offset = 0
        word_count = 0
        
        for word, offset, size in entries:
            f_in.seek(offset)
            raw_html = f_in.read(size).decode('utf-8', errors='ignore')
            
            clean_json_str = clean_html(raw_html, word)
            payload_bytes = clean_json_str.encode('utf-8')
            payload_size = len(payload_bytes)
            
            # Пропускаем пустые записи
            if payload_size == 0 or clean_json_str == "[]":
                continue
            
            f_out_dict.write(payload_bytes)
            
            f_out_idx.write(word.encode('utf-8') + b'\0')
            f_out_idx.write(struct.pack('>II', current_offset, payload_size))
            
            current_offset += payload_size
            word_count += 1

    print(f"Успешно: clean/{base_name}_clean.dict ({current_offset / 1024 / 1024:.2f} MB, {word_count} слов)")

if __name__ == "__main__":
    # Получаем список файлов из аргументов командной строки (от bash-скрипта)
    dictionaries_to_process = sys.argv[1:]
    
    if not dictionaries_to_process:
        print("В парсер не переданы файлы для обработки.")
        sys.exit(0)
        
    print(f"Запуск Python парсера для {len(dictionaries_to_process)} файлов...")
    
    # Создаем папку clean на случай, если bash ее не создал
    os.makedirs("clean", exist_ok=True)

    for d in dictionaries_to_process:
        process_dictionary(d)
        
    print("\nПарсинг завершен!")
