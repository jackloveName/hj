import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../compare/compare_page.dart';
import '../evidence/evidence_rooms_page.dart';
import '../kit.dart';
import '../media.dart';
import 'archive_view.dart';
import 'contract_page.dart';
import 'dispute_page.dart';
import 'move_out_page.dart';
import 'property_edit_page.dart';
import 'rules_page.dart';
import 'timeline_page.dart';

class PropertyDetailPage extends StatelessWidget {
  const PropertyDetailPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(propertyId);
    if (property == null) {
      return const ZScreen(
        child: ZEmpty(icon: Icons.search_off_rounded, title: '房源不存在'),
      );
    }

    final health = repository.healthOf(property.id);
    final photos = repository.photoCountOf(property.id);
    final coveredRooms = property.allRooms
        .where((room) => repository.photoCountOf(property.id, room: room) > 0)
        .length;
    // 已退租：整页变成只读归档（回顾 + 各块内容），不再给任何操作入口
    final archived = property.status == PropertyStatus.ended;
    // 已经退租的房子：顶上给一段「租住回顾」，先把这段租住收个尾
    final recap = archived
        ? buildTenancyRecap(
            property: property,
            rents: repository.rentsOf(property.id),
            utilities: repository.utilitiesOf(property.id),
            photos: repository.photosOf(property.id),
          )
        : null;
    // 顶部头图：设定封面就用封面；没设但拍过取证照片，就用照片兜底 ——
    // 只有一张照片都没有时才用内置默认图
    final headerCoverRef = _headerCoverRef(repository, property);

