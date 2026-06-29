import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class IndexEntry {
  final String word;
  final int offset;
  final int size;
  IndexEntry(this.word, this.offset, this.size);
}

class DictionaryEngine {
  final List<IndexEntry> _index = [];
  RandomAccessFile? _dictFile;

  /// Загружает .idx в память и открывает .dict для быстрого чтения
  Future<bool> load(String idxPath, String dictPath) async {
    try {
      final idxBytes = await File(idxPath).readAsBytes();
      _dictFile = await File(dictPath).open(mode: FileMode.read);

      int ptr = 0;
      while (ptr < idxBytes.length) {
        int end = idxBytes.indexOf(0, ptr);
        if (end == -1) break;

        final word = utf8.decode(idxBytes.sublist(ptr, end));
        ptr = end + 1;

        if (ptr + 8 > idxBytes.length) break;

        final offsetData = ByteData.view(idxBytes.buffer, ptr, 8);
        final offset = offsetData.getUint32(0, Endian.big);
        final size = offsetData.getUint32(4, Endian.big);
        ptr += 8;

        _index.add(IndexEntry(word, offset, size));
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Сверхбыстрый бинарный поиск по индексу и чтение JSON с диска
  String translate(String query) {
    if (_index.isEmpty || _dictFile == null) return "";

    int low = 0;
    int high = _index.length - 1;

    while (low <= high) {
      int mid = low + ((high - low) >> 1);
      int cmp = _index[mid].word.compareTo(query);

      if (cmp == 0) {
        _dictFile!.setPositionSync(_index[mid].offset);
        final bytes = _dictFile!.readSync(_index[mid].size);
        return utf8.decode(bytes);
      } else if (cmp < 0) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return ""; // Слово не найдено
  }

  void dispose() {
    _dictFile?.closeSync();
  }
}
