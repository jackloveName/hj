import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  LocalStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore._(await SharedPreferences.getInstance());

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) async =>
      _prefs.setString(key, value);

  Future<void> remove(String key) async => _prefs.remove(key);

  String get location => '浏览器本地存储 (localStorage)';
}
