import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';
import 'capture_page.dart';
import 'evidence_export_page.dart';
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

    return ZScreen(
      bottomBar: ZBottomBar(
        child: ZButton(
          icon: Icons.photo_camera_outlined,
          label: '为「${rooms[_selectedRoom]}」拍照取证',
          onTap: () => _capture(context, repository, rooms[_selectedRoom]),
        ),
      ),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const ZSteps(steps: ['选房间', '拍照', '标注', '存证'], current: 0),
                const SizedBox(height: 16),
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
                        onTap: () => setState(() => _selectedRoom = i),
                        onOpen: () => zPush(
                          context,
                          RoomAlbumPage(
                            propertyId: property.id,
                            room: rooms[i],
                            phase: _phase,
                          ),
                        ),
                      ),
                    _AddRoomTile(
                      onTap: () => _addRoom(context, repository, property),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ZButton(
                  label: '生成取证清单 / 照片包',
                  style: ZButtonStyle.ghost,
                  icon: Icons.ios_share,
                  onTap: () => zPush(
                    context,
                    EvidenceExportPage(propertyId: property.id, phase: _phase),
                  ),
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
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加房间'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：书房'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: Z.ink3)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
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
    required this.onTap,
    required this.onOpen,
  });

  final String room;
  final int count;
  final String? thumbRef;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: count > 0 ? onOpen : onTap,
            onLongPress: onTap,
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
                watermark: ['$room · $count 张'],
                overlay: count == 0
                    ? Container(
                        color: Z.card.withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          size: 18,
                          color: Z.brand,
                        ),
                      )
                    : null,
              ),
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
            borderRadius: BorderRadius.circular(Z.rSm),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Z.rSm),
                border: Border.all(color: Z.dashed, width: 1.4),
              ),
              child: Icon(Icons.add_rounded, size: 18, color: Z.ink4),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '',
          style: TextStyle(fontFamily: Z.font, fontFamilyFallback: Z.fallback),
        ),
      ],
    );
  }
}
