// 跨端键值存储：移动端 / 桌面端用本地 JSON 文件，Web 用浏览器 localStorage。
export 'local_store_io.dart'
    if (dart.library.js_interop) 'local_store_web.dart';
