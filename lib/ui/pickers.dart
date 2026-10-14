import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/tokens.dart';
import 'kit.dart';

bool get isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

enum _Source { camera, gallery }

Future<Uint8List?> pickImage(
  BuildContext context, {
  bool cameraFirst = true,
}) async {
  _Source source = _Source.gallery;
  // Web 上 image_picker 会把「拍照」映射成带 capture 的文件选择器，
  // 手机浏览器同样能直接唤起相机，所以这里不再把 Web 排除掉
  final allowCamera = cameraFirst;
  final picked = await showModalBottomSheet<_Source>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '添加照片',
              style: TextStyle(
                fontFamily: Z.font,
                fontFamilyFallback: Z.fallback,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (allowCamera)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Z.brand),
              title: const Text('拍照'),
              subtitle: const Text('立刻拍摄，自动记录时间与地点'),
              onTap: () => Navigator.of(ctx).pop(_Source.camera),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: Z.brand),
            title: const Text('从相册选择'),
            onTap: () => Navigator.of(ctx).pop(_Source.gallery),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (picked == null) return null;
  source = picked;

  try {
    final file = await ImagePicker().pickImage(
      source: source == _Source.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    if (file == null) return null;
    return await file.readAsBytes();
  } catch (error) {
    if (context.mounted) zToast(context, '无法读取图片：$error');
    return null;
  }
}

Future<List<Uint8List>> pickImages(BuildContext context) async {
  try {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    return [for (final file in files) await file.readAsBytes()];
  } catch (error) {
    if (context.mounted) zToast(context, '无法读取图片：$error');
    return const [];
  }
}

Future<DateTime?> pickDate(
  BuildContext context, {
  DateTime? initial,
  String helpText = '选择日期',
}) async {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 20),
    lastDate: DateTime(now.year + 30),
    helpText: helpText,
    locale: const Locale('zh', 'CN'),
  );
}