    return ZScreen(
      // 已退租 = 只剩查看：底部不给任何操作；纠纷中只留维权与退租
      bottomBar: canEditProperty(property)
          ? _BottomBar(property: property)
          : property.status == PropertyStatus.dispute
          ? _DisputeBar(property: property)
          : null,
      child: Column(
        children: [
          _Header(
            property: property,
            coverRef: headerCoverRef,
            editable: canEditProperty(property),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (recap != null) ...[
                  _TenancyRecapCard(property: property, recap: recap),
                  const SizedBox(height: 14),
                ],
                if (property.status == PropertyStatus.dispute) ...[
                  _DisputeCard(property: property, repository: repository),
                  const SizedBox(height: 14),
                ],
                if (archived) ...[
                  // 已退租：那六块不再给入口（那些页面天生带「加一条/改一下」），
                  // 内容摊成几段只读展示；存证健康度与维权材料在这个阶段没有意义，
                  // 一并收掉
                  ...buildArchiveSections(
                    context: context,
                    repository: repository,
                    property: property,
                  ),
                ] else ...[
                  _ModuleGrid(
                    property: property,
                    photoCount: photos,
                    roomCount: coveredRooms,
                  ),
                  // 存证健康度只对还在租的房子有意义（都是「还能补什么」的建议）；
                  // 纠纷中看的是维权待办清单，已退租看的是归档内容
                  if (property.status == PropertyStatus.active) ...[
                    const ZSectionTitle(
                      title: '存证健康度',
                      icon: Icons.shield_outlined,
                    ),
                    _HealthCard(health: health),
                  ],
                  const ZSectionTitle(
                    title: '维权材料',
                    icon: Icons.gavel_outlined,
                  ),
                  ZCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        ZListRow(
                          icon: Icons.compare_arrows_rounded,
                          title: '退租对比报告',
                          subtitle: '入住 / 退租左右对照，一键导出 PDF',
                          onTap: () => zPush(
                            context,
                            ComparePage(propertyId: property.id),
                          ),
                        ),
                        ZListRow(
                          icon: Icons.rule_folder_outlined,
                          title: '房东要求',
                          subtitle:
                              '${landlordRuleCount(property, repository.rulesOf(property.id))} 条约定'
                              ' · 退租时的重要依据',
                          onTap: () =>
                              zPush(context, RulesPage(propertyId: property.id)),
                          divider: false,
                        ),
                      ],
                    ),
                  ),
                  const ZSectionTitle(
                    title: '退租与纠纷',
                    icon: Icons.key_outlined,
                  ),
                  ZCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        // 房源状态只在这两条路上变：退租走一整页的结算
                        // （押金 + 与房东对接），纠纷就是把状态标上并写清原因
                        // （在押金页改押金状态不会动房源状态）
                        ZListRow(
                          icon: Icons.key_outlined,
                          title: '去退租',
                          subtitle: '租住走完了：结算押金、记下与房东的交接',
                          onTap: () => zPush(
                            context,
                            MoveOutPage(propertyId: property.id),
                          ),
                          // 已经在纠纷中时下面那行不出现，这行就是最后一行
                          divider: property.status != PropertyStatus.dispute,
                        ),
                        // 已经是纠纷中了就不再给这个入口：事情已经进入维权流程，
                        // 再点一次除了把状态重写一遍没有意义（要改原因走押金追踪的维权备注）
                        if (property.status != PropertyStatus.dispute)
                          ZListRow(
                            icon: Icons.gavel_outlined,
                            title: '去纠纷',
                            subtitle: '押金有争议：标记纠纷并写清原因',
                            onTap: () => zPush(
                              context,
                              DisputePage(propertyId: property.id),
                            ),
                            divider: false,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                // 加错了的房子（或者只是想清掉）总得能删：入口放最后，
                // 二次确认里写清会连照片和记录一起删
                Center(
                  child: TextButton.icon(
                    onPressed: () =>
                        _confirmDelete(context, repository, property),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: Z.dangerDeep,
                    ),
                    label: Text(
                      '删除这套房源',
                      style: ZText.label.copyWith(color: Z.dangerDeep),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部头图用哪张：**设了封面就用封面**；没设但拍过取证照片，就用照片兜底
  /// （优先入住取证，和「设封面」的默认口径一致；否则用最新那张）。
  /// 一张照片都没有时才返回 null，交给内置默认底图。
  String? _headerCoverRef(Repository repository, Property property) {
    final cover = property.coverRef;
    if (cover != null && cover.isNotEmpty) return cover;
    final photos = repository.photosOf(property.id);
    if (photos.isEmpty) return null;
    final moveIn = photos.where((photo) => photo.phase == PhotoPhase.moveIn);
    final pick = moveIn.isNotEmpty ? moveIn.first : photos.first;
    return pick.thumbRef.isNotEmpty ? pick.thumbRef : pick.imageRef;
  }

  /// 删除整套房子（含照片与全部记录）。
  ///
  /// 这是不可恢复的操作，二次确认里要把「会删掉什么」和「更好的做法」都写清楚：
  /// 想结束租约走「退租」，要留证据就先导出报告或照片包。
  Future<void> _confirmDelete(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    final photos = repository.photosOf(property.id).length;
    final ok = await zConfirm(
      context,
      title: '删除「${property.name}」？',
      message:
          '会连同这套房的 $photos 张照片、合同与全部记录一起删掉，删了拿不回来。\n\n'
          '只是想结束租约的话，用「退租」；要拿去维权的话，先导出对比报告。',
      confirmText: '删除',
      cancelText: '再想想',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await repository.deleteProperty(property.id);
    if (!context.mounted) return;
    // 房子没了，这一页也就没有内容可看了，退回上一页
    Navigator.of(context).maybePop();
    zToast(context, '已删除「${property.name}」');
  }
}

/// 纠纷中的状态卡：争的是什么、扣了多少、手里有什么、接下来做什么。
///
/// 和「已退租」的回顾卡是同一种角色 —— 顶上先把状态说清楚，
/// 底下才是各块资料。红底浅色卡（和押金卡同一个调色板），
/// 一眼就知道这套房子现在是「有事要办」的状态。
class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.property, required this.repository});

  final Property property;
  final Repository repository;

  @override
  Widget build(BuildContext context) {
    final deposit = property.deposit;
    final (bg, fg) = ZTag.paletteOf(ZTone.danger);
    final markedAt = deposit.logs
        .where((log) => log.status == DepositStatus.inDispute)
        .map((log) => log.time)
        .fold<DateTime?>(null, (best, time) => best == null || time.isAfter(best) ? time : best);
    final moveOutPhotos = repository
        .photosOf(property.id)
        .where((photo) => photo.phase == PhotoPhase.moveOut)
        .length;
    final comms = repository.commsOf(property.id).length;

    return ZCard(
      color: bg,
      border: Border.all(color: fg.withValues(alpha: 0.25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_outlined, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                '押金纠纷 · 维权中',
                style: ZText.labelStrong.copyWith(color: fg),
              ),
              const Spacer(),
              ZPill(label: '纠纷中', background: bg, foreground: fg),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            deposit.deductedAmount > 0
                ? '被扣 ${fmtMoney(deposit.deductedAmount)}'
                      '${deposit.deductReason.isEmpty ? '' : ' · ${deposit.deductReason}'}'
                : property.contract.deposit > 0
                ? '押金 ${fmtMoney(property.contract.deposit)} 还没退到手'
                : '押金还没结清',
            style: ZText.title3.copyWith(fontSize: 18, height: 1.35),
          ),
          if (deposit.disputeNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '原因：${deposit.disputeNote}',
              style: ZText.caption.copyWith(height: 1.5),
            ),
          ],
          if (markedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              '${fmtDate(markedAt)} 标记为纠纷',
              style: ZText.small,
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: fg.withValues(alpha: 0.18)),
          const SizedBox(height: 10),
          Text('维权要做的事', style: ZText.label.copyWith(fontSize: 13)),
          const SizedBox(height: 6),
          _DisputeStep(
            done: moveOutPhotos > 0,
            text: moveOutPhotos > 0
                ? '退租照片已留 $moveOutPhotos 张：对比报告靠它'
                : '先把退租照片拍全：对比报告靠它',
          ),
          _DisputeStep(
            done: comms > 0,
            text: comms > 0
                ? '沟通留痕 $comms 条：纠纷期间还能继续补'
                : '每次交涉都记一条沟通（纠纷期间也能记）',
          ),
          const _DisputeStep(
            done: false,
            text: '点下面「去维权」导出对比报告与催告函',
            last: true,
          ),
        ],
      ),
    );
  }
}

