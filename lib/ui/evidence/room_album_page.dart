import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';
import 'capture_page.dart';
import 'photo_detail_page.dart';

/// 页面 07 · 取证 · 房间相册（按时间倒序，只可追加）
class RoomAlbumPage extends StatefulWidget {
  const RoomAlbumPage({
    super.key,
    required this.propertyId,
    required this.room,
    required this.phase,
  });

  final String propertyId;
  final String room;
  final PhotoPhase phase;

  @override
  State<RoomAlbumPage> createState() => _RoomAlbumPageState();
}

class _RoomAlbumPageState extends State<RoomAlbumPage> {
  bool _slideMode = false;
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final photos = repository.photosOf(
      widget.propertyId,
      phase: widget.phase,
      room: widget.room,
    );

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '$widget.room · ${widget.phase.label}',
            subtitle: photos.isEmpty
                ? null
                : '已存证 ${photos.length} 张'
                      '${_slideMode ? ' · ${_current + 1}/${photos.length}' : ''}',
            actions: [
              if (photos.isNotEmpty)
                ZIconButton(
                  icon: _slideMode
                      ? Icons.grid_view_rounded
                      : Icons.view_carousel_rounded,
                  color: Z.brand,
                  tooltip: _slideMode ? '网格视图' : '幻灯片视图',
                  onTap: () => setState(() {
                    _slideMode = !_slideMode;
                    _current = _current.clamp(0, photos.length - 1);
                  }),
                ),
              ZIconButton(
                icon: Icons.photo_camera_outlined,
                color: Z.brand,
                tooltip: '追加拍摄',
                onTap: () => _add(context, repository),
              ),
            ],
          ),
          Expanded(
            child: photos.isEmpty
                ? ZEmpty(
                    icon: Icons.photo_camera_outlined,
                    title: '${widget.room} 还没有照片',
                    message: '拍下这个房间的现状，系统会自动加时间水印。',
                    actionLabel: '立即拍照',
                    onAction: () => _add(context, repository),
                  )
                : _slideMode
                ? PageView.builder(
                    controller: PageController(
                      initialPage: _current.clamp(0, photos.length - 1),
                    ),
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _current = i),
                    itemBuilder: (context, index) {
                      final photo = photos[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => zPush(
                                  context,
                                  PhotoDetailPage(photoId: photo.id),
                                ),
                                child: ZPhoto(
                                  ref: photo.imageRef,
                                  watermark: [
                                    '${photo.issueType.emoji} ${photo.issueType.label}',
                                    fmtDateTime(photo.timestamp),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              fmtDateTime(photo.timestamp),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZText.mono.copyWith(fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${index + 1} / ${photos.length}',
                              style: ZText.caption.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 9,
                          crossAxisSpacing: 9,
                          childAspectRatio: 0.78,
                        ),
                    itemCount: photos.length,
                    itemBuilder: (context, index) {
                      final photo = photos[index];
                      return GestureDetector(
                        onTap: () =>
                            zPush(context, PhotoDetailPage(photoId: photo.id)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ZPhoto(
                                ref: photo.imageRef,
                                watermark: [
                                  '${photo.issueType.emoji} ${photo.issueType.label}',
                                  fmtDateTime(photo.timestamp),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              fmtDateTime(photo.timestamp),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZText.mono.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, Repository repository) async {
    final bytes = await pickImage(context);
    if (bytes == null || !context.mounted) return;
    await zPush(
      context,
      CapturePage(
        propertyId: widget.propertyId,
        room: widget.room,
        phase: widget.phase,
        bytes: bytes,
      ),
    );
  }
}
