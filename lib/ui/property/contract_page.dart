import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../services/contract_scanner.dart';
import '../../theme/tokens.dart';
import '../../utils/format.dart';
import '../kit.dart';
import '../media.dart';
import '../pickers.dart';
import 'property_edit_page.dart';

class ContractPage extends StatelessWidget {
  const ContractPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<Repository>();
    final property = repository.propertyById(propertyId);
    if (property == null) {
      return const ZScreen(child: SizedBox.shrink());
    }
    final contract = property.contract;
    final missing = <String>[
      if (contract.earlyTermination.isEmpty) '提前退租条件',
      if (contract.renewalTerms.isEmpty) '续租条款',
      if (contract.contractPhotoRefs.isEmpty) '合同照片',
    ];

    return ZScreen(
      bottomBar: _BottomBar(property: property),
      child: Column(
        children: [
          ZAppBar(
            leading: const ZBackButton(),
            title: '合同信息',
            actions: [
              InkWell(
                onTap: () => _scan(context, repository, property),
                child: ZPill(
                  label: '风险扫描',
                  background: Z.brandTint,
                  foreground: Z.brand,
                  icon: Icons.auto_awesome_outlined,
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const ZHintBar(
                  text: '填完自动生成 交租计划 与 到期倒计时，并写入本地提醒。',
                  icon: Icons.bolt_outlined,
                ),
                const ZSectionTitle(
                  title: '出租方',
                  icon: Icons.person_outline_rounded,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  onTap: () =>
                      zPush(context, PropertyEditPage(propertyId: property.id)),
                  child: Column(
                    children: [
                      ZKv(label: '房东姓名', value: property.landlord.name),
                      ZKv(
                        label: '联系电话',
                        value: property.landlord.phone.isEmpty
                            ? '未填写'
                            : property.landlord.phone,
                        divider: property.landlord.wechat.isNotEmpty,
                      ),
                      if (property.landlord.wechat.isNotEmpty)
                        ZKv(
                          label: '微信 / 其他',
                          value: property.landlord.wechat,
                          divider: false,
                        ),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '金额与周期',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  onTap: () =>
                      zPush(context, PropertyEditPage(propertyId: property.id)),
                  child: Column(
                    children: [
                      ZKv(
                        label: '月租金额',
                        value: '${fmtMoney(contract.monthlyRent)} / 月',
                        valueColor: Z.ink,
                      ),
                      ZKv(
                        label: '押金金额',
                        value: fmtMoney(contract.deposit),
                        valueColor: Z.warnDeep,
                      ),
                      ZKv(
                        label: '付款方式',
                        value: contract.paymentMethod,
                        divider: false,
                      ),
                    ],
                  ),
                ),
                const ZSectionTitle(
                  title: '关键日期',
                  icon: Icons.event_available_outlined,
                ),
                ZCard(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  onTap: () =>
                      zPush(context, PropertyEditPage(propertyId: property.id)),
                  child: Column(
                    children: [
                      ZKv(
                        label: '入住日期',
                        value: fmtDate(contract.moveInDate),
                        mono: true,
                        valueColor: Z.ink,
                      ),
                      ZKv(
                        label: '合同到期',
                        value: fmtDate(contract.contractEnd),
                        mono: true,
                        valueColor: Z.ink,
                      ),
                      ZKv(
                        label: '交租日',
                        value: '每月 ${contract.rentDueDay} 号',
                      ),
                      ZKv(
                        label: '退租通知',
                        value: '需提前 ${contract.noticeDays} 天通知房东',
                      ),
                      ZKv(
                        label: '租住方式',
                        value: contract.rentScope,
                        divider: false,
                      ),
                    ],
                  ),
                ),
                ZSectionTitle(
                  title: '合同照片（选填）',
                  icon: Icons.image_outlined,
                  moreLabel: '${contract.contractPhotoRefs.length} / 6 页',
                ),
                _ContractPhotos(property: property),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ZHintBar(
                    text: '未填写：${missing.join('、')} — 建议补全，否则退租时无据可依。',
                    tone: ZTone.warn,
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scan(
    BuildContext context,
    Repository repository,
    Property property,
  ) async {
    final risks = scanContract(property.contract);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Text('合同风险扫描', style: ZText.title3.copyWith(fontSize: 17)),
            const SizedBox(height: 4),
            Text(
              risks.isEmpty
                  ? '未发现明显的风险关键词，仍建议逐条核对合同原文。'
                  : '共发现 ${risks.length} 处需要留意的地方',
              style: ZText.caption,
            ),
            const SizedBox(height: 14),
            for (final risk in risks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ZTag.paletteOf(risk.tone).$1,
                    borderRadius: BorderRadius.circular(Z.rLg),
                    border: Border.all(
                      color: ZTag.paletteOf(risk.tone).$2
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ZTag(
                            label: switch (risk.tone) {
                              ZTone.danger => '高风险',
                              ZTone.warn => '需注意',
                              _ => '提示',
                            },
                            tone: risk.tone,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              risk.title,
                              style: ZText.label.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        risk.detail,
                        style: ZText.caption.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.tips_and_updates_outlined,
                            size: 15,
                            color: Z.brand,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              risk.advice,
                              style: ZText.body.copyWith(
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ContractPhotos extends StatelessWidget {
  const _ContractPhotos({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final refs = property.contract.contractPhotoRefs;
    return Row(
      children: [
        for (var i = 0; i < refs.length; i++) ...[
          Expanded(
            child: InkWell(
              onTap: () => showPhoto(context, refs[i], title: '合同照片'),
              child: ZPhoto(
                ref: refs[i],
                height: 56,
                watermark: ['第 ${i + 1} 页'],
              ),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: InkWell(
            onTap: () => _add(context),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Z.rSm),
                border: Border.all(color: Z.dashed, width: 1.4),
              ),
              child: Icon(Icons.add_rounded, size: 18, color: Z.ink4),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final repository = context.read<Repository>();
    final bytes = await pickImage(context);
    if (bytes == null) return;
    final ref = await repository.saveMedia(
      bytes,
      folder: property.id,
      name: 'contract_${newId('c')}.jpg',
    );
    await repository.updateProperty(
      property.copyWith(
        contract: property.contract.copyWith(
          contractPhotoRefs: [...property.contract.contractPhotoRefs, ref],
        ),
      ),
    );
    if (context.mounted) zToast(context, '合同照片已保存');
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return ZBottomBar(
      child: ZButton(
        label: '保存并生成提醒计划',
        onTap: () async {
          final repository = context.read<Repository>();
          await repository.updateProperty(property);
          if (!context.mounted) return;
          zToast(
            context,
            '已生成：每月 ${property.contract.rentDueDay} 号交租，'
            '${fmtDate(property.contract.contractEnd)} 到期',
          );
        },
      ),
    );
  }
}
