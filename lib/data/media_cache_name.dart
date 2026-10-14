import 'dart:convert';

// 云端照片的本地缓存文件名：由引用（URL / oss 路径）算出稳定的短名。
//
// 不能直接把引用当文件名（含冒号、斜杠、查询串），因此做两次 32 位哈希拼接，
// 既跨端一致（Web 上不会出现超长文件名），也不容易撞名。
String cloudCacheName(String ref) {
  var fnv = 0x811c9dc5;
  var djb = 5381;
  for (final unit in utf8.encode(ref)) {
    fnv = ((fnv ^ unit) * 0x01000193) & 0xFFFFFFFF;
    djb = ((djb * 33) + unit) & 0xFFFFFFFF;
  }
  final a = fnv.toRadixString(16).padLeft(8, '0');
  final b = djb.toRadixString(16).padLeft(8, '0');
  return '$a$b';
}
