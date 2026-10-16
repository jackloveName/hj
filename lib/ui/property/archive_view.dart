import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';

/// 已退租房子的归档视图。
///
/// 「入住取证 / 合同信息 / 房东要求 / 维修记录 / 沟通记录」这些页面天生带着
/// 「加一条 / 改一下」的操作，已退租的房子不再让人点进去；但内容必须看得见 ——
/// 所以在这里摊平成几段只读的内容：合同要点、取证张数与缩略图、房东要求、
/// 维修、沟通。照片仍然可以点开看大图（看，不算操作）。
List<Widget> buildArchiveSections({
  required BuildContext context,
  required Repository repository,
  required Property property,
}) => [
  _contractSection(property),
  _evidenceSection(context, repository, property),
  _rulesSection(repository, property),
  _repairsSection(repository, property),
  _commsSection(repository, property),
];

/// 合同要点：房东、钱、关键日期、入住表底数 —— 全是那次租住的事实
Widget _contractSection(Property property) {
  final contract = property.contract;
  final deposit = property.deposit;
  final landlord = property.landlord;
  final readings = <String>[
    if (contract.moveInElectricity != null)
      '电 ${fmtAmount(contract.moveInElectricity!)}',
    if (contract.moveInWater != null) '水 ${fmtAmount(contract.moveInWater!)}',
    if (contract.hasGasMeter && contract.moveInGas != null)
      '燃气 ${fmtAmount(contract.moveInGas!)}',
  ];
  return Column(
    children: [
      const ZSectionTitle(
        title: '合同信息',
        icon: Icons.description_outlined,
      ),
      ZCard(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Column(
          children: [
            ZKv(label: '房东', value: landlord.name),
            if (landlord.phone.isNotEmpty)
              ZKv(label: '联系电话', value: landlord.phone),
            ZKv(
              label: '月租',
              value: '${fmtMoney(contract.monthlyRent)} / 月',
              valueColor: Z.ink,
            ),
            ZKv(
              label: '押金',
              value: contract.deposit > 0
                  ? '${fmtMoney(contract.deposit)} · ${deposit.status.label}'
                  : '无押金',
              valueColor: contract.deposit > 0 ? Z.warnDeep : Z.ink3,
            ),
            ZKv(label: '付款方式', value: contract.paymentMethod),
            ZKv(
              label: '入住',
              value: fmtDate(contract.moveInDate),
              mono: true,
            ),
            ZKv(
              label: '退租',
              value: fmtDate(moveOutDate(property)),
              mono: true,
            ),
            ZKv(label: '交租日', value: '每月 ${contract.rentDueDay} 号'),
            ZKv(label: '退租通知', value: '提前 ${contract.noticeDays} 天'),
            ZKv(label: '租住方式', value: contract.rentScope),
            ZKv(
              label: '入住表底数',
              value: readings.isEmpty ? '未记录' : readings.join(' · '),
              divider: false,
            ),
          ],
        ),
      ),
    ],
  );
}

/// 入住取证：张数统计 + 一排缩略图（点开看大图，不能拍、不能删）
Widget _evidenceSection(
  BuildContext context,
  Repository repository,
  Property property,
) {
  final photos = repository.photosOf(property.id);
  final moveIn = photos
      .where((photo) => photo.phase == PhotoPhase.moveIn)
      .toList();
  final moveOut = photos
      .where((photo) => photo.phase == PhotoPhase.moveOut)
      .toList();
  final rooms = property.allRooms;
  final covered = rooms
      .where(
        (room) => moveIn.any((photo) => photo.room == room),
      )
      .length;
  final thumbs = [...moveIn, ...moveOut].take(6).toList();

  return Column(
    children: [
      ZSectionTitle(
        title: '入住取证',
        icon: Icons.photo_camera_outlined,
        moreLabel: '${photos.length} 张',
      ),
      ZCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '入住 ${moveIn.length} 张 · 退租 ${moveOut.length} 张 · '
              '覆盖 $covered/${rooms.length} 房间',
              style: ZText.caption,
            ),
            if (thumbs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('没有留下取证照片', style: ZText.small),
              )
            else ...[
              const SizedBox(height: 10),
              // 固定尺寸的正方形缩略图：只有一两张时也不会被拉成一条长条
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final photo in thumbs)
                    InkWell(
                      onTap: () => showPhoto(
                        context,
                        photo.imageRef,
                        title: '${photo.room} · ${photo.phase.label}',
                      ),
                      child: ZPhoto(
                        ref: photo.thumbRef,
                        width: 52,
                        height: 52,
                        radius: Z.rSm,
                        // 文件读不到就用固定占位图，别写「文件缺失」
                        fallback: const ZMissingPhoto(),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// 房东要求：合同里的特殊条款 + 记过的一条条要求
Widget _rulesSection(Repository repository, Property property) {
  final rules = repository.rulesOf(property.id);
  final special = property.contract.specialTerms.trim();
  // 合同里的特殊条款也算一条房东要求（和详情页那个格子同一个口径）
  final count = landlordRuleCount(property, rules);
  return Column(
    children: [
      ZSectionTitle(
        title: '房东要求',
        icon: Icons.rule_folder_outlined,
        moreLabel: '$count 条',
      ),
      ZCard(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
        child: Column(
          children: [
            if (count == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('没有记录过要求', style: ZText.small),
              ),
            if (special.isNotEmpty)
              ZListRow(
                icon: Icons.description_outlined,
                title: '合同里的特殊条款',
                subtitle: special,
                divider: rules.isNotEmpty,
              ),
            for (var i = 0; i < rules.length; i++)
              ZListRow(
                icon: Icons.check_circle_outline_rounded,
                title: rules[i].source.label,
                subtitle: rules[i].content,
                divider: i != rules.length - 1,
              ),
          ],
        ),
      ),
    ],
  );
}

/// 维修记录：只读列出每一次报修
Widget _repairsSection(Repository repository, Property property) {
  final repairs = repository.repairsOf(property.id);
  return Column(
    children: [
      ZSectionTitle(
        title: '维修记录',
        icon: Icons.build_outlined,
        moreLabel: '${repairs.length} 单',
      ),
      ZCard(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
        child: Column(
          children: [
            if (repairs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('没有维修记录', style: ZText.small),
              ),
            for (var i = 0; i < repairs.length; i++)
              ZListRow(
                icon: Icons.build_outlined,
                title: repairs[i].item,
                subtitle: [
                  fmtDate(repairs[i].reportedAt),
                  repairs[i].status.label,
                  if (repairs[i].description.isNotEmpty)
                    repairs[i].description,
                ].join(' · '),
                divider: i != repairs.length - 1,
              ),
          ],
        ),
      ),
    ],
  );
}

/// 沟通记录：只读列出每条留痕（纠纷/维权时可能还要回看）
Widget _commsSection(Repository repository, Property property) {
  final comms = repository.commsOf(property.id);
  return Column(
    children: [
      ZSectionTitle(
        title: '沟通记录',
        icon: Icons.chat_bubble_outline_rounded,
        moreLabel: '${comms.length} 条',
      ),
      ZCard(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
        child: Column(
          children: [
            if (comms.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('没有沟通留痕', style: ZText.small),
              ),
            for (var i = 0; i < comms.length; i++)
              ZListRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: comms[i].content.isEmpty ? '（没有文字）' : comms[i].content,
                subtitle: [
                  fmtDateTime(comms[i].timestamp),
                  if (comms[i].tags.isNotEmpty) comms[i].tags.join('/'),
                ].join(' · '),
                divider: i != comms.length - 1,
              ),
          ],
        ),
      ),
    ],
  );
}
