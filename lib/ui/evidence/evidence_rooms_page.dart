import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';
import 'capture_page.dart';
import 'room_album_page.dart';

/// SCREEN 03 · 入住取证 · 选房间
class EvidenceRoomsPage extends StatefulWidget {
  const EvidenceRoomsPage({
    super.key,
    required this.propertyId,
    this.initialPhase = PhotoPhase.moveIn,
  });

  final String propertyId;
  final PhotoPhase initialPhase;

  @override
  State<EvidenceRoomsPage> createState() => _EvidenceRoomsPageState();
}

class _EvidenceRoomsPageState extends State<EvidenceRoomsPage> {
  late PhotoPhase _phase = widget.initialPhase;
  int _selectedRoom = 0;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(widget.propertyId);
    if (property == null) {
      return const ZScreen(child: SizedBox.shrink());
    }
    final rooms = property.allRooms;
    final total = repository.photoCountOf(property.id, phase: _phase);
    // 角标与下方分区保持同一口径：都统计当前阶段
    final quota = '$total 张';
    // 已退租 / 纠纷中只读：照片可以翻，不能再拍、不能再加房间
    final editable = canEditProperty(property);

    return ZScreen(
      bottomBar: editable
          ? ZBottomBar(
              child: ZButton(
                icon: Icons.photo_camera_outlined,
                label: '为「${rooms[_selectedRoom]}」拍照取证',
                onTap: () => _capture(context, repository, rooms[_selectedRoom]),
              ),
            )
          : null,
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: _phase.label,
            actions: [
              ZPill(
                label: quota,
                background: Z.brandTint,
                foreground: Z.brand,
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ZChips<PhotoPhase>(
                  options: PhotoPhase.values,
                  value: _phase,
                  emphasize: true,
                  padding: EdgeInsets.zero,
                  labelOf: (value) => value.label,
                  onChanged: (value) => setState(() => _phase = value),
                ),
                const SizedBox(height: 12),
                const ZHintBar(text: '每张照片自动加 时间 / 位置 / 房间 水印，不可编辑，仅可追加。'),
                ZSectionTitle(
                  title: '房间（${rooms.length}）',
                  icon: Icons.meeting_room_outlined,
                  moreLabel: '已取证 $total 张',
                ),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.82,
                  children: [
                    for (var i = 0; i < rooms.length; i++)
                      _RoomTile(
                        room: rooms[i],
                        count: repository.photoCountOf(
                          property.id,
                          phase: _phase,
                          room: rooms[i],
                        ),
                        thumbRef: _thumb(repository, property.id, rooms[i]),
                        selected: _selectedRoom == i,
                        onSelect: () => setState(() => _selectedRoom = i),
                        onOpen: () => zPush(
                          context,
                          RoomAlbumPage(
                            propertyId: property.id,
                            room: rooms[i],
                            phase: _phase,
                          ),
                        ),
                      ),
                    if (editable)
                      _AddRoomTile(
                        onTap: () => _addRoom(context, repository, property),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _thumb(Repository repository, String propertyId, String room) {
    final photos = repository.photosOf(propertyId, phase: _phase, room: room);
    return photos.isEmpty ? null : photos.first.thumbRef;
  }

  Future<void> _capture(
    BuildContext context,
    Repository repository,
    String room,
  ) async {
    final bytes = await pickImage(context);
    if (bytes == null || !context.mounted) return;
    await zPush(
      context,
      CapturePage(
        propertyId: widget.propertyId,
        room: room,
        phase: _phase,
        bytes: bytes,
      ),
    );
  }

  Future<void> _addRoom(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    // 刻意不用 TextEditingController：弹窗退场动画还在跑的时候 dispose 它，
    // TextField 会拿着已释放的控制器重建，直接红屏。这里只要「按下确定时
    // 拿到当前输入」，一个局部变量就够。
    var typed = '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加房间'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：书房'),
          onChanged: (text) => typed = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: Z.ink3)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(typed.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await repository.updateProperty(
      property.copyWith(rooms: [...property.rooms, name]),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.count,
    required this.thumbRef,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final String room;
  final int count;
  final String? thumbRef;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    // 整块（照片 + 房间名）都可点：点哪间就高亮哪间；
    // 已经拍过的房间顺带打开相册
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onSelect();
        if (count > 0) onOpen();
      },
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Z.rMd),
                border: Border.all(
                  color: selected ? Z.brand : Colors.transparent,
                  width: 1.6,
                ),
              ),
              padding: const EdgeInsets.all(1.5),
              child: ZPhoto(
                ref: thumbRef,
                radius: Z.rSm,
                // 房间名就在格子下方（「客厅」），照片上只留张数
                watermark: ['$count 张'],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            room,
            style: TextStyle(
              fontFamily: Z.font,
              fontFamilyFallback: Z.fallback,
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Z.brand : Z.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddRoomTile extends StatelessWidget {
  const _AddRoomTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Z.rMd),
            child: Container(
              // 外框跟 _RoomTile 一模一样（1.6 透明描边 + 1.5 内边距），
              // 这样虚线格和照片格一样大、四边也对齐
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Z.rMd),
                border: Border.all(color: Colors.transparent, width: 1.6),
              ),
              child: Container(
                // 得显式居中：不加 alignment 时这个虚线框会缩到图标那么大
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Z.rSm),
                  border: Border.all(color: Z.dashed, width: 1.4),
                ),
                child: Icon(Icons.add_rounded, size: 18, color: Z.ink4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '',
          // 占位一行：字号跟房间名一致，两个格子的高度才对得上
          style: TextStyle(
            fontFamily: Z.font,
            fontFamilyFallback: Z.fallback,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}
