import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalStore {
  LocalStore._(this._file, this._data);

  final File _file;
  final Map<String, dynamic> _data;

  static Future<LocalStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}${Platform.pathSeparator}zudun');
    if (!await root.exists()) await root.create(recursive: true);
    final file = File('${root.path}${Platform.pathSeparator}store.json');
    Map<String, dynamic> data = <String, dynamic>{};
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            data = decoded.map((k, v) => MapEntry(k.toString(), v));
          }
        }
      } catch (_) {
        data = <String, dynamic>{};
      }
    }
    return LocalStore._(file, data);
  }

  String? getString(String key) {
    final value = _data[key];
    return value is String ? value : null;
  }

  Future<void> setString(String key, String value) async {
    _data[key] = value;
    await _file.writeAsString(jsonEncode(_data), flush: true);
  }

  Future<void> remove(String key) async {
    _data.remove(key);
    await _file.writeAsString(jsonEncode(_data), flush: true);
  }

  String get location => _file.path;
}
