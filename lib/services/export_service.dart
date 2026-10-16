import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../utils/format.dart';

class ExportBundle {
  const ExportBundle({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

class ExportService {
  ExportService(this.repository);

  final Repository repository;

  /// 照片包：全部原始取证照片 + 取证清单文本
  Future<ExportBundle> buildPhotoZip(Property property) async {
    final archive = Archive();
    final photos = repository.photosOf(property.id);
    final manifest = StringBuffer()
      ..writeln('租盾 · 取证照片包')
      ..writeln('房源：${property.name}')
      ..writeln('地址：${property.address}')
      ..writeln('导出时间：${fmtDateTime(DateTime.now())}')
      ..writeln('照片数量：${photos.length}')
      ..writeln('');

    for (final photo in photos) {
      final bytes = await repository.readMedia(photo.imageRef);
      if (bytes == null) continue;
      final folder = '${photo.phase.label}/${photo.room}';
      final name =
          '${fmtDateTime(photo.timestamp).replaceAll(RegExp(r'[^0-9]'), '')}_${photo.issueType.label}.jpg';
      archive.addFile(ArchiveFile('$folder/$name', bytes.length, bytes));
      manifest.writeln(
        '[$folder] $name | 问题：${photo.issueType.label} | 说明：${photo.description.isEmpty ? '无' : photo.description}',
      );
    }

    final manifestBytes = utf8.encode(manifest.toString());
    archive.addFile(
      ArchiveFile('取证清单.txt', manifestBytes.length, manifestBytes),
    );

    return ExportBundle(
      bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
      fileName: '${_safe(property.name)}_取证照片包.zip',
    );
  }

  String _safe(String input) =>
      input.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
}