/// 纠纷卡里的一条「该做的事」：做完的打勾，没做的留着提醒
class _DisputeStep extends StatelessWidget {
  const _DisputeStep({
    required this.done,
    required this.text,
    this.last = false,
  });

  final bool done;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 15,
            color: done ? Z.okDeep : Z.ink3,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: ZText.caption.copyWith(
                height: 1.45,
                color: done ? Z.ink2 : Z.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 已退租房子的「租住回顾」：住过多久、花了多少、留下多少证据。
///
/// 放在详情页最上面：这段租住已经结束了，先让人看一眼全貌，
/// 再往下翻照片、合同这些材料。深蓝底沿用费用页汇总卡的样式。
class _TenancyRecapCard extends StatelessWidget {
  const _TenancyRecapCard({required this.property, required this.recap});

  final Property property;
  final TenancyRecap recap;

  @override
  Widget build(BuildContext context) {
    final deposit = property.deposit;
    return ZCard(
      gradient: Z.navyGradient,
      shadow: Z.e2,
      border: Border.all(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_stories_outlined,
                size: 14,
                color: Z.onDarkMuted,
              ),
              const SizedBox(width: 6),
              Text('租住回顾', style: _labelStyle),
              const Spacer(),
              // 押金没退到手就在这儿挂一颗，退出再进来也一眼看得到
              // （按状态判断：金额没填也算没退到手）
              if (depositNotBack(property)) ...[
                ZPill(
                  label: '押金未退',
                  background: Z.warn.withValues(alpha: 0.22),
                  foreground: const Color(0xFFFFD8A0),
                ),
                const SizedBox(width: 6),
              ],
              ZPill(
                label: '已退租',
                background: Colors.white.withValues(alpha: 0.14),
                foreground: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '和「${property.name}」一起住了 ${recap.days} 天',
            style: ZText.title3.copyWith(
              fontSize: 19,
              color: Colors.white,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${fmtDate(recap.moveInDate)} 入住 · ${fmtDate(recap.moveOutDate)} 退租',
            style: _labelStyle.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.14),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _RecapStat(label: '月租', value: fmtMoney(property.contract.monthlyRent)),
              _RecapStat(label: '合同', value: '${recap.contractMonths} 个月'),
              _RecapStat(label: '实付', value: '${recap.paidMonths} 期'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _RecapStat(label: '一共付了房租', value: fmtMoney(recap.paidRent)),
              _RecapStat(
                label: '水电燃气',
                value: recap.utilityRecords == 0
                    ? '无记录'
                    : fmtMoney(recap.utilityCost),
              ),
              _RecapStat(
                label: '存证照片',
                value: recap.photos == 0
                    ? '0 张'
                    : '${recap.photos} 张',
                hint: recap.photos == 0
                    ? null
                    : '入住 ${recap.moveInPhotos} · 退租 ${recap.moveOutPhotos}',
              ),
            ],
          ),
          if (property.contract.deposit > 0) ...[
            const SizedBox(height: 12),
            Text(_depositSummary(deposit), style: _labelStyle.copyWith(fontSize: 12)),
            // 押金还没退到手：给一个单向操作，退到了就记下来。
            // 记完这一页不再给改（改错了走「押金追踪」）
            if (deposit.status == DepositStatus.toBeReturned) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _markDepositReturned(context, property),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text('押金已退到手'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            deposit.handoverDone
                ? '钥匙、水电、验收都和房东对完了，这段租住收尾了。'
                : '房间交回去了，照片、费用和维权材料都还留着。',
            style: _labelStyle.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 押金到账了：记下「已退还 + 金额 + 日期」，留一条日志。
  ///
  /// 单向操作 —— 退过之后这一页不再给入口（押金是既成事实，
  /// 真要改金额/状态，去「押金追踪」那页）。
  Future<void> _markDepositReturned(
    BuildContext context,
    Property property,
  ) async {
    final total = property.contract.deposit;
    final ok = await zConfirm(
      context,
      title: '押金已退到手',
      message: '押金 ${fmtMoney(total)} 已经收到？'
          '记下来之后房源详情页就不给改了。',
      confirmText: '已收到',
      cancelText: '还没',
    );
    if (!ok || !context.mounted) return;
    final repository = context.read<Repository>();
    final latest = repository.propertyById(property.id);
    if (latest == null) return;
    final deposit = latest.deposit;
    final now = DateTime.now();
    final oldNote = deposit.disputeNote.trim();
    await repository.updateProperty(
      latest.copyWith(
        deposit: deposit.copyWith(
          status: DepositStatus.returned,
          returnedAmount: total,
          returnedDate: now,
          // 全额退到手就不该再挂扣款（历史日志留着，别把过程抹掉）
          deductedAmount: 0,
          deductReason: '',
          // 维权备注只在维权期间有意义：退到手就从明细收起来，
          // 原内容写进下面这条日志
          disputeNote: '',
          logs: [
            ...deposit.logs,
            DepositLog(
              status: DepositStatus.returned,
              time: now,
              note:
                  '押金 ${fmtMoney(total)} 已退还'
                  '${oldNote.isEmpty ? '' : ' · 原维权备注：$oldNote'}',
            ),
          ],
        ),
      ),
      touch: false,
    );
    if (context.mounted) zToast(context, '记下了：押金已退还');
  }

  /// 押金那一句：退了 / 被扣 / 还在等，说清楚退了多少、扣了什么
  String _depositSummary(DepositInfo deposit) {
    final total = fmtMoney(property.contract.deposit);
    return switch (deposit.status) {
      DepositStatus.returned =>
        '押金 $total 已全额退还'
            '${deposit.returnedDate == null ? '' : '（${fmtDate(deposit.returnedDate!)}）'}',
      DepositStatus.partiallyDeducted =>
        '押金 $total 退回 ${fmtMoney(deposit.returnedAmount)}'
            '，被扣 ${fmtMoney(deposit.deductedAmount)}'
            '${deposit.deductReason.isEmpty ? '' : '（${deposit.deductReason}）'}',
      DepositStatus.none => '这套房没有押金',
      // 押金没到手也能退租：这里照实写「未退还」，别让人以为已经退清了
      _ => '押金 $total 未退还（还在房东手里）',
    };
  }
}

/// 深蓝底上的小统计：标签压暗、数字亮白
class _RecapStat extends StatelessWidget {
  const _RecapStat({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _labelStyle),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZText.title4.copyWith(fontSize: 15, color: Colors.white),
          ),
          if (hint != null)
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _labelStyle.copyWith(fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// 深蓝底上的标签文字：统一一处，免得每行各写一遍颜色和字号
const TextStyle _labelStyle = TextStyle(
  fontFamily: Z.font,
  fontFamilyFallback: Z.fallback,
  fontSize: 12.5,
  color: Z.onDarkMuted,
);

class _Header extends StatelessWidget {
  const _Header({
    required this.property,
    required this.coverRef,
    required this.editable,
  });

  final Property property;
  final String? coverRef;

  /// 非租住中（已退租 / 纠纷中）不给「编辑房源」入口：历史只能看
  final bool editable;

  @override
  Widget build(BuildContext context) {
    // 高度跟着系统字体放大走：写死 168 时，320 宽的小屏 + 1.2 倍字
    // 会把底部的状态胶囊挤出画面
    return SizedBox(
      // +20 是余量：320 宽时底部三枚胶囊会换成两行，加上 1.2 倍字号需要的高度
      height: MediaQuery.textScalerOf(context).scale(168) + 20,
      child: ZPhoto(
        ref: coverRef,
        radius: 0,
        // 没传封面、或封面文件已经丢了（换机只导了 JSON 之类的），
        // 就退回内置底图 —— 头图位置写「文件缺失」太扎眼，也不像首页该有的样子
        fallback: const ZDefaultCover(scrim: false),
        overlay: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xBD08142C),
                const Color(0x0D08142C),
                const Color(0xA808142C).withValues(alpha: 0.66),
              ],
              stops: const [0, 0.46, 1],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 头图上的返回键用统一组件，别各页自己拼
                  const ZBackButton(onDark: true),
                  const SizedBox(width: 6),
                  const Text(
                    '返回房源',
                    style: TextStyle(
                      fontFamily: Z.font,
                      fontFamilyFallback: Z.fallback,
                      fontSize: 12,
                      color: Color(0xCCFFFFFF),
                    ),
                  ),
                  const Spacer(),
                  // 已退租 / 纠纷中不给编辑入口：从「历史租住」点进来是回顾过去
                  if (editable)
                    InkWell(
                      onTap: () => zPush(
                        context,
                        PropertyEditPage(propertyId: property.id),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                property.name,
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${property.address}${property.subtitle.isEmpty ? '' : ' · ${property.subtitle}'}',
                style: const TextStyle(
                  fontFamily: Z.font,
                  fontFamilyFallback: Z.fallback,
                  fontSize: 12,
                  color: Color(0xC7FFFFFF),
                ),
              ),
              const SizedBox(height: 10),
              // 三枚胶囊在窄屏上放不下，用 Wrap 让它自然换行，不再横向溢出
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  ZPill(
                    label: property.status.label,
                    background: statusPillColor(property.status),
                    foreground: Colors.white,
                  ),
                  ZPill(
                    // 租住结束（已退租 / 纠纷中）之后按「退租日」算，
                    // 不能再跟着今天一直涨；口径也和租住回顾一致（含首尾）
                    label: property.status == PropertyStatus.active
                        ? stayDurationLabel(property.contract.moveInDate)
                        : '已入住 ${livedDays(property)} 天',
                    background: const Color(0x2EFFFFFF),
                    foreground: Colors.white,
                  ),
                  ZPill(
                    label: '${fmtDate(property.contract.contractEnd)} 到期',
                    background: const Color(0x2EFFFFFF),
                    foreground: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({
    required this.property,
    required this.photoCount,
    required this.roomCount,
  });

  final Property property;
  final int photoCount;
  final int roomCount;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final repairs = repository.repairsOf(property.id);
    final pendingRepairs = repairs
        .where((r) => r.status != RepairStatus.completed)
        .length;
    final moveOutCount = repository.photoCountOf(
      property.id,
      phase: PhotoPhase.moveOut,
    );

    final modules = <_Module>[
      _Module(
        icon: Icons.photo_camera_outlined,
        label: '入住取证',
        hint: '$photoCount 张 / ${property.allRooms.length} 房间',
        badge: '核心',
        onTap: () => zPush(context, EvidenceRoomsPage(propertyId: property.id)),
      ),
      _Module(
        icon: Icons.description_outlined,
        label: '合同信息',
        hint: '13 个字段',
        onTap: () => zPush(context, ContractPage(propertyId: property.id)),
      ),
      _Module(
        icon: Icons.warning_amber_rounded,
        label: '房东要求',
        hint: '${landlordRuleCount(property, repository.rulesOf(property.id))} 条约定',
        tone: ZTone.warn,
        onTap: () => zPush(context, RulesPage(propertyId: property.id)),
      ),
      _Module(
        icon: Icons.build_outlined,
        label: '维修记录',
        hint:
            '${repairs.length} 单'
            '${pendingRepairs > 0 ? ' · $pendingRepairs 待处理' : ''}',
        onTap: () => zPush(
          context,
          TimelinePage(propertyId: property.id, initialTab: 0),
        ),
      ),
      _Module(
        icon: Icons.chat_bubble_outline_rounded,
        label: '沟通记录',
        hint: '${repository.commsOf(property.id).length} 条留痕',
        onTap: () => zPush(
          context,
          TimelinePage(propertyId: property.id, initialTab: 1),
        ),
      ),
      _Module(
        icon: Icons.compare_arrows_rounded,
        label: '退租对比',
        hint: moveOutCount > 0 ? '$moveOutCount 张已拍' : '未开始',
        tone: ZTone.violet,
        emphasize: true,
        onTap: () => zPush(context, ComparePage(propertyId: property.id)),
      ),
    ];

    // 格子高度按「内容需要多少」给（106），不再用宽高比：
    // 320pt 小屏上宽高比算出来的格子比内容还矮，大字号下直接溢出
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        // 112 = 内容在 1.2 倍字号下需要的高度 + 一点取整余量
        mainAxisExtent: 112,
      ),
      children: [for (final module in modules) _ModuleTile(module: module)],
    );
  }
}

class _Module {
  const _Module({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.badge,
    this.tone = ZTone.brand,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final String? badge;
  final ZTone tone;
  final bool emphasize;
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final _Module module;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ZTag.paletteOf(module.tone);
    return ZCard(
      padding: const EdgeInsets.fromLTRB(8, 13, 8, 12),
      border: module.emphasize
          ? Border.all(color: Z.violet.withValues(alpha: 0.3), width: 1.4)
          : null,
      gradient: module.emphasize
          ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Z.card, const Color(0x0D6C4BD8)],
            )
          : null,
      onTap: module.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(module.icon, size: 17, color: fg),
              ),
              const SizedBox(height: 7),
              Text(
                module.label,
                style: ZText.label.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                module.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZText.small.copyWith(fontSize: 11),
              ),
            ],
          ),
          if (module.badge != null)
            Positioned(
              right: -4,
              top: -6,
              child: ZPill(
                label: module.badge!,
                background: Z.brand,
                foreground: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final EvidenceHealth health;

  @override
  Widget build(BuildContext context) {
    final percent = (health.ratio * 100).round();
    final color = percent >= 80 ? Z.ok : (percent >= 50 ? Z.warn : Z.danger);
    return ZCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(height: 7, color: Z.line2),
                      FractionallySizedBox(
                        widthFactor: health.ratio.clamp(0.02, 1.0),
                        child: Container(
                          height: 7,
                          decoration: const BoxDecoration(
                            gradient: Z.healthGradient,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$percent%',
                style: ZText.label.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < health.items.length; i++)
            ZKv(
              label: health.items[i].label,
              value: health.items[i].hint,
              valueColor: health.items[i].ok ? Z.ok : Z.warnDeep,
              divider: i != health.items.length - 1,
            ),
        ],
      ),
    );
  }
}

/// 纠纷中只剩两件事：继续维权（对比报告 / 沟通留证）和把押金结算掉
class _DisputeBar extends StatelessWidget {
  const _DisputeBar({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return ZBottomBar(
      child: Row(
        children: [
          Expanded(
            child: ZButton(
              label: '去维权',
              style: ZButtonStyle.dark,
              icon: Icons.gavel_outlined,
              // 和「押金纠纷维权中」那条待办同一个落点
              onTap: () => zPush(context, ComparePage(propertyId: property.id)),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: ZButton(
              label: '退租',
              style: ZButtonStyle.ghost,
              icon: Icons.key_outlined,
              onTap: () => zPush(context, MoveOutPage(propertyId: property.id)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return ZBottomBar(
      child: Row(
        children: [
          SizedBox(
            // 图标 + 「补充取证」四个字需要的宽度，108 会差几个像素
            width: 122,
            child: ZButton(
              label: '补充取证',
              style: ZButtonStyle.ghost,
              icon: Icons.photo_camera_outlined,
              onTap: () =>
                  zPush(context, EvidenceRoomsPage(propertyId: property.id)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ZButton(
              label: '开始退租对比',
              style: ZButtonStyle.dark,
              icon: Icons.compare_arrows_rounded,
              onTap: () => zPush(context, ComparePage(propertyId: property.id)),
            ),
          ),
        ],
      ),
    );
  }
}
