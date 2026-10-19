import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
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
    // 已退租 / 纠纷中只读：相册能翻、能看，不能再追加拍摄
    final property = repository.propertyById(widget.propertyId);
    final editable = property != null && canEditProperty(property);

    return ZScreen(
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            // 「入住取证-客厅」：阶段在前，房间在后
            title: '${widget.phase.label}-${widget.room}',
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
              if (editable)
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
                    actionLabel: editable ? '立即拍照' : null,
                    onAction: editable ? () => _add(context, repository) : null,
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
                                // 单图看的是整张证据：按原图比例摆，
                                // contain 完整显示，不用 cover 裁掉边缘
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio:
                                        photo.width > 0 && photo.height > 0
                                        ? photo.width / photo.height
                                        : 4 / 3,
                                    child: ZPhoto(
                                      ref: photo.imageRef,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // 时间已经在水印条里了，这里不再重复一遍
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
                        child: ZPhoto(
                          ref: photo.imageRef,
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
