import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart' show idbFactoryMemory;
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:zudun/app.dart';
import 'package:zudun/content/legal.dart';
import 'package:zudun/content/templates.dart';
import 'package:zudun/data/cloud_bridge.dart';
import 'package:zudun/data/cloud_ref.dart';
import 'package:zudun/data/media_cache_name.dart';
import 'package:zudun/data/media_idb.dart';
import 'package:zudun/data/repository.dart';
import 'package:zudun/main.dart';
import 'package:zudun/models/models.dart';
import 'package:zudun/services/api/api_client.dart';
import 'package:zudun/services/api/api_settings.dart';
import 'package:zudun/services/api/config_api.dart';
import 'package:zudun/services/api/password_crypto.dart';
import 'package:zudun/services/app_update.dart';
import 'package:zudun/services/cloud_service.dart';
import 'package:zudun/services/contract_scanner.dart';
import 'package:zudun/services/error_log.dart';
import 'package:zudun/services/notification_plan.dart';
import 'package:zudun/services/notification_service.dart';
import 'package:zudun/services/pdf_service.dart';
import 'package:zudun/services/session.dart';
import 'package:zudun/services/watermark.dart';
import 'package:zudun/theme/app_theme.dart';
import 'package:zudun/theme/tokens.dart';
import 'package:zudun/ui/app_update_dialog.dart';
import 'package:zudun/ui/auth/account_page.dart';
import 'package:zudun/ui/auth/login_page.dart';
import 'package:zudun/ui/compare/compare_page.dart';
import 'package:zudun/ui/evidence/evidence_rooms_page.dart';
import 'package:zudun/ui/evidence/room_album_page.dart';
import 'package:zudun/ui/expense/deposit_page.dart';
import 'package:zudun/ui/expense/expense_page.dart';
import 'package:zudun/ui/expense/utility_edit_page.dart';
import 'package:zudun/ui/expense/utility_history_page.dart';
import 'package:zudun/ui/expense/utility_page.dart';
import 'package:zudun/ui/home/home_page.dart';
import 'package:zudun/ui/kit.dart';
import 'package:zudun/ui/media.dart';
import 'package:zudun/ui/profile/about_page.dart';
import 'package:zudun/ui/profile/error_log_page.dart';
import 'package:zudun/ui/profile/legal_guide_page.dart';
import 'package:zudun/ui/profile/privacy_page.dart';
import 'package:zudun/ui/profile/profile_page.dart';
import 'package:zudun/ui/profile/reminder_settings_page.dart';
import 'package:zudun/ui/profile/templates_page.dart';
import 'package:zudun/ui/property/contract_page.dart';
import 'package:zudun/ui/property/history_page.dart';
import 'package:zudun/ui/property/property_detail_page.dart';
import 'package:zudun/ui/property/property_edit_page.dart';
import 'package:zudun/ui/property/rules_page.dart';
import 'package:zudun/ui/property/tenancy_page.dart';
import 'package:zudun/ui/property/timeline_page.dart';
import 'package:zudun/ui/shell.dart';
import 'package:zudun/utils/contrast.dart';
import 'package:zudun/utils/font_charset.dart';
import 'package:zudun/utils/format.dart';

/// 假通知通道：把调用记下来，用来验证「排期 / 清空」逻辑而不依赖真机
class _FakeNotificationChannel implements NotificationChannel {
  _FakeNotificationChannel({this.supported = true, this.granted = true});

  /// false 模拟「这个平台没实现」，用于验证降级路径
  final bool supported;
  final bool granted;

  final List<NotificationPlan> scheduled = [];
  final List<int> shown = [];
  int cancelAllCount = 0;
  int cancelPendingCount = 0;
  void Function(String? payload)? onTap;

  @override
  bool get supportsScheduling => true;

  @override
  Future<bool> init({required void Function(String? payload) onTap}) async {
    if (!supported) throw MissingPluginException('假通道：这个平台没实现通知');
    this.onTap = onTap;
    return true;
  }

  @override
  Future<NotificationPermission> requestPermission() async =>
      granted ? NotificationPermission.granted : NotificationPermission.denied;

  @override
  Future<void> schedule(NotificationPlan plan) async => scheduled.add(plan);

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async => shown.add(id);

  @override
  Future<void> cancelPending() async => cancelPendingCount++;

  @override
  Future<void> cancelAll() async => cancelAllCount++;

  int openSettingsCount = 0;

  @override
  Future<bool> openSystemSettings() async {
    openSettingsCount++;
    return true;
  }
}

Property buildProperty() => Property(
  id: 'p1',
  name: '翠屏里 3 栋 502',
  address: '北京市朝阳区望京街道',
  area: '89㎡',
  layout: '两室一厅',
  landlord: const Landlord(name: '张建国', phone: '138****6677'),
  contract: ContractInfo(
    monthlyRent: 3200,
    deposit: 8000,
    paymentMethod: '押一付三',
    moveInDate: DateTime(2026, 3, 1),
    contractEnd: DateTime(2026, 12, 31),
    rentDueDay: 13,
    specialTerms: '不可养宠物，退租需恢复原状。',
  ),
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 1),
);

/// 已经退租、押金已退还的一套房子（历史记录用）
Property buildHistoryProperty() => Property(
  id: 'p2',
  name: '以前住的房子',
  address: '北京市海淀区知春路 12 号院 3 号楼',
  area: '60㎡',
  layout: '一室一厅',
  landlord: const Landlord(name: '李房东', phone: '139****0000'),
  contract: ContractInfo(
    monthlyRent: 2600,
    deposit: 6000,
    paymentMethod: '押一付三',
    moveInDate: DateTime(2025, 9, 1),
    contractEnd: DateTime(2026, 8, 31),
    rentDueDay: 5,
  ),
  status: PropertyStatus.ended,
  deposit: DepositInfo(
    status: DepositStatus.returned,
    returnedAmount: 6000,
    returnedDate: DateTime(2026, 9, 30),
  ),
  createdAt: DateTime(2025, 9, 1),
  updatedAt: DateTime(2026, 9, 30),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('格式化工具', () {
    test('金额千分位与小数处理', () {
      expect(fmtMoney(8000), '¥8,000');
      expect(fmtMoney(3200.5), '¥3,200.50');
      expect(fmtAmount(234.6), '234.60');
    });

    test('下次交租日跨月计算', () {
      expect(
        nextRentDue(13, from: DateTime(2026, 10, 20)),
        DateTime(2026, 11, 13),
      );
      expect(
        nextRentDue(25, from: DateTime(2026, 3, 3)),
        DateTime(2026, 3, 25),
      );
    });

    test('环比趋势描述', () {
      expect(trendNote([100, 119]), '较上月偏高 19%');
      expect(trendNote([100, 80]), '较上月下降 20%');
      expect(trendNote([100, 100]), '较上月基本持平');
    });
  });

  group('数据模型', () {
    test('房源序列化往返一致', () {
      final property = buildProperty();
      final restored = Property.fromJson(property.toJson());
      expect(restored.name, property.name);
      expect(restored.layout, '两室一厅');
      expect(restored.contract.monthlyRent, 3200);
      expect(restored.contract.rentDueDay, 13);
      expect(restored.contract.contractEnd, DateTime(2026, 12, 31));
      expect(restored.deposit.status, DepositStatus.paid);
    });

    test('水电读数自动算用量与费用', () {
      const reading = UtilityReading(
        reading: 25814,
        previousReading: 25620,
        unitPrice: 0.55,
      );
      expect(reading.usage, 194);
      expect(reading.cost, closeTo(106.7, 0.001));
    });

    test('表读数倒退时用量为 0', () {
      const reading = UtilityReading(reading: 100, previousReading: 200);
      expect(reading.usage, 0);
    });

    test('标注坐标可序列化并保持精度', () {
      final photo = EvidencePhoto(
        id: 'e1',
        propertyId: 'p1',
        room: '主卧',
        imageRef: 'a.jpg',
        thumbRef: 'a_t.jpg',
        timestamp: DateTime(2026, 3, 1, 10, 24),
        issueType: IssueType.floor,
        description: '地板 2 处划痕，入住前已有',
        annotations: const [
          AnnotationShape(
            type: 'circle',
            points: [Offset(0.34, 0.26), Offset(0.47, 0.33)],
          ),
          AnnotationShape(type: 'text', points: [Offset(0.6, 0.5)], text: '划痕'),
        ],
      );
      final restored = EvidencePhoto.fromJson(photo.toJson());
      expect(restored.annotations.length, 2);
      expect(restored.annotations.first.points.first.dx, closeTo(0.34, 0.0001));
      expect(restored.annotations.last.text, '划痕');
    });

    test('未知枚举值回退默认状态', () {
      final json = buildProperty().toJson();
      json['status'] = 'unknown_status';
      expect(Property.fromJson(json).status, PropertyStatus.active);
    });

    test('押金六态与租金三态标签完整', () {
      expect(DepositStatus.values.length, 6);
      expect(DepositStatus.none.label, '无押金');
      expect(DepositStatus.returned.label, '已退还');
      expect(RentStatus.values.length, 3);
      expect(RentStatus.overdue.label, '逾期');
    });
  });

  group('合同风险扫描', () {
    test('押金不退属于高风险', () {
      final risks = scanContract(
        ContractInfo(
          moveInDate: DateTime(2026, 3, 1),
          contractEnd: DateTime(2026, 12, 31),
          specialTerms: '提前退租押金不退。',
        ),
      );
      expect(risks.any((risk) => risk.tone.name == 'danger'), isTrue);
    });

    test('押金高于 1.5 个月租金会提示', () {
      final risks = scanContract(
        ContractInfo(
          monthlyRent: 3000,
          deposit: 9000,
          moveInDate: DateTime(2026, 3, 1),
          contractEnd: DateTime(2026, 12, 31),
        ),
      );
      expect(risks.any((risk) => risk.title.contains('押金高于')), isTrue);
    });
  });

  group('法规与文书内容', () {
    test('法规指南包含四个板块', () {
      expect(legalArticles.length, greaterThanOrEqualTo(4));
      expect(disputeSteps.length, 5);
      expect(cannotDeduct.length, greaterThan(0));
      expect(canDeduct.length, greaterThan(0));
    });

    test('催告函填入金额与期限', () {
      final text = renderTemplate('demand', {
        'tenant': '王小明',
        'landlord': '张建国',
        'address': '北京市朝阳区望京街道',
        'deposit': '8000',
        'deadline': '7',
      });
      expect(text.contains('押金退还催告函'), isTrue);
      expect(text.contains('王小明'), isTrue);
      expect(text.contains('8000'), isTrue);
    });

    test('缺失字段用占位符且不抛错', () {
      final text = renderTemplate('lawsuit', const {});
      expect(text.contains('民事起诉状'), isTrue);
      expect(text.contains('____'), isTrue);
    });
  });

  group('PDF 兜底与生成', () {
    test('字体字符白名单会替换生僻字', () {
      expect(sanitizeForPdf('翠屏里 3 栋 502'), '翠屏里 3 栋 502');
      expect(sanitizeForPdf('ok'), 'ok');
    });

    test('取证清单 PDF 可嵌入中文', () async {
      final bytes = await PdfService.buildChecklist(
        property: buildProperty(),
        sections: const [
          PdfSection(
            room: '主卧',
            items: [
              PdfPhotoItem(
                image: null,
                title: '地板问题',
                subtitle: '地板有 2 处划痕，入住前已存在。',
                meta: '2026-03-01 10:24',
              ),
            ],
          ),
        ],
      );
      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('退租对比报告 PDF 可生成', () async {
      final bytes = await PdfService.buildCompareReport(
        property: buildProperty(),
        pairs: const [
          PdfComparePair(
            room: '主卧',
            issue: '地板问题',
            moveInImage: null,
            moveInCaption: '2026-03-01 · 2 处划痕',
            moveOutImage: null,
            moveOutCaption: '2026-12-31 · 划痕相同',
            note: '该瑕疵入住前已有，非租户造成。',
          ),
        ],
        conclusion: '综合说明测试',
      );
      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('维权文书 PDF 可生成', () async {
      final bytes = await PdfService.buildDocument(
        title: '押金退还催告函',
        paragraphs: ['本人已退租并返还房屋。', '请于 7 日内退还押金人民币 8000 元。'],
      );
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('取证水印合成', () {
    test('水印会烧录进照片并生成缩略图', () async {
      // 造一张纯色测试图，模拟用户拍摄的原始照片
      final source = img.Image(width: 640, height: 480);
      img.fill(source, color: img.ColorRgb8(180, 170, 150));
      final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 90));

      final result = await WatermarkService.process(
        source: bytes,
        lines: [
          '拍摄时间：2026-03-01 10:24',
          '拍摄地点：北京市朝阳区望京街道',
          '房　间：客厅 · 入住取证',
          '问　题：墙面破损 · 东北角有 12cm 裂缝',
        ],
      );

      expect(result.width, 640);
      expect(result.height, 480);
      expect(result.image, isNotEmpty);
      expect(result.thumb, isNotEmpty);
      // 缩略图会被压到 420px 以内
      expect(result.thumb.length, lessThan(result.image.length));
      // JPEG 文件头
      expect(result.image[0], 0xFF);
      expect(result.image[1], 0xD8);
    });

    test('关闭水印时不改变画面尺寸', () async {
      final source = img.Image(width: 300, height: 200);
      img.fill(source, color: img.ColorRgb8(120, 140, 160));
      final result = await WatermarkService.process(
        source: Uint8List.fromList(img.encodeJpg(source)),
        lines: const ['拍摄时间：2026-03-01 10:24'],
        watermark: false,
      );
      expect(result.width, 300);
      expect(result.height, 200);
    });
  });

  group('租金计划生成', () {
    final property = buildProperty().copyWith(
      contract: buildProperty().contract.copyWith(rentDueDay: 13),
    );

    test('按租期生成整月账单', () {
      // 合同 2026-03-01 ~ 2026-12-31，交租日 13 号 → 10 期
      final schedule = buildRentSchedule(
        property: property,
        existing: const [],
        today: DateTime(2026, 3, 1),
      );
      expect(schedule.length, 10);
      expect(schedule.first.month, '2026-03');
      expect(schedule.last.month, '2026-12');
      expect(schedule.first.dueDate, DateTime(2026, 3, 13));
      expect(schedule.first.amount, 3200);
    });

    test('已过应付日的记录标记为逾期，之后的为待付', () {
      final schedule = buildRentSchedule(
        property: property,
        existing: const [],
        today: DateTime(2026, 5, 20),
      );
      final march = schedule.firstWhere((r) => r.month == '2026-03');
      final june = schedule.firstWhere((r) => r.month == '2026-06');
      // 入住当月（2026-03）的房租在签合同时就付了，不算逾期
      expect(march.status, RentStatus.paid);
      expect(march.paidDate, property.contract.moveInDate);
      final april = schedule.firstWhere((r) => r.month == '2026-04');
      expect(april.status, RentStatus.overdue);
      expect(june.status, RentStatus.pending);
    });

    test('入住当月：没到交租日只算待付，到了才默认已交', () {
      // 3 月 1 日入住、13 号交租 → 3 月 5 日还没到交租日
      final before = buildRentSchedule(
        property: property,
        existing: const [],
        today: DateTime(2026, 3, 5),
      );
      final marchBefore = before.firstWhere((r) => r.month == '2026-03');
      expect(marchBefore.status, RentStatus.pending);
      expect(
        marchBefore.paidDate,
        isNull,
        reason: '还没到交租日，不该默认「已缴 1 个月」',
      );

      // 到了交租日当天：默认已交（签合同时付首月是常态）
      final onDay = buildRentSchedule(
        property: property,
        existing: const [],
        today: DateTime(2026, 3, 13),
      );
      final marchOnDay = onDay.firstWhere((r) => r.month == '2026-03');
      expect(marchOnDay.status, RentStatus.paid);
      expect(marchOnDay.paidDate, property.contract.moveInDate);

      // 过了交租日也仍然是「已交」，不会平白报一条逾期
      final after = buildRentSchedule(
        property: property,
        existing: const [],
        today: DateTime(2026, 3, 20),
      );
      final marchAfter = after.firstWhere((r) => r.month == '2026-03');
      expect(marchAfter.status, RentStatus.paid);
    });

    test('保留已付记录（含 id 与状态），只刷新未付月份', () {
      final existing = [
        RentRecord(
          id: 'keep-me',
          propertyId: property.id,
          month: '2026-03',
          amount: 3000,
          dueDate: DateTime(2026, 3, 13),
          status: RentStatus.paid,
          paidDate: DateTime(2026, 3, 12),
        ),
      ];
      final schedule = buildRentSchedule(
        property: property,
        existing: existing,
        today: DateTime(2026, 3, 1),
      );
      final march = schedule.firstWhere((r) => r.month == '2026-03');
      expect(march.id, 'keep-me');
      expect(march.status, RentStatus.paid);
      expect(march.amount, 3000, reason: '已付账单不应被租金改动覆盖');

      final april = schedule.firstWhere((r) => r.month == '2026-04');
      expect(april.amount, 3200);
      expect(april.id, isNot('keep-me'));
    });
  });

  group('待办提醒规则', () {
    final property = buildProperty();
    const config = ReminderSettings();

    List<ReminderItem> build(
      DateTime now, {
      Property? target,
      List<EvidencePhoto> photos = const [],
      List<UtilityRecord> utilities = const [],
      List<RentRecord> rents = const [],
      ReminderSettings settings = config,
    }) => buildReminders(
      properties: [target ?? property],
      photos: photos,
      utilities: utilities,
      rents: rents,
      config: settings,
      now: now,
    );

    test('临近交租日触发交租提醒', () {
      // 交租日 13 号，3 月 11 日 → 还有 2 天
      final list = build(DateTime(2026, 3, 11));
      final rent = list.where((r) => r.kind == ReminderKind.rentDue).toList();
      expect(rent, isNotEmpty);
      expect(rent.first.daysLeft, 2);
      expect(rent.first.tone, ZTone.warn);
    });

    test('待办说法：交租当天是「就是今天」，前一天是「明天」', () {
      // 交租日 13 号，就在今天
      final today = build(DateTime(2026, 3, 13));
      final rentToday = today.firstWhere(
        (r) => r.kind == ReminderKind.rentDue,
      );
      expect(rentToday.daysLeft, 0);
      expect(rentToday.actionLabel, '就是今天', reason: '别写成「0 天后」');

      // 前一天
      final eve = build(DateTime(2026, 3, 12));
      final rentEve = eve.firstWhere((r) => r.kind == ReminderKind.rentDue);
      expect(rentEve.actionLabel, '明天', reason: '别写成「1 天后」');

      // 合同到期同理：12-31 到期，12-30 那天说「明天」
      final contract = build(DateTime(2026, 12, 30));
      final expiry = contract.firstWhere(
        (r) => r.kind == ReminderKind.contractExpire,
      );
      expect(expiry.daysLeft, 1);
      expect(expiry.actionLabel, '明天');
    });

    test('交租日已过且未付款时提示逾期（不再跳到下个月）', () {
      final list = build(
        DateTime(2026, 3, 14),
        rents: [
          RentRecord(
            id: 'r1',
            propertyId: property.id,
            month: '2026-03',
            amount: 3200,
            dueDate: DateTime(2026, 3, 13),
          ),
        ],
      );
      final rent = list.firstWhere((r) => r.kind == ReminderKind.rentDue);
      expect(rent.tone, ZTone.danger);
      expect(rent.actionLabel, '已逾期');
      expect(rent.subtitle.contains('已逾期 1 天'), isTrue);
    });

    test('已付账单不会产生逾期提醒', () {
      final list = build(
        DateTime(2026, 3, 14),
        rents: [
          RentRecord(
            id: 'r1',
            propertyId: property.id,
            month: '2026-03',
            amount: 3200,
            dueDate: DateTime(2026, 3, 13),
            status: RentStatus.paid,
            paidDate: DateTime(2026, 3, 12),
          ),
        ],
      );
      expect(list.where((r) => r.kind == ReminderKind.rentDue), isEmpty);
    });

    test('距离较远时不产生交租提醒', () {
      final list = build(DateTime(2026, 3, 1));
      expect(list.where((r) => r.kind == ReminderKind.rentDue), isEmpty);
    });

    test('合同到期按阈值分级', () {
      final soon = build(DateTime(2026, 12, 20))
          .firstWhere((r) => r.kind == ReminderKind.contractExpire);
      expect(soon.tone, ZTone.brand);

      final urgent = build(DateTime(2026, 12, 28))
          .firstWhere((r) => r.kind == ReminderKind.contractExpire);
      expect(urgent.tone, ZTone.danger);
    });

    test('本月未抄表与缺少入住取证都会提醒', () {
      final list = build(DateTime(2026, 3, 20));
      expect(list.any((r) => r.kind == ReminderKind.utilityReading), isTrue);
      expect(list.any((r) => r.kind == ReminderKind.photoMissing), isTrue);
    });

    test('已有本月抄表记录后不再提醒抄表', () {
      final list = build(
        DateTime(2026, 3, 20),
        utilities: [
          UtilityRecord(
            id: 'u1',
            propertyId: property.id,
            month: '2026-03',
            recordedAt: DateTime(2026, 3, 3),
          ),
        ],
      );
      expect(list.any((r) => r.kind == ReminderKind.utilityReading), isFalse);
    });

    test('关闭某一类提醒后不再产出对应条目', () {
      final list = build(
        DateTime(2026, 3, 20),
        settings: config.copyWith(
          enableRent: false,
          enableUtility: false,
          enableContract: false,
        ),
      );
      expect(
        list.any(
          (r) =>
              r.kind == ReminderKind.rentDue ||
              r.kind == ReminderKind.utilityReading ||
              r.kind == ReminderKind.contractExpire,
        ),
        isFalse,
      );
    });

    test('已退租且押金待退还会提醒催要押金', () {
      final ended = property.copyWith(
        status: PropertyStatus.ended,
        deposit: const DepositInfo(status: DepositStatus.toBeReturned),
        updatedAt: DateTime(2026, 3, 1),
      );
      final list = build(DateTime(2026, 3, 20), target: ended);
      final deposit = list
          .where((r) => r.kind == ReminderKind.depositReturn)
          .toList();
      expect(deposit, isNotEmpty);
      expect(deposit.first.subtitle.contains('已等待 19 天'), isTrue);
    });

    test('待付款项排在普通提示之前', () {
      final list = build(DateTime(2026, 3, 11));
      final rentIndex = list.indexWhere((r) => r.kind == ReminderKind.rentDue);
      final utilityIndex = list.indexWhere(
        (r) => r.kind == ReminderKind.utilityReading,
      );
      expect(rentIndex, isNonNegative);
      expect(utilityIndex, isNonNegative);
      expect(rentIndex, lessThan(utilityIndex));
    });

    test('逾期项排在最前', () {
      final list = build(
        DateTime(2026, 3, 14),
        rents: [
          RentRecord(
            id: 'r1',
            propertyId: property.id,
            month: '2026-03',
            amount: 3200,
            dueDate: DateTime(2026, 3, 13),
          ),
        ],
      );
      expect(list.first.tone, ZTone.danger);
      expect(list.first.kind, ReminderKind.rentDue);
    });
  });

  group('存证健康度', () {
    final property = buildProperty();
    final now = DateTime(2026, 3, 20);

    EvidencePhoto photo(String room, PhotoPhase phase) => EvidencePhoto(
      id: '${room}_${phase.name}',
      propertyId: property.id,
      room: room,
      imageRef: 'a.jpg',
      thumbRef: 'a_t.jpg',
      timestamp: now,
      phase: phase,
    );

    test('材料齐全时健康度为 100%', () {
      final photos = [
        for (final room in Property.defaultRooms)
          photo(room, PhotoPhase.moveIn),
        photo('主卧', PhotoPhase.moveOut),
      ];
      final health = buildHealth(
        property: property.copyWith(
          contract: property.contract.copyWith(contractPhotoRefs: ['c.jpg']),
        ),
        photos: photos,
        utilities: [
          UtilityRecord(
            id: 'u1',
            propertyId: property.id,
            month: '2026-03',
            recordedAt: now,
          ),
        ],
        now: now,
      );
      expect(health.ratio, 1.0);
      expect(health.items.every((item) => item.ok), isTrue);
    });

    test('没有任何材料时健康度为 0 并给出补齐提示', () {
      final health = buildHealth(
        property: property,
        photos: const [],
        utilities: const [],
        now: now,
      );
      expect(health.ratio, 0);
      expect(health.items.length, 4);
      expect(
        health.items.firstWhere((i) => i.label == '合同照片').hint,
        contains('建议补'),
      );
    });

    test('只覆盖部分房间时按比例计分', () {
      final photos = [
        for (final room in Property.defaultRooms.take(4))
          photo(room, PhotoPhase.moveIn),
      ];
      final health = buildHealth(
        property: property,
        photos: photos,
        utilities: const [],
        now: now,
      );
      // 4/8 房间 × 0.5 = 0.25
      expect(health.ratio, closeTo(0.25, 0.0001));
    });
  });

  group('费用统计', () {
    final property = buildProperty();

    test('按月拆分租金、水电与物业网络', () {
      final expense = computeMonthlyExpense(
        rents: [
          RentRecord(
            id: 'r1',
            propertyId: property.id,
            month: '2026-03',
            amount: 3200,
            dueDate: DateTime(2026, 3, 13),
            status: RentStatus.paid,
          ),
        ],
        utilities: [
          UtilityRecord(
            id: 'u1',
            propertyId: property.id,
            month: '2026-03',
            electricity: const UtilityReading(
              reading: 300,
              previousReading: 100,
              unitPrice: 0.5,
            ),
            propertyFee: 120,
            networkFee: 60,
            recordedAt: DateTime(2026, 3, 3),
          ),
        ],
        propertyId: property.id,
        month: '2026-03',
      );
      expect(expense.rent, 3200);
      expect(expense.utility, closeTo(100, 0.001));
      expect(expense.other, 180);
      expect(expense.total, closeTo(3480, 0.001));
    });

    test('趋势按时间正序且长度可控', () {
      final trend = buildExpenseTrend(
        rents: const [],
        utilities: const [],
        propertyId: property.id,
        now: DateTime(2026, 3, 20),
        months: 3,
      );
      expect(trend.length, 3);
      expect(trend.first.month, '2026-01');
      expect(trend.last.month, '2026-03');
    });

    test('累计与年度汇总只统计已付租金', () {
      final rents = [
        RentRecord(
          id: 'r1',
          propertyId: property.id,
          month: '2026-01',
          amount: 3000,
          dueDate: DateTime(2026, 1, 13),
          status: RentStatus.paid,
        ),
        RentRecord(
          id: 'r2',
          propertyId: property.id,
          month: '2026-02',
          amount: 3000,
          dueDate: DateTime(2026, 2, 13),
        ),
      ];
      expect(sumPaidRent(rents, property.id), 3000);
      expect(sumYearlyExpense(rents, const [], property.id, 2026), 3000);
    });
  });

  group('回归：编辑房源不丢历史账单', () {
    final property = buildProperty();

    test('合同改短后，范围外的已付记录原样保留', () {
      final existing = [
        RentRecord(
          id: 'jan',
          propertyId: property.id,
          month: '2025-12',
          amount: 3000,
          dueDate: DateTime(2025, 12, 13),
          status: RentStatus.paid,
          paidDate: DateTime(2025, 12, 12),
          note: '微信转账',
        ),
        RentRecord(
          id: 'mar',
          propertyId: property.id,
          month: '2026-03',
          amount: 3200,
          dueDate: DateTime(2026, 3, 13),
          status: RentStatus.paid,
          paidDate: DateTime(2026, 3, 12),
        ),
      ];
      // 计划只覆盖 2026-03 ~ 2026-05
      final shortened = property.copyWith(
        contract: property.contract.copyWith(
          moveInDate: DateTime(2026, 3, 1),
          contractEnd: DateTime(2026, 5, 31),
        ),
      );
      final planned = buildRentSchedule(
        property: shortened,
        existing: existing,
        today: DateTime(2026, 3, 1),
      );
      final merged = mergeRentSchedule(existing: existing, planned: planned);

      final kept = merged.firstWhere((r) => r.month == '2025-12');
      expect(kept.status, RentStatus.paid, reason: '合同范围外的历史记录必须保留');
      expect(kept.paidDate, DateTime(2025, 12, 12));
      expect(kept.note, '微信转账');

      // 计划内月份以计划为准，且不会重复
      expect(merged.where((r) => r.month == '2026-03').length, 1);
      expect(
        merged.map((r) => r.month).toList(),
        containsAll(['2025-12', '2026-03', '2026-04', '2026-05']),
      );
      // 结果按月升序
      expect(merged.first.month, '2025-12');
    });
  });

  group('回归：已缴月数与金额同源', () {
    final property = buildProperty();

    test('月数 × 月租 = 累计已付租金', () {
      final rents = [
        for (var m = 3; m <= 9; m++)
          RentRecord(
            id: 'r$m',
            propertyId: property.id,
            month: '2026-${m.toString().padLeft(2, '0')}',
            amount: 3200,
            dueDate: DateTime(2026, m, 13),
            status: RentStatus.paid,
            paidDate: DateTime(2026, m, 12),
          ),
      ];
      expect(countPaidMonths(rents, property.id), 7);
      expect(sumPaidRent(rents, property.id), 22400);
      expect(
        countPaidMonths(rents, property.id) * 3200,
        sumPaidRent(rents, property.id),
      );
    });
  });

  group('回归：押金状态与房源状态联动', () {
    test('六种押金状态都有明确的房源状态', () {
      expect(statusForDeposit(DepositStatus.none), PropertyStatus.active);
      expect(statusForDeposit(DepositStatus.paid), PropertyStatus.active);
      expect(
        statusForDeposit(DepositStatus.toBeReturned),
        PropertyStatus.ended,
      );
      expect(
        statusForDeposit(DepositStatus.partiallyDeducted),
        PropertyStatus.ended,
      );
      expect(statusForDeposit(DepositStatus.returned), PropertyStatus.ended);
      expect(statusForDeposit(DepositStatus.inDispute), PropertyStatus.dispute);
    });

    test('押金改回已缴纳后，房源状态可以回到租住中', () {
      final ended = buildProperty().copyWith(status: PropertyStatus.ended);
      final restored = ended.copyWith(
        status: statusForDeposit(DepositStatus.paid),
      );
      expect(restored.status, PropertyStatus.active);
    });
  });

  group('抄表：上月读数按自然月带入', () {
    test('上一月键跨年计算正确', () {
      expect(previousMonthKey('2026-10'), '2026-09');
      expect(previousMonthKey('2026-01'), '2025-12');
      expect(previousMonthKey('2026-03'), '2026-02');
      expect(previousMonthKey('不是月份'), '不是月份');
      expect(previousMonthKey('2026-13'), '2026-13');
    });

    test('只取「日历上一月」的记录，不串到更早的月份', () {
      final utilities = [
        UtilityRecord(
          id: 'u1',
          propertyId: 'p1',
          month: '2026-09',
          recordedAt: DateTime(2026, 9, 30),
          electricity: const UtilityReading(
            reading: 1200,
            previousReading: 1100,
            unitPrice: 1,
            unit: 'kWh',
          ),
        ),
        UtilityRecord(
          id: 'u2',
          propertyId: 'p1',
          month: '2026-07',
          recordedAt: DateTime(2026, 7, 30),
          electricity: const UtilityReading(
            reading: 900,
            previousReading: 800,
            unitPrice: 1,
            unit: 'kWh',
          ),
        ),
      ];

      final previous = previousUtilityOf(
        utilities: utilities,
        propertyId: 'p1',
        month: '2026-10',
      );
      expect(previous?.month, '2026-09');
      expect(previous?.electricity?.reading, 1200);
    });

    test('上一月没有记录时视为无上月读数', () {
      final utilities = [
        UtilityRecord(
          id: 'u2',
          propertyId: 'p1',
          month: '2026-07',
          recordedAt: DateTime(2026, 7, 30),
        ),
      ];

      expect(
        previousUtilityOf(
          utilities: utilities,
          propertyId: 'p1',
          month: '2026-10',
        ),
        isNull,
      );
      // 上一月是 1 月时的跨年查找
      expect(
        previousUtilityOf(
          utilities: [
            UtilityRecord(
              id: 'u3',
              propertyId: 'p1',
              month: '2025-12',
              recordedAt: DateTime(2025, 12, 30),
            ),
          ],
          propertyId: 'p1',
          month: '2026-01',
        )?.month,
        '2025-12',
      );
    });
  });

  groupApi();
    test('入住时长文案：未入住时不说「已入住 -N 天」', () {
      final today = DateTime(2026, 10, 12);
      expect(stayDurationLabel(DateTime(2026, 10, 12), now: today), '今天入住');
      expect(stayDurationLabel(DateTime(2026, 10, 2), now: today), '已入住 10 天');
      expect(stayDurationLabel(DateTime(2026, 10, 20), now: today), '距入住 8 天');
    });
    test('云端合并：同月租金与抄表只保留云端那条', () {
      final cloud = {
        'version': 1,
        'properties': <Object>[],
        'photos': <Object>[],
        'rents': [
          {'id': 'cloud-rent', 'propertyId': 'p1', 'month': '2026-10'},
        ],
        'utilities': [
          {'id': 'cloud-util', 'propertyId': 'p1', 'month': '2026-10'},
        ],
      };
      final local = {
        'version': 1,
        'properties': <Object>[],
        'photos': <Object>[],
        'rents': [
          {'id': 'local-rent', 'propertyId': 'p1', 'month': '2026-10'},
          {'id': 'local-rent-9', 'propertyId': 'p1', 'month': '2026-09'},
        ],
        'utilities': [
          {'id': 'local-util', 'propertyId': 'p1', 'month': '2026-10'},
        ],
      };
      final merged = mergeDatasets(cloud, local);
      final rents = (merged['rents']! as List).cast<Map<String, dynamic>>();
      // 10 月只留云端那条，9 月本机独有的补进来
      expect(rents.where((r) => r['month'] == '2026-10'), hasLength(1));
      expect(rents.firstWhere((r) => r['month'] == '2026-10')['id'], 'cloud-rent');
      expect(rents.where((r) => r['month'] == '2026-09'), hasLength(1));
      final utils = (merged['utilities']! as List).cast<Map<String, dynamic>>();
      expect(utils, hasLength(1));
      expect(utils.first['id'], 'cloud-util');
    });

  test('合同新增字段：序列化往返 + 旧数据读默认值', () {
    final contract = ContractInfo(
      monthlyRent: 3200,
      deposit: 8000,
      paymentMethod: '月付',
      moveInDate: DateTime(2026, 3, 1),
      contractEnd: DateTime(2027, 3, 1),
      rentDueDay: 28,
      noticeDays: 15,
      rentScope: '合租',
    );
    final restored = ContractInfo.fromJson(contract.toJson());
    expect(restored.noticeDays, 15);
    expect(restored.rentScope, '合租');
    expect(restored.rentDueDay, 28);

    // 老版本存的合同没有这两个键，读出来应是默认值
    final legacy = ContractInfo.fromJson({
      'monthlyRent': 3200,
      'deposit': 8000,
      'paymentMethod': '押一付三',
      'moveInDate': '2026-03-01T00:00:00.000',
      'contractEnd': '2027-03-01T00:00:00.000',
      'rentDueDay': 13,
    });
    expect(legacy.noticeDays, 30);
    expect(legacy.rentScope, '整租');
  });
  test('外观偏好：序列化往返 + 旧数据默认跟随系统', () {
    const settings = AppSettings(appearance: AppAppearance.dark);
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.appearance, AppAppearance.dark);

    // 老版本存的数据没有 appearance 键，读出来应默认「跟随系统」
    final legacy = AppSettings.fromJson({'userName': '小王'});
    expect(legacy.appearance, AppAppearance.system);
    expect(legacy.userName, '小王');
    // 系统通知也是后来加的：老数据默认关着（不能替用户决定去要系统权限）
    expect(legacy.systemNotifications, isFalse);
    expect(
      AppSettings.fromJson(
        const AppSettings(systemNotifications: true).toJson(),
      ).systemNotifications,
      isTrue,
    );

    // 存了非法值也不能让整份设置读失败
    final broken = AppSettings.fromJson({'appearance': 'neon'});
    expect(broken.appearance, AppAppearance.system);
  });

  test('深色令牌：文字层级在明暗两套下都不会「糊」在底色上', () {
    void check(Brightness brightness) {
      Z.applyBrightness(brightness);
      final where = brightness == Brightness.dark ? '深色' : '浅色';
      double ratio(Color fg, Color bg) => contrastRatio(fg, bg);

      // 正文：按 WCAG AA 4.5 守住
      for (final pair in <(String, Color, Color)>[
        ('主文字 / 卡片', Z.ink, Z.card),
        ('主文字 / 页面底色', Z.ink, Z.page),
        ('主文字 / 分区块', Z.ink, Z.line3),
        ('次级文字 / 卡片', Z.ink2, Z.card),
      ]) {
        expect(
          meetsContrast(pair.$2, pair.$3),
          isTrue,
          reason:
              '$where：${pair.$1} 对比度不足（${ratio(pair.$2, pair.$3).toStringAsFixed(2)}）',
        );
      }

      // 辅助文字：设计稿现值浅色 4.31 / 深色 6.18，守住 4.2 不再往下掉
      expect(
        ratio(Z.ink3, Z.card),
        greaterThan(4.2),
        reason:
            '$where：辅助文字 / 卡片对比度不足（${ratio(Z.ink3, Z.card).toStringAsFixed(2)}）',
      );

      // 占位 / 提示文字：浅色 2.48、深色 4.23，至少要明显区别于底色
      expect(
        ratio(Z.ink4, Z.card),
        greaterThan(2.4),
        reason:
            '$where：占位文字 / 卡片对比度不足（${ratio(Z.ink4, Z.card).toStringAsFixed(2)}）',
      );

      // 白字只出现在品牌色按钮上，这条底线不能被深色改坏
      expect(
        meetsContrast(Colors.white, Z.brand, large: true),
        isTrue,
        reason: '$where：品牌按钮上的白字对比度不足',
      );
    }

    check(Brightness.light);
    check(Brightness.dark);
    // 令牌是全局的，跑完恢复浅色
    addTearDown(() => Z.applyBrightness(Brightness.light));
  });

  ReminderItem reminderOf(
    ReminderKind kind, {
    required DateTime date,
    int daysLeft = 0,
    String propertyId = 'p1',
    String propertyName = '翠屏里 3 栋 502',
    DateTime? until,
  }) => ReminderItem(
    kind: kind,
    title: '标题',
    subtitle: '副标题',
    date: date,
    daysLeft: daysLeft,
    propertyId: propertyId,
    propertyName: propertyName,
    until: until,
  );

  testWidgets('本机数据比 App 新：不解析、不覆盖，并给出升级提示', (tester) async {
    final repository = await openTestRepository(tester);
    final key = repository.dataKey;

    // 模拟"被更高版本 App 写过"的本机数据
    final future = jsonEncode({
      'version': 99,
      'savedAt': DateTime.now().toIso8601String(),
      'properties': [
        {'id': 'p9', 'name': '未来的房子'},
      ],
      'settings': {'userName': '未来的我'},
    });
    await tester.runAsync(
      () => repository.store.setString(key, future),
    );

    // 换一个作用域再换回来，触发一次真正的重新加载
    await tester.runAsync(() async {
      await repository.useScope('zudun.data.reload_probe');
      await repository.useScope(key);
    });

    expect(repository.readOnly, isTrue, reason: '版本更高时要进入只读保护');
    expect(repository.properties, isEmpty, reason: '解析不了就别硬解析成半份数据');
    expect(repository.lastError, contains('更高版本'));

    // 任何一次保存都不能把磁盘上那份数据覆盖掉
    await tester.runAsync(
      () => repository.updateSettings(
        repository.settings.copyWith(userName: '本机新名字'),
      ),
    );
    expect(
      repository.store.getString(key),
      future,
      reason: '只读保护下原数据必须一字不改',
    );
  });

  test('删除标记：删掉的记录不会再被云端合并回来', () {
    // 云端还有这张照片，本机已经删了并留了墓碑
    final cloud = {
      'photos': [
        {'id': 'ph1', 'propertyId': 'p1'},
        {'id': 'ph2', 'propertyId': 'p1'},
      ],
      'comms': [
        {'id': 'c1', 'propertyId': 'p1'},
      ],
    };
    final local = {
      'photos': [
        {'id': 'ph1', 'propertyId': 'p1'},
      ],
      'comms': <Map<String, dynamic>>[],
      'deleted': {
        'photos': {'ph1': '2026-10-13T10:00:00.000'},
        'comms': {'c1': '2026-10-13T10:05:00.000'},
      },
    };

    final merged = mergeDatasets(cloud, local);
    final photos = (merged['photos']! as List).cast<Map<String, dynamic>>();
    final comms = (merged['comms']! as List).cast<Map<String, dynamic>>();

    expect(photos.map((p) => p['id']), ['ph2'], reason: '删掉的 ph1 不能再回来');
    expect(comms, isEmpty, reason: '本机删掉的沟通记录也不该被云端带回来');
    expect(
      (merged['deleted']! as Map)['photos'],
      contains('ph1'),
      reason: '墓碑要跟着合并结果一起传下去',
    );

    // 两端都删过时，保留更晚的时间
    final both = mergeDatasets(
      {
        'deleted': {
          'photos': {'ph9': '2026-10-13T11:00:00.000'},
        },
      },
      {
        'photos': [
          {'id': 'ph9'},
        ],
        'deleted': {
          'photos': {'ph9': '2026-10-13T09:00:00.000'},
        },
      },
    );
    expect(
      ((both['deleted']! as Map)['photos']! as Map)['ph9'],
      '2026-10-13T11:00:00.000',
    );
    expect((both['photos']! as List), isEmpty);
  });

  testWidgets('删一条记录会写进本机数据（墓碑能跨启动保留）', (tester) async {
    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveComm(
        CommunicationRecord(
          id: 'c-del',
          propertyId: 'p1',
          content: '这条会被删掉',
          tags: const ['维修'],
          timestamp: DateTime(2026, 10, 10),
        ),
      );
      await repository.deleteComm('c-del');
    });

    final raw = repository.store.getString(repository.dataKey) ?? '';
    expect(raw, contains('"deleted"'), reason: '删除要留痕');
    expect(raw, contains('c-del'));
    expect(repository.commsOf('p1'), isEmpty);
  });

  test('年度抄表合计：金额与三种表的用量', () {
    final records = [
      UtilityRecord(
        id: 'u1',
        propertyId: 'p1',
        month: '2026-08',
        electricity: const UtilityReading(
          reading: 1300,
          previousReading: 1200,
          unitPrice: 0.6,
          unit: 'kWh',
        ),
        water: const UtilityReading(
          reading: 120,
          previousReading: 110,
          unitPrice: 3.5,
          unit: 'm3',
        ),
        propertyFee: 100,
        recordedAt: DateTime(2026, 8, 1),
      ),
      UtilityRecord(
        id: 'u2',
        propertyId: 'p1',
        month: '2026-09',
        electricity: const UtilityReading(
          reading: 1400,
          previousReading: 1300,
          unitPrice: 0.6,
          unit: 'kWh',
        ),
        recordedAt: DateTime(2026, 9, 1),
      ),
      // 另一年 / 另一套房子的数据不该被算进来
      UtilityRecord(
        id: 'u3',
        propertyId: 'p1',
        month: '2025-12',
        electricity: const UtilityReading(
          reading: 900,
          previousReading: 800,
          unitPrice: 0.6,
          unit: 'kWh',
        ),
        recordedAt: DateTime(2025, 12, 1),
      ),
      UtilityRecord(
        id: 'u4',
        propertyId: 'p2',
        month: '2026-09',
        electricity: const UtilityReading(
          reading: 500,
          previousReading: 400,
          unitPrice: 0.6,
          unit: 'kWh',
        ),
        recordedAt: DateTime(2026, 9, 1),
      ),
    ];

    final summary = summarizeUtilityYear(records, 'p1', '2026');
    expect(summary.months, 2, reason: '只统计这一年、这套房子的记录');
    expect(summary.electricity, 200);
    expect(summary.water, 10);
    expect(summary.propertyFee, 100);
    expect(summary.cost, closeTo(60 + 35 + 100 + 60, 0.01));

    final other = summarizeUtilityYear(records, 'p1', '2024');
    expect(other.months, 0);
    expect(other.cost, 0);
  });

  test('Web 媒体仓库：IndexedDB 存取、占用统计、删除都对', () async {
    final idb = IdbMediaBackend(idbFactoryMemory);
    addTearDown(idb.close);

    final photo = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));
    final thumb = Uint8List.fromList(List<int>.filled(64, 7));

    await idb.put('media:p1/a.jpg', photo);
    await idb.put('media:p1/a.thumb.jpg', thumb);

    final read = await idb.get('media:p1/a.jpg');
    expect(read, isNotNull);
    expect(read!.length, photo.length);
    expect(read, photo, reason: '取回来要和存进去的一模一样');

    expect(
      await idb.totalBytes(),
      photo.length + thumb.length,
      reason: '占用要按真实字节数统计，而不是只算内存里的',
    );

    // 覆盖同一条不会重复计数
    await idb.put('media:p1/a.jpg', Uint8List.fromList(List<int>.filled(10, 1)));
    expect(await idb.totalBytes(), 10 + thumb.length);

    await idb.delete('media:p1/a.jpg');
    expect(await idb.get('media:p1/a.jpg'), isNull);
    expect(await idb.totalBytes(), thumb.length);

    await idb.delete('media:p1/a.thumb.jpg');
    expect(await idb.totalBytes(), 0);
  });

  testWidgets('错误日志：记录、落盘、重载、只保留最近 50 条', (tester) async {
    // 用真实的本机存储（路径由 openTestRepository 里的 mock 提供）
    final repository = await openTestRepository(tester);
    final store = repository.store;
    final log = ErrorLog(store);

    // 落盘是真实文件 IO：必须放进 runAsync，否则 FakeAsync 下会一直挂着
    await tester.runAsync(() async {
      log.add(StateError('第一次出错'), stack: StackTrace.current);
      log.add('第二次出错', note: '未捕获异常');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(log.entries, hasLength(2));
    expect(log.entries.first.message, contains('第二次出错'));

    final restored = ErrorLog(store)..load();
    expect(restored.entries, hasLength(2));
    expect(restored.entries.last.message, contains('第一次出错'));

    // 超过上限只留最近的
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        restored.add('第 $i 条');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(restored.entries, hasLength(ErrorLog.maxEntries));
    expect(restored.entries.first.message, contains('第 59 条'));

    // 复制用的文本 + 清空
    expect(restored.text, contains('第 59 条'));
    await tester.runAsync(restored.clear);
    expect(restored.isEmpty, isTrue);
    expect(restored.text, '暂无错误记录');
  });

  test('字体分工：界面用子集、PDF 用全量（别弄反）', () {
    final uiRegular = File('assets/fonts/NotoSansSC-Regular.ttf').lengthSync();
    final uiBold = File('assets/fonts/NotoSansSC-Bold.ttf').lengthSync();
    final pdfRegular = File(
      'assets/fonts/pdf/NotoSansSC-Regular.ttf',
    ).lengthSync();
    final pdfBold = File('assets/fonts/pdf/NotoSansSC-Bold.ttf').lengthSync();

    // 界面字体只带 App 用到的字：几百 KB 级别
    for (final size in [uiRegular, uiBold]) {
      expect(size, greaterThan(120 * 1024), reason: '子集不该小到没字形');
      expect(
        size,
        lessThan(600 * 1024),
        reason: '界面字体应该是子集（否则 Web 首屏白下几 MB）',
      );
    }
    // PDF 字体必须保留全量：报告里的生僻字不能变 □
    for (final size in [pdfRegular, pdfBold]) {
      expect(
        size,
        greaterThan(1500 * 1024),
        reason: 'PDF 必须用全量字体，别被换成子集',
      );
    }
  });

  testWidgets('启动只取界面字体，不碰 PDF 全量字体（否则首屏白下 4MB）', (tester) async {
    final requested = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      requested.add(key);
      final file = File(key);
      if (!file.existsSync()) return null;
      return ByteData.sublistView(file.readAsBytesSync());
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    rootBundle.clear();
    await loadStartupFonts();

    expect(
      requested,
      contains('assets/fonts/NotoSansSC-Regular.ttf'),
      reason: '界面字体（水印画布要用）必须在启动时注册',
    );
    expect(
      requested.where((key) => key.startsWith('assets/fonts/pdf/')),
      isEmpty,
      reason: 'PDF 全量字体只能等真正导出 PDF 时再取，'
          '放在启动路径上等于每个用户首屏多下 4MB',
    );
  });

  test('系统通知计划：交租排「提前 N 天 + 当天」并往后预排，过点的不补排', () {
    final due = DateTime(2026, 10, 25);
    final plans = buildNotificationPlan(
      reminders: [reminderOf(ReminderKind.rentDue, date: due, daysLeft: 12)],
      config: const ReminderSettings(rentDaysAhead: 3),
      now: DateTime(2026, 10, 13, 8),
      lookAheadMonths: 0,
    );

    expect(plans, hasLength(2));
    expect(plans.first.when, DateTime(2026, 10, 22, 9));
    expect(plans.first.title, '该交房租了');
    expect(plans.last.when, DateTime(2026, 10, 25, 9));
    expect(plans.last.title, '今天该交房租了');
    expect(plans.first.slot, PlanSlot.rentDue);

    // 交租日当天 10 点打开 App：本月两个时间点都已过，不补弹；下个月的照排
    final late = buildNotificationPlan(
      reminders: [reminderOf(ReminderKind.rentDue, date: due, daysLeft: 0)],
      config: const ReminderSettings(rentDaysAhead: 3),
      now: DateTime(2026, 10, 25, 10),
    );
    expect(
      late.where((plan) => plan.when.year == 2026 && plan.when.month == 10),
      isEmpty,
      reason: '已经过点的提醒不补弹',
    );
    expect(late.first.when, DateTime(2026, 11, 22, 9));

    // 预排 12 个月：长期不打开 App 也能每月收到，且不会排到合同到期之后
    final long = buildNotificationPlan(
      reminders: [
        reminderOf(
          ReminderKind.rentDue,
          date: due,
          daysLeft: 12,
          until: DateTime(2026, 12, 31),
        ),
      ],
      config: const ReminderSettings(rentDaysAhead: 3),
      now: DateTime(2026, 10, 13, 8),
    );
    expect(long.length, greaterThan(2), reason: '要往后预排，不能只排一次');
    expect(long.first.when, DateTime(2026, 10, 22, 9));
    expect(
      long.last.when.isBefore(DateTime(2026, 12, 31, 9)),
      isTrue,
      reason: '合同结束之后的月份不该再排',
    );
    expect(
      long.where((plan) => plan.when.month == 12 && plan.when.day == 25),
      hasLength(1),
      reason: '12-25 还在合同期内，要排',
    );
    expect(
      long.any((plan) => plan.when.year == 2027),
      isFalse,
      reason: '合同 12-31 到期，之后不再排交租提醒',
    );
  });

  test('系统通知计划：房租逾期改成第二天早上提醒', () {
    final overdue = reminderOf(
      ReminderKind.rentDue,
      date: DateTime(2026, 10, 5),
      daysLeft: -8,
    );

    // 早上 8 点：当天 9 点还没到，就排今天
    final plans = buildNotificationPlan(
      reminders: [overdue],
      config: const ReminderSettings(),
      now: DateTime(2026, 10, 13, 8),
    );
    expect(plans, hasLength(1));
    expect(plans.single.when, DateTime(2026, 10, 13, 9));
    expect(plans.single.title, '房租还没交');

    // 已经过了 9 点就排到第二天
    final later = buildNotificationPlan(
      reminders: [overdue],
      config: const ReminderSettings(),
      now: DateTime(2026, 10, 13, 10),
    );
    expect(later.single.when, DateTime(2026, 10, 14, 9));
  });

  test('系统通知计划：合同到期按勾选节点 + 到期当天各排一条', () {
    final plans = buildNotificationPlan(
      reminders: [
        reminderOf(
          ReminderKind.contractExpire,
          date: DateTime(2027, 3, 1),
          daysLeft: 140,
        ),
      ],
      config: const ReminderSettings(contractDaysAhead: [30, 7]),
      now: DateTime(2026, 10, 13, 8),
    );

    expect(plans.map((p) => p.when).toList(), [
      DateTime(2027, 1, 30, 9),
      DateTime(2027, 2, 22, 9),
      DateTime(2027, 3, 1, 9),
    ]);
    expect(plans.last.title, '合同今天到期');
    expect(plans.every((p) => p.slot == PlanSlot.contractExpire), isTrue);
  });

  test('系统通知计划：抄表提醒日已过就排到下个月，并预排一年', () {
    // 设置成每月 1 号提醒，今天 10-13 已经过了 → 第一条排 11-01
    final passed = buildNotificationPlan(
      reminders: [
        reminderOf(ReminderKind.utilityReading, date: DateTime(2026, 10, 1)),
      ],
      config: const ReminderSettings(utilityDay: 1),
      now: DateTime(2026, 10, 13, 8),
    );
    expect(passed.first.when, DateTime(2026, 11, 1, 9));
    expect(passed.length, 12, reason: '往后预排一整年，长期不开 App 也不会漏');
    expect(
      passed.every((plan) => plan.when.day == 1 && plan.when.hour == 9),
      isTrue,
      reason: '每条都落在提醒日的早上 9 点',
    );

    // 提醒日还没到就用本月
    final thisMonth = buildNotificationPlan(
      reminders: [
        reminderOf(ReminderKind.utilityReading, date: DateTime(2026, 10, 20)),
      ],
      config: const ReminderSettings(utilityDay: 20),
      now: DateTime(2026, 10, 13, 8),
    );
    expect(thisMonth.first.when, DateTime(2026, 10, 20, 9));
  });

  test('系统通知计划：押金待退还在第二天早上；取证待办不进系统通知', () {
    final plans = buildNotificationPlan(
      reminders: [
        reminderOf(ReminderKind.depositReturn, date: DateTime(2026, 9, 30)),
        reminderOf(ReminderKind.photoMissing, date: DateTime(2026, 10, 13)),
      ],
      config: const ReminderSettings(),
      now: DateTime(2026, 10, 13, 10),
    );

    expect(plans, hasLength(1), reason: '取证待办没有「到点」概念，留在应用内');
    expect(plans.single.slot, PlanSlot.depositReturn);
    expect(plans.single.when, DateTime(2026, 10, 14, 9));
  });

  test('系统通知计划：id 稳定、按时间升序、换房子不串号', () {
    final reminders = [
      reminderOf(ReminderKind.rentDue, date: DateTime(2026, 11, 1), daysLeft: 5),
      reminderOf(
        ReminderKind.contractExpire,
        date: DateTime(2027, 3, 1),
        daysLeft: 140,
      ),
    ];
    const config = ReminderSettings();
    final first = buildNotificationPlan(
      reminders: reminders,
      config: config,
      now: DateTime(2026, 10, 27, 8),
    );
    final second = buildNotificationPlan(
      reminders: reminders,
      config: config,
      now: DateTime(2026, 10, 27, 8),
    );

    expect(first.map((p) => p.id).toList(), second.map((p) => p.id).toList());
    expect(first.map((p) => p.id).toSet(), hasLength(first.length));
    for (var i = 1; i < first.length; i++) {
      expect(
        first[i].when.isBefore(first[i - 1].when),
        isFalse,
        reason: '计划要按时间升序',
      );
    }

    // 另一套房子算出来的 id 不一样，不会互相覆盖
    final other = buildNotificationPlan(
      reminders: [
        reminderOf(
          ReminderKind.rentDue,
          date: DateTime(2026, 11, 1),
          daysLeft: 5,
          propertyId: 'p2',
        ),
      ],
      config: config,
      now: DateTime(2026, 10, 27, 8),
    );
    expect(
      other.map((p) => p.id).toSet().intersection(
        first.map((p) => p.id).toSet(),
      ),
      isEmpty,
      reason: '两套房子的通知不能撞 id，否则会互相顶掉',
    );
  });

  test('只读归档：退租后不再允许新增抄表与维修', () {
    final active = buildProperty();
    expect(canAddUtility(active), isTrue);
    expect(canAddTimeline(active), isTrue);
    final ended = active.copyWith(status: PropertyStatus.ended);
    expect(canAddUtility(ended), isFalse, reason: '已退租：抄表只读');
    expect(canAddTimeline(ended), isFalse, reason: '已退租：维修只读');
    final dispute = active.copyWith(status: PropertyStatus.dispute);
    expect(canAddUtility(dispute), isFalse, reason: '维权期间也不再抄表');
    expect(canAddTimeline(dispute), isTrue, reason: '维权期间仍要能记录沟通留证');
  });
  groupWidgets();
}

/// 接口层与云端同步的回归用例
void groupApi() {
  group('接口层', () {
    test('响应码按平台约定解析', () {
      // 00000 → 解包 data
      expect(
        resolveApiResponse(
          statusCode: 200,
          body: {'code': '00000', 'data': {'accessToken': 'T'}},
        ),
        {'accessToken': 'T'},
      );
      // 200 → 返回整个响应体
      expect(
        resolveApiResponse(statusCode: 200, body: {'code': '200', 'msg': 'ok'}),
        {'code': '200', 'msg': 'ok'},
      );
      // 无 code 字段也算成功
      expect(
        resolveApiResponse(statusCode: 200, body: {'ok': true}),
        {'ok': true},
      );
      // 401 / A000401 → 登录失效
      for (final code in ['401', '000401', 'A000401']) {
        expect(
          () => resolveApiResponse(statusCode: 200, body: {'code': code}),
          throwsA(
            isA<ApiException>().having(
              (error) => error.unauthorized,
              'unauthorized',
              isTrue,
            ),
          ),
        );
      }
      // 业务错误：把 msg 抛出来
      expect(
        () => resolveApiResponse(
          statusCode: 200,
          body: {'code': 'A00001', 'msg': '验证码错误'},
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            '验证码错误',
          ),
        ),
      );
      // 其它非 200 业务码：用 code 兜底
      expect(
        () => resolveApiResponse(statusCode: 200, body: {'code': 'A00002'}),
        throwsA(
          isA<ApiException>().having((error) => error.code, 'code', 'A00002'),
        ),
      );
      // HTTP 层错误且没有业务码
      expect(
        () => resolveApiResponse(statusCode: 502, body: '<html>'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.reachable,
            'reachable',
            isTrue,
          ),
        ),
      );
    });

    test('用户配置归一化支持三种返回形态', () {
      final expected = {'properties': <Object>[]};
      expect(parseConfigMap(jsonEncode(expected)), expected);
      expect(parseConfigMap({'paramValue': jsonEncode(expected)}), expected);
      expect(parseConfigMap({'data': expected}), expected);
      expect(parseConfigMap(''), isNull);
      expect(parseConfigMap('null'), isNull);
      expect(parseConfigMap('不是 JSON'), isNull);
    });

    test('设备类型与资源引用约定', () {
      expect(ApiSettings.dataKeySuffix, 'ZuDunData');
      expect(OssRef.isRemote('oss:/dir/a.jpg'), isTrue);
      expect(OssRef.isRemote('/home/user/a.jpg'), isFalse);
      expect(OssRef.isRemote('media:p1/a.jpg'), isFalse);
      expect(OssRef.of('dir//a.jpg'), 'oss:/dir/a.jpg');
      expect(OssRef.pathOf('oss:/dir/a.jpg'), '/dir/a.jpg');
      expect(normalizeRemotePath('\\dir\\a.jpg'), '/dir/a.jpg');
      // 缓存名稳定且跨端一致
      expect(cloudCacheName('oss:/a.jpg'), cloudCacheName('oss:/a.jpg'));
      expect(cloudCacheName('oss:/a.jpg'), isNot(cloudCacheName('oss:/b.jpg')));
    });

    test('密码加密与平台前端（crypto-js）结果一致', () {
      // 参考值用平台前端同一套算法在 Node（crypto-js）下生成：
      // AES-ECB + PKCS7，明文 = 毫秒时间戳 + 密码，密钥 -mall--password-
      expect(
        encryptPassword(
          'abc123456',
          secret: '-mall--password-',
          timestampMs: 1700000000000,
        ),
        'ec0wwoI84j1hjl5gzRScbkE9JwPBGZQLBcS2DIMFqFk=',
      );
    });
  });

  group('数据合并', () {
    final cloud = {
      'version': 1,
      'properties': [
        {'id': 'p1', 'name': '云端房源'},
      ],
      'photos': <Object>[],
      'settings': {'userName': '云端的我'},
      'activeId': 'p1',
    };
    final local = {
      'version': 1,
      'properties': [
        {'id': 'p1', 'name': '本机房源'},
        {'id': 'p2', 'name': '本机新增'},
      ],
      'photos': [
        {'id': 'ph1'},
      ],
      'settings': {'userName': '本机的我'},
      'activeId': 'p2',
    };

    test('同 id 以云端为准，本机独有的记录追加', () {
      final merged = mergeDatasets(cloud, local);
      final properties = (merged['properties']! as List)
          .cast<Map<String, dynamic>>();
      expect(properties, hasLength(2));
      expect(properties.first['name'], '云端房源');
      expect(properties.last['id'], 'p2');
      expect((merged['photos']! as List), hasLength(1));
      expect(merged['settings'], {'userName': '云端的我'});
      expect(merged['activeId'], 'p1');
    });
  });

  group('登录态与作用域', () {
    test('游客与账号的作用域、数据键互不干扰', () async {
      final temp = Directory.systemTemp.createTempSync('zudun_session_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final repository = await Repository.open();
      final session = Session(repository.store);

      expect(session.loggedIn, isFalse);
      expect(session.scope, Session.guestScope);
      expect(session.dataKey, 'GuestLocalZuDunData');

      await session.saveLogin(
        token: 'T-1',
        phone: '13800138000',
        provider: 'code',
        user: {'nickName': '小张'},
      );
      expect(session.loggedIn, isTrue);
      expect(session.dataKey, '13800138000ZuDunData');
      expect(session.displayName, '小张');

      // 重新读取（模拟重启）后仍然保持登录态
      final restored = Session(repository.store);
      await restored.restore();
      expect(restored.loggedIn, isTrue);
      expect(restored.phone, '13800138000');
      expect(restored.user['nickName'], '小张');

      await restored.clear();
      expect(restored.loggedIn, isFalse);
      expect(restored.dataKey, 'GuestLocalZuDunData');
    });

    test('首屏分流：未登录且没选过本机模式时先看登录页', () async {
      final temp = Directory.systemTemp.createTempSync('zudun_gate_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final repository = await Repository.open();
      final session = Session(repository.store);
      final settings = ApiSettings(repository.store);
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: settings,
        httpClient: MockClient(
          (request) async => _jsonResponse({'code': '00000', 'data': {}}),
        ),
      );
      addTearDown(cloud.dispose);

      // 全新安装：先看登录页
      expect(session.loggedIn, isFalse);
      expect(session.guestMode, isFalse);
      expect(cloud.needsLogin, isTrue);

      // 选择本机模式后直接进应用
      await session.enterGuestMode();
      expect(cloud.needsLogin, isFalse);

      // 登录后退出本机模式标记，退出登录会回到登录页
      await session.saveLogin(
        token: 'T-1',
        phone: '13800138000',
        provider: 'code',
      );
      expect(session.guestMode, isFalse);
      await session.clear();
      expect(cloud.needsLogin, isTrue);
    });

    test('老用户升级：本机已有数据时自动进入本机模式', () async {
      final temp = Directory.systemTemp.createTempSync('zudun_upgrade_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      // 模拟上一版本留下的本机数据
      final first = await Repository.open();
      await first.addProperty(buildProperty());
      expect(first.rawDataOf(Repository.guestDataKey), isNotNull);

      final repository = await Repository.open();
      final session = Session(repository.store);
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: ApiSettings(repository.store),
        httpClient: MockClient(
          (request) async => _jsonResponse({'code': '00000', 'data': {}}),
        ),
      );
      addTearDown(cloud.dispose);
      await cloud.restore();
      expect(session.guestMode, isTrue);
      expect(cloud.needsLogin, isFalse);
    });
  });

  group('CloudService 端到端（假网关）', () {
    Future<(Repository, Session, ApiSettings, List<http.Request>)> setup() async {
      final temp = Directory.systemTemp.createTempSync('zudun_cloud_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final requests = <http.Request>[];
      final repository = await Repository.open();
      final session = Session(repository.store);
      final settings = ApiSettings(repository.store);
      return (repository, session, settings, requests);
    }

    /// 假网关：登录成功、用户详情可用、云端配置为空
    MockClient fakeGateway(List<http.Request> requests, {String? remoteData}) =>
        MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/login_with_code')) {
            return _jsonResponse({
              'code': '00000',
              'data': {'accessToken': 'T-123'},
            });
          }
          if (path.endsWith('/user_detail_info')) {
            return _jsonResponse({
              'code': '00000',
              'data': {'phone': '13800138000', 'nickName': '小张'},
            });
          }
          if (path.contains('/get/other/value/config/')) {
            return _jsonResponse({'code': '00000', 'data': remoteData});
          }
          if (path.endsWith('/other/save')) {
            return _jsonResponse({'code': '200'});
          }
          if (path.endsWith('/destroy_user')) {
            return _jsonResponse({'code': '200'});
          }
          return http.Response('{}', 404);
        });

    test('注销账号会清掉本机照片文件', () async {
      final (repository, session, settings, requests) = await setup();
      final bytes = Uint8List.fromList(List.generate(32, (index) => index));
      // 先登录，再把数据加到账号作用域，模拟「只在账号里存在的照片」
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: settings,
        httpClient: fakeGateway(requests),
      );
      await cloud.signIn(
        phone: '13800138000',
        validCode: '123456',
        byPassword: false,
      );
      await repository.addProperty(buildProperty());
      final ref = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'a.jpg',
      );
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph1',
          propertyId: 'p1',
          room: '客厅',
          imageRef: ref,
          thumbRef: ref,
          timestamp: DateTime(2026, 10, 1),
        ),
      );
      expect(await repository.readMedia(ref), isNotNull);
      await cloud.destroyAccount();

      expect(session.loggedIn, isFalse);
      expect(await repository.readMedia(ref), isNull, reason: '本机照片文件也要删掉');
      expect(repository.photos, isEmpty);
      cloud.dispose();
    });

    test('首次登录会把本机数据推到账号作用域', () async {
      final (repository, session, settings, requests) = await setup();

      await repository.addProperty(buildProperty());
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: settings,
        httpClient: fakeGateway(requests),
      );
      await cloud.signIn(
        phone: '13800138000',
        validCode: '123456',
        byPassword: false,
      );

      expect(cloud.loggedIn, isTrue);
      expect(session.dataKey, '13800138000ZuDunData');
      expect(cloud.state, SyncState.idle);
      // 本机数据被完整推送到账号作用域
      final save = requests.lastWhere(
        (request) => request.url.path.endsWith('/other/save'),
      );
      final body = jsonDecode(utf8.decode(save.bodyBytes)) as Map;
      expect(body['paramKey'], '13800138000ZuDunData');
      final payload =
          jsonDecode('${body['paramValue']}') as Map<String, dynamic>;
      expect((payload['properties']! as List), hasLength(1));
      // Token 通过 Authorization 头发送
      expect(
        requests
            .lastWhere(
              (request) => request.url.path.endsWith('/other/save'),
            )
            .headers['Authorization'],
        'T-123',
      );
      cloud.dispose();
    });

    test('云端已有数据时按 id 合并本机游客数据', () async {
      final (repository, session, settings, requests) = await setup();
      await repository.addProperty(buildProperty());
      final remote = <String, dynamic>{
        'version': 1,
        'properties': [
          {'id': 'remote-1', 'name': '云端的房源'},
        ],
        'photos': <Object>[],
        'rents': <Object>[],
        'utilities': <Object>[],
        'repairs': <Object>[],
        'rules': <Object>[],
        'comms': <Object>[],
        'settings': <String, Object?>{},
        'activeId': 'remote-1',
      };
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: settings,
        httpClient: fakeGateway(requests, remoteData: jsonEncode(remote)),
      );
      await cloud.signIn(
        phone: '13800138000',
        validCode: '123456',
        byPassword: false,
      );

      // 两边合并：云端的 remote-1 + 本机游客的 p1
      expect(repository.properties, hasLength(2));
      expect(
        repository.properties.map((property) => property.name),
        containsAll(['云端的房源', '翠屏里 3 栋 502']),
      );
      cloud.dispose();
    });

    test('pull 会用云端数据覆盖本机（同一账号作用域）', () async {
      final (repository, session, settings, requests) = await setup();
      await repository.addProperty(buildProperty());

      var remoteData = <String, dynamic>{};
      final client = MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/login_with_code')) {
          return _jsonResponse({
            'code': '00000',
            'data': {'accessToken': 'T-1'},
          });
        }
        if (path.endsWith('/user_detail_info')) {
          return _jsonResponse({'code': '00000', 'data': {}});
        }
        if (path.contains('/get/other/value/config/')) {
          return _jsonResponse({
            'code': '00000',
            'data': remoteData.isEmpty ? null : jsonEncode(remoteData),
          });
        }
        if (path.endsWith('/other/save')) {
          return _jsonResponse({'code': '200'});
        }
        return http.Response('{}', 404);
      });
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: settings,
        httpClient: client,
      );
      // 首次登录：云端为空，本机数据被推上去
      await cloud.signIn(
        phone: '13800138000',
        validCode: '123456',
        byPassword: false,
      );
      expect(repository.properties, hasLength(1));

      // 另一台设备在云端放了两套房源
      remoteData = <String, dynamic>{
        'version': 1,
        'properties': [
          {'id': 'a', 'name': 'A 房源'},
          {'id': 'b', 'name': 'B 房源'},
        ],
        'photos': <Object>[],
        'rents': <Object>[],
        'utilities': <Object>[],
        'repairs': <Object>[],
        'rules': <Object>[],
        'comms': <Object>[],
        'settings': <String, Object?>{},
        'activeId': 'a',
      };
      await cloud.pull(merge: false);
      expect(repository.properties, hasLength(2));
      expect(
        repository.properties.map((property) => property.name),
        containsAll(['A 房源', 'B 房源']),
      );
      cloud.dispose();
    });
  });

  group('租住与历史记录', () {
    Future<Repository> openTempRepository(String tag) async {
      final temp = Directory.systemTemp.createTempSync('zudun_$tag');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      return Repository.open();
    }

    test('当前租住回落到还在租的一套，退租的房子进入历史', () async {
      final repository = await openTempRepository('current_scope');
      await repository.addProperty(buildProperty());
      await repository.addProperty(buildHistoryProperty());

      // 选中的是已退租的房子时，当前租住回落到还在租的那套
      await repository.setActive('p2');
      expect(repository.currentProperty?.id, 'p1');
      expect(repository.historyProperties.map((p) => p.id), ['p2']);

      // 选中在租的房源时跟随用户选择
      await repository.setActive('p1');
      expect(repository.currentProperty?.id, 'p1');

      // 全部退租后没有当前租住，两套都进历史
      final p1 = repository.propertyById('p1')!;
      await repository.updateProperty(
        p1.copyWith(
          status: PropertyStatus.ended,
          deposit: DepositInfo(
            status: DepositStatus.returned,
            returnedAmount: 8000,
            returnedDate: DateTime(2026, 10, 8),
          ),
        ),
      );
      expect(repository.currentProperty, isNull);
      expect(repository.historyProperties, hasLength(2));
    });

    testWidgets('我的租住：当前租住卡片 + 历史记录入口', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = await openTestRepository(tester);
      await tester.runAsync(() async {
        await repository.addProperty(buildProperty());
        await repository.addProperty(buildHistoryProperty());
        await repository.setActive('p1');
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: const TenancyPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 左上角不再写「当前租住」，直接显示当前这套的名字（切换器）
      expect(find.text('当前租住'), findsNothing);
      expect(find.text('翠屏里 3 栋 502'), findsWidgets);
      expect(find.text('新增一套租住'), findsOneWidget);
      // 历史租住仍收在这一行的右上角
      expect(find.text('历史 1 套'), findsOneWidget);

      // 历史记录入口 → 历史页
      await tester.tap(find.text('历史 1 套'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('以前住的房子'), findsWidgets);
      expect(find.textContaining('退租 2026-09-30'), findsOneWidget);
      expect(find.textContaining('押金已退还'), findsOneWidget);
      // 还在租的房子不混进历史
      expect(find.text('翠屏里 3 栋 502'), findsNothing);
    });

    testWidgets('租住页：左上角是房源切换器，能换当前租住', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = await openTestRepository(tester);
      await tester.runAsync(() async {
        await repository.addProperty(buildProperty());
        await repository.addProperty(
          Property(
            id: 'p9',
            name: '第二套在租的房子',
            address: '北京市海淀区中关村大街 1 号',
            landlord: const Landlord(name: '李房东'),
            contract: ContractInfo(
              monthlyRent: 2000,
              deposit: 4000,
              moveInDate: DateTime(2026, 9, 1),
              contractEnd: DateTime(2027, 8, 31),
              rentDueDay: 5,
            ),
            status: PropertyStatus.active,
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
        );
        await repository.setActive('p1');
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(theme: ZTheme.light(), home: const TenancyPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 左上角显示当前这套的名字，不再是「当前租住」；两套在租 → 有下拉箭头
      expect(find.text('当前租住'), findsNothing);
      expect(find.text('翠屏里 3 栋 502'), findsWidgets);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      // 旧的「切换当前租住」列表行没了
      expect(find.text('切换当前租住'), findsNothing);

      // 点左上角 → 换到第二套
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(find.text('第二套在租的房子'), findsWidgets);
      await tester.tap(find.text('第二套在租的房子').last);
      await tester.pumpAndSettle();
      expect(repository.activeId, 'p9');
    });

    testWidgets('没有历史记录时给出退租后自动归档的提示', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = await openTestRepository(tester);
      await tester.runAsync(() => repository.addProperty(buildProperty()));

      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: const TenancyPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 左上角是当前房源名（只有一套时不摆下拉箭头）
      expect(find.text('翠屏里 3 栋 502'), findsWidgets);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      // 没有历史记录时不显示历史入口
      expect(find.textContaining('历史 '), findsNothing);
      // 那行「换房子时新增一套…」的说明文字也去掉了
      expect(find.textContaining('旧的会自动进入历史记录'), findsNothing);
    });
  });

  group('云端照片', () {
    test('登录后照片走云端引用，并带本地缓存', () async {
      final temp = Directory.systemTemp.createTempSync('zudun_media_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final repository = await Repository.open();
      final bridge = _FakeBridge();
      repository.cloud = bridge;

      final bytes = Uint8List.fromList(List.generate(64, (index) => index));
      final ref = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'a.jpg',
      );
      expect(ref, 'oss:/zudun/p1/a.jpg');
      expect(bridge.uploaded, hasLength(1));
      // 上传过的字节直接进入云端缓存，不再二次下载
      expect(await repository.readMedia(ref), bytes);
      expect(bridge.downloads, 0);

      // 缓存丢失时才会去云端下载
      const cacheKey = 'oss:/zudun/other.jpg';
      expect(await repository.readMedia(cacheKey), isNotNull);
      expect(bridge.downloads, 1);

      // 删除照片时一并释放云端文件
      await repository.addPhoto(
        EvidencePhoto(
          id: 'photo-1',
          propertyId: 'p1',
          room: '客厅',
          imageRef: ref,
          thumbRef: ref,
          timestamp: DateTime(2026, 10, 1),
        ),
      );
      await repository.deletePhoto('photo-1');
      expect(bridge.released, contains(ref));
    });
  });
}

/// 假网关响应：显式声明 utf-8，否则中文内容无法用 latin1 编码
http.Response _jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 清理测试用的临时目录：Windows 上偶发文件占用导致删除失败，忽略即可
void _cleanTemp(Directory temp) {
  try {
    temp.deleteSync(recursive: true);
  } catch (_) {
    // 系统临时目录会被自动回收
  }
}

/// 假的云端桥接：不联网，记录调用情况
class _FakeBridge implements CloudBridge {
  @override
  bool enabled = true;
  final List<String> uploaded = <String>[];
  final List<String> released = <String>[];
  int downloads = 0;

  @override
  Future<Uint8List?> readRemoteMedia(String ref) async {
    downloads++;
    return Uint8List.fromList(List.generate(8, (index) => index));
  }

  @override
  Future<String?> uploadMedia(Uint8List bytes, {required String name}) async {
    uploaded.add(name);
    return 'oss:/zudun/p1/$name';
  }

  @override
  Future<void> releaseRemoteMedia(List<String> refs) async {
    released.addAll(refs);
  }

  @override
  void schedulePush() {}
}
/// 主要页面冒烟：这种「无界高度」的布局问题只有点进去才会炸，
/// 所以每个页面单独一个用例渲染一遍。新增页面时记得往这里加一行。
void groupSmoke() {
  final pages = <String, Widget Function()>{
    '首页': () => const HomePage(),
    '我的租住': () => const TenancyPage(),
    '历史租住': () => const HistoryPage(),
    '费用': () => const ExpensePage(),
    '押金': () => const DepositPage(propertyId: 'p1'),
    '水电燃气': () => const UtilityPage(propertyId: 'p1'),
    '抄表录入': () => const UtilityEditPage(propertyId: 'p1'),
    '房源详情': () => const PropertyDetailPage(propertyId: 'p1'),
    '合同': () => const ContractPage(propertyId: 'p1'),
    '维修与沟通': () => const TimelinePage(propertyId: 'p1'),
    '入住取证': () => const EvidenceRoomsPage(propertyId: 'p1'),
    '退租对比': () => const ComparePage(propertyId: 'p1'),
    '我的': () => const ProfilePage(),
    '设置': () => const AboutPage(),
    '法规指南': () => const LegalGuidePage(),
    '文书模板': () => const TemplatesPage(),
    '提醒设置': () => const ReminderSettingsPage(),
    '登录': () => const LoginPage(),
    '押金规则': () => const RulesPage(propertyId: 'p1'),
    '账号与同步': () => const AccountPage(),
    '隐私与安全': () => const PrivacyPage(),
    '抄表历史': () => const UtilityHistoryPage(propertyId: 'p1'),
    '错误日志': () => const ErrorLogPage(),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key}：渲染不抛异常', (tester) async {
      await _pumpSmokePage(
        tester,
        entry.value,
        label: entry.key,
        brightness: Brightness.light,
      );
    });

    // 深色第 1 轮：同一批页面在深色令牌下也要能画出来
    testWidgets('${entry.key}：深色下渲染不抛异常', (tester) async {
      await _pumpSmokePage(
        tester,
        entry.value,
        label: entry.key,
        brightness: Brightness.dark,
      );
    });
  }
}

/// 冒烟：把页面挂到和真实 App 一样的主题接线上渲染一遍
Future<void> _pumpSmokePage(
  WidgetTester tester,
  Widget Function() build, {
  required String label,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // 令牌是全局的：跑完恢复浅色，避免污染其它用例
  addTearDown(() => Z.applyBrightness(Brightness.light));

  final repository = await openTestRepository(tester);
  await tester.runAsync(() => seedSmokeData(repository));
  final session = Session(repository.store);
  final settings = ApiSettings(repository.store);
  final cloud = CloudService(
    repository: repository,
    session: session,
    settings: settings,
    httpClient: MockClient(
      (request) async => _jsonResponse({'code': '00000', 'data': {}}),
    ),
  );
  addTearDown(cloud.dispose);

  // 令牌由 App 层在建树前设定（ZTheme 本身不再有副作用），冒烟时手动对齐
  Z.applyBrightness(brightness);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Repository>.value(value: repository),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<CloudService>.value(value: cloud),
        Provider<ApiSettings>.value(value: settings),
        ChangeNotifierProvider<NotificationService>.value(
          value: NotificationService(),
        ),
        ChangeNotifierProvider<ErrorLog>.value(value: ErrorLog(repository.store)),
      ],
      child: MaterialApp(
        theme: ZTheme.light(),
        darkTheme: ZTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        // 真实 App 里标签页都挂在 AppShell 的 Scaffold 下，
        // 首页 / 房源详情这类页面本身不带 Scaffold，冒烟时补上
        home: Scaffold(body: build()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final error = tester.takeException();
  expect(error, isNull, reason: error?.toString());

  if (brightness == Brightness.dark) {
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
      reason: '深色冒烟必须真的落在深色主题上',
    );
    final offenders = lightSurfaceOffenders(tester);
    expect(
      offenders,
      isEmpty,
      reason: '$label：深色下出现了近白底色块（应改用 Z.card / Z.surfaceMuted 等令牌）',
    );
    // 滚到底再查一遍：ListView 里没进视口的项也要检查（漏检过两次）
    for (var i = 0; i < 4; i++) {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) break;
      await tester.drag(scrollable.first, const Offset(0, -600));
      await tester.pumpAndSettle();
      final scrolled = lightSurfaceOffenders(tester);
      expect(
        scrolled,
        isEmpty,
        reason: '$label：往下滚之后出现了近白底色块',
      );
    }
  }
}

/// 深色下不该出现「不透明近白底块」。
///
/// 白字 / 白描边（它们不是色块）、渐变与照片、半透明叠加（如 hero 上的白色薄雾）、
/// 有意反色的 chip 与标记点都不算问题；这里只盯「整块实心近白」这种深色下最刺眼的底色。
List<String> lightSurfaceOffenders(WidgetTester tester) {
  final offenders = <String>[];

  // 刻意反色成浅底的控件不在此列：选中态 chip / tag / 圆点，
  // 以及 Material 规定的反色提示条（深色下的 SnackBar 本就是浅底）
  const invertedByDesign = {'ZChips', 'ZTag', 'ZPill', 'SnackBar'};

  String where(Element element) {
    final path = <String>[];
    element.visitAncestorElements((ancestor) {
      final key = ancestor.widget.key;
      path.add(
        ancestor.widget.runtimeType.toString() + (key == null ? '' : '[$key]'),
      );
      return path.length < 14;
    });
    return path.reversed.join(' < ');
  }

  void check(Color? color, String kind, Element element) {
    if (color == null) return;
    if (color.a < 0.95) return; // 半透明叠加放过
    if (relativeLuminance(color) < 0.7) return; // 只要近白

    // 太小的（圆点 / 分隔标记）不算色块
    final size = (element.renderObject as RenderBox?)?.size;
    if (size == null || size.width < 40 || size.height < 40) return;

    var insideInverted = false;
    element.visitAncestorElements((ancestor) {
      if (invertedByDesign.contains(ancestor.widget.runtimeType.toString())) {
        insideInverted = true;
        return false;
      }
      return true;
    });
    if (insideInverted) return;

    offenders.add('$kind $color <- ${where(element)}');
  }

  for (final element in tester.allElements) {
    final widget = element.widget;
    if (widget is ColoredBox) check(widget.color, 'ColoredBox', element);
    if (widget is Material) check(widget.color, 'Material', element);
    if (widget is DecoratedBox) {
      final decoration = widget.decoration;
      if (decoration is BoxDecoration &&
          decoration.gradient == null &&
          decoration.image == null) {
        check(decoration.color, 'DecoratedBox', element);
      }
    }
  }
  return offenders;
}

/// 冒烟测试用的数据：一套在租 + 一套历史，含抄表、维修、沟通、房东约定
Future<void> seedSmokeData(Repository repository) async {
  await repository.addProperty(buildProperty());
  await repository.addProperty(buildHistoryProperty());
  await repository.setActive('p1');
  await repository.saveUtility(
    UtilityRecord(
      id: 'u1',
      propertyId: 'p1',
      month: monthKey(DateTime.now()),
      electricity: const UtilityReading(
        reading: 25814,
        previousReading: 25620,
        unitPrice: 0.55,
        unit: 'kWh',
      ),
      water: const UtilityReading(
        reading: 1842,
        previousReading: 1806,
        unitPrice: 3.5,
        unit: 'm³',
      ),
      recordedAt: DateTime.now(),
    ),
  );
  await repository.saveRepair(
    RepairRecord(
      id: 'r1',
      propertyId: 'p1',
      item: '卫生间漏水',
      description: '楼上漏水到天花板',
      reportedAt: DateTime(2026, 10, 5),
    ),
  );
  await repository.saveRepair(
    RepairRecord(
      id: 'r2',
      propertyId: 'p1',
      item: '空调不制冷',
      description: '已联系维修师傅',
      reportedAt: DateTime(2026, 9, 20),
      status: RepairStatus.inProgress,
    ),
  );
  await repository.saveComm(
    CommunicationRecord(
      id: 'c1',
      propertyId: 'p1',
      content: '房东答应周末来修',
      tags: const ['维修'],
      timestamp: DateTime(2026, 10, 4),
    ),
  );
  await repository.saveRule(
    LandlordRule(
      id: 'rule1',
      propertyId: 'p1',
      content: '不可养宠物',
      createdAt: DateTime(2026, 3, 1),
    ),
  );
}

/// 用临时目录顶替 path_provider，拿到一个可以直接读写的 Repository
Future<Repository> openTestRepository(WidgetTester tester) async {
  final temp = Directory.systemTemp.createTempSync('zudun_test_repo');
  addTearDown(() => _cleanTemp(temp));
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return (await tester.runAsync(Repository.open))!;
}

/// 需要 Widget 环境的回归用例
void groupWidgets() {
  testWidgets('系统通知：环境不支持时要给出提示，且不写进设置', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    // 用一个「初始化就失败」的假通道，模拟平台没有实现的情况
    final notifications = NotificationService(
      channel: _FakeNotificationChannel(supported: false),
    );
    addTearDown(notifications.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: ChangeNotifierProvider<NotificationService>.value(
          value: notifications,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: const ReminderSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 测试环境里没有原生插件 → 服务应安静降级
    expect(find.text('提醒到点弹到系统通知栏'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(
      repository.settings.systemNotifications,
      isFalse,
      reason: '拿不到权限就不该把开关打开',
    );
    expect(
      notifications.available,
      isFalse,
      reason: '测试环境没有原生插件，应标记为不可用',
    );
  });

  testWidgets('系统通知：开启后按计划排期，关掉就清空', (tester) async {
    final repository = await openTestRepository(tester);
    final channel = _FakeNotificationChannel();
    final notifications = NotificationService(channel: channel);
    addTearDown(notifications.dispose);

    await tester.runAsync(() async {
      await seedSmokeData(repository);
      await repository.updateSettings(
        repository.settings.copyWith(systemNotifications: true),
      );
      // 只挂监听，排期由测试显式驱动，避免异步尾巴跑到用例结束之后
      notifications.attach(repository, syncNow: false);
      await notifications.sync();
    });

    expect(notifications.enabled, isTrue);
    expect(channel.scheduled, isNotEmpty, reason: '开了开关就该把提醒排给系统');
    expect(
      channel.cancelAllCount,
      0,
      reason: '重排只能清「待触发」的，不能把通知栏里已弹出的提醒撤掉',
    );
    expect(channel.cancelPendingCount, greaterThan(0));
    expect(
      channel.scheduled.map((item) => item.id).toSet(),
      notifications.plans.map((plan) => plan.id).toSet(),
      reason: '排期结果要和计划一一对应',
    );
    for (final plan in channel.scheduled) {
      expect(plan.when.hour, 9, reason: '通知统一在早上 9 点');
      expect(plan.when.isAfter(DateTime.now()), isTrue, reason: '不排过去的时刻');
    }

    // 关掉开关：计划清空，系统里的排期也要撤掉
    final cancelBefore = channel.cancelAllCount;
    await tester.runAsync(() async {
      await repository.updateSettings(
        repository.settings.copyWith(systemNotifications: false),
      );
      await notifications.sync();
    });
    expect(notifications.plans, isEmpty);
    expect(notifications.enabled, isFalse);
    expect(channel.cancelAllCount, greaterThan(cancelBefore));
    notifications.detach();
  });

  testWidgets('系统通知：系统拒绝授权时开关不会打开', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final notifications = NotificationService(
      channel: _FakeNotificationChannel(granted: false),
    );
    addTearDown(notifications.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: ChangeNotifierProvider<NotificationService>.value(
          value: notifications,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: const ReminderSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(
      repository.settings.systemNotifications,
      isFalse,
      reason: '没拿到授权就别打开开关，否则用户以为会被提醒',
    );
    expect(find.textContaining('系统还没允许通知'), findsOneWidget);
  });

  testWidgets('系统通知：已开启时列出接下来要提醒的事情', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final notifications = NotificationService(
      channel: _FakeNotificationChannel(),
    );
    addTearDown(notifications.dispose);

    await tester.runAsync(() async {
      await seedSmokeData(repository);
      await repository.updateSettings(
        repository.settings.copyWith(systemNotifications: true),
      );
      notifications.attach(repository, syncNow: false);
      await notifications.sync();
      notifications.detach();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: ChangeNotifierProvider<NotificationService>.value(
          value: notifications,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: const ReminderSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('已开启'), findsOneWidget);
    expect(
      find.text('发一条测试通知'),
      findsOneWidget,
      reason: '要留一个入口让用户验证通知到底通不通',
    );
  });

  testWidgets('点系统通知进来会落到对应标签页', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => seedSmokeData(repository));
    final session = Session(repository.store);
    await tester.runAsync(() => session.enterGuestMode());
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);
    final notifications = NotificationService();
    addTearDown(notifications.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
          ChangeNotifierProvider<NotificationService>.value(
            value: notifications,
          ),
        ],
        child: MaterialApp(theme: ZTheme.light(), home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 默认停在首页
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);

    // 合同到期的通知 → 「租住」
    notifications.handleTapPayload('p1|contractExpire');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.home_work_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_work_outlined), findsNothing);
    expect(notifications.pendingTapSlot, isNull, reason: '消费完要清掉');

    // 抄表通知 → 「费用」
    notifications.handleTapPayload('p1|utilityReading');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsOneWidget);
  });

  testWidgets('二级页面统一用同一个返回键组件', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => seedSmokeData(repository));
    final session = Session(repository.store);
    await tester.runAsync(() => session.enterGuestMode());
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    for (final page in <Widget>[
      const PropertyDetailPage(propertyId: 'p1'),
      const ContractPage(propertyId: 'p1'),
      const PrivacyPage(),
      const AboutPage(),
      const ReminderSettingsPage(),
    ]) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Repository>.value(value: repository),
            ChangeNotifierProvider<Session>.value(value: session),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
            Provider<ApiSettings>.value(value: settings),
            ChangeNotifierProvider<NotificationService>.value(
              value: NotificationService(),
            ),
          ],
          child: MaterialApp(
            theme: ZTheme.light(),
            home: Scaffold(body: page),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(ZBackButton),
        findsOneWidget,
        reason: '${page.runtimeType} 的返回键要统一',
      );
    }
  });

  testWidgets('全新安装：直接进登录页，不先弹协议确认页', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 没登录、也没选游客模式 = 刚装好的状态
    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      ZudunApp(
        repository: repository,
        session: session,
        cloud: cloud,
        notifications: NotificationService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('登录 / 注册'), findsWidgets, reason: '进页面就是登录页');
    expect(find.text('游客模式进入'), findsOneWidget);
    // 两份协议由用户自己点开，不再有「先同意」的中间页
    expect(find.text('同意并继续'), findsNothing);
    expect(find.text('《隐私政策》'), findsOneWidget);
    expect(find.text('《平台注册协议》'), findsOneWidget);
  });

  testWidgets('我的：深色模式开关反映当前明暗，拨一下即固定深色', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => Z.applyBrightness(Brightness.light));

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() => session.enterGuestMode());
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      ZudunApp(
        repository: repository,
        session: session,
        cloud: cloud,
        notifications: NotificationService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('深色模式'), findsOneWidget);
    // 默认跟随系统，测试环境是浅色 → 开关是关的
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(repository.settings.appearance, AppAppearance.dark);

    // 落盘完成、通知发出后，开关要变成开
    await tester.runAsync(
      () => repository.updateSettings(
        repository.settings.copyWith(appearance: AppAppearance.dark),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的：游客模式给出提示、不摆「关于租盾」、协议入口改名', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => seedSmokeData(repository));
    final session = Session(repository.store);
    await tester.runAsync(() => session.enterGuestMode());
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
          ChangeNotifierProvider<NotificationService>.value(
            value: NotificationService(),
          ),
        ],
        child: MaterialApp(theme: ZTheme.light(), home: const ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 游客模式：有对应的提示和登录入口
    expect(find.textContaining('游客模式'), findsWidgets);
    expect(find.text('去登录'), findsOneWidget);
    // 列表里不再出现「关于租盾」
    expect(find.text('关于租盾'), findsNothing);
    // 协议入口改成「隐私政策和平台注册协议」
    expect(find.text('隐私政策和平台注册协议'), findsOneWidget);
  });

  test('维修承担方：新增「共同承担」，序列化与旧数据都兼容', () {
    expect(
      CostBearer.values.map((bearer) => bearer.label),
      contains('共同承担'),
    );
    expect(CostBearer.shared.label, '共同承担');

    // 往返
    final repair = RepairRecord(
      id: 'r1',
      propertyId: 'p1',
      item: '洗衣机',
      description: '洗衣机坏了',
      reportedAt: DateTime(2026, 10, 12),
      cost: 100,
      costPaidBy: CostBearer.shared,
    );
    expect(RepairRecord.fromJson(repair.toJson()).costPaidBy, CostBearer.shared);

    // 老数据里没见过的值仍回落到「待确认」，不会读崩
    final legacy = RepairRecord.fromJson({
      'id': 'r2',
      'propertyId': 'p1',
      'item': '马桶',
      'description': '堵了',
      'reportedAt': '2026-10-01T00:00:00.000',
      'costPaidBy': 'somethingElse',
    });
    expect(legacy.costPaidBy, CostBearer.undecided);
  });

  testWidgets('记维修：弹窗里能选「共同承担」，保存后卡片按所选展示', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const TimelinePage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('记维修'));
    await tester.pumpAndSettle();
    expect(find.text('共同承担'), findsOneWidget);

    await tester.tap(find.text('共同承担'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '洗衣机坏了');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = repository.repairsOf('p1');
    expect(saved, hasLength(1));
    expect(saved.single.costPaidBy, CostBearer.shared);
    expect(find.text('共同承担'), findsOneWidget, reason: '卡片要按所选展示');
  });

  testWidgets('时间轴：竖线要连到下一张卡片的圆点，中间不能断', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveRepair(
        RepairRecord(
          id: 'r1',
          propertyId: 'p1',
          item: '洗衣机',
          description: '洗衣机坏了',
          reportedAt: DateTime(2026, 10, 12),
        ),
      );
      await repository.saveComm(
        CommunicationRecord(
          id: 'c1',
          propertyId: 'p1',
          content: '房东答应周末来修',
          tags: const ['维修'],
          timestamp: DateTime(2026, 10, 11),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const TimelinePage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final railFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.color == Z.line &&
          widget.constraints?.maxWidth == 1.5,
    );
    final dotFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );

    expect(dotFinder, findsNWidgets(2), reason: '两条记录就该有两个圆点');
    expect(railFinder, findsOneWidget, reason: '最后一张卡片下面不该再有线');

    final rail = tester.getRect(railFinder);
    final firstDot = tester.getRect(dotFinder.at(0));
    final nextDot = tester.getRect(dotFinder.at(1));

    expect(
      rail.top,
      lessThanOrEqualTo(firstDot.bottom + 0.5),
      reason: '线的上端要接着自己的圆点',
    );
    expect(
      rail.bottom,
      greaterThanOrEqualTo(nextDot.center.dy - 0.5),
      reason: '线的下端要落在下一个圆点上，中间不能断开',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('记沟通：标签可以多选，保存后都带上', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const TimelinePage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('记沟通'));
    await tester.pumpAndSettle();
    expect(find.text('标签（可多选）'), findsOneWidget);

    FilterChip chipOf(String label) =>
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

    await tester.tap(find.widgetWithText(FilterChip, '押金'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '维修'));
    await tester.pumpAndSettle();

    expect(chipOf('押金').selected, isTrue);
    expect(chipOf('维修').selected, isTrue, reason: '标签要能同时选中多个');

    await tester.enterText(
      find.byType(TextField).first,
      '房东说押金和维修一起算',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = repository.commsOf('p1');
    expect(saved, hasLength(1));
    expect(saved.single.tags, containsAll(<String>['押金', '维修']));
  });

  testWidgets('改完表计读数，水电燃气页的数字会跟着更新', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final thisMonth = monthKey(DateTime.now());
    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_this',
          propertyId: 'p1',
          month: thisMonth,
          electricity: const UtilityReading(
            reading: 1300,
            previousReading: 1200,
            unitPrice: 0.6,
            unit: 'kWh',
          ),
          recordedAt: DateTime.now(),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1300'), findsWidgets);

    // 点电表那行进编辑页，改成本月读数 1350
    // 「电表」在表计读数行和图例里都出现，取上面那个（读数行）
    await tester.tap(find.text('电表').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '本月读数',
          )
          .first,
      '1350',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('1350'),
      findsWidgets,
      reason: '改完读数要立刻反映到表计读数上',
    );
    expect(repository.utilityOfMonth('p1', thisMonth)?.electricity?.reading, 1350);
  });

  testWidgets('全部抄表记录：年份行给年度合计，点进去是 12 个月', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final thisMonth = monthKey(DateTime.now());
    final prevMonth = previousMonthKey(thisMonth);
    final year = thisMonth.split('-').first;
    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_prev',
          propertyId: 'p1',
          month: prevMonth,
          electricity: const UtilityReading(
            reading: 1200,
            previousReading: 1100,
            unitPrice: 0.6,
            unit: 'kWh',
          ),
          recordedAt: DateTime.now(),
        ),
      );
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_this',
          propertyId: 'p1',
          month: thisMonth,
          electricity: const UtilityReading(
            reading: 1300,
            previousReading: 1200,
            unitPrice: 0.6,
            unit: 'kWh',
          ),
          recordedAt: DateTime.now(),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityHistoryPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 年份行：年度合计 + 几个月有记录
    expect(find.text('$year 年'), findsOneWidget);
    expect(find.text('2 个月'), findsOneWidget);
    expect(find.text('合计'), findsOneWidget);

    await tester.tap(find.text('$year 年'));
    await tester.pumpAndSettle();

    // 12 个月都列出来：有记录的显示读数摘要，没有的显示「未记录」
    expect(find.text('12 个月明细'), findsOneWidget);
    expect(find.text('年度合计'), findsOneWidget);
    expect(find.text('未记录'), findsWidgets);
    expect(find.text(monthLabel(prevMonth)), findsOneWidget);
    expect(find.text(monthLabel(thisMonth)), findsOneWidget);

    // 点有记录的月份 → 编辑页，月份锁定
    await tester.tap(find.text(monthLabel(prevMonth)));
    await tester.pumpAndSettle();
    expect(find.text('编辑抄表记录'), findsOneWidget);
    expect(find.text(monthLabel(prevMonth)), findsOneWidget);
    expect(find.text('不可修改'), findsOneWidget);
  });

  testWidgets('首页：有房源时也显示「你已流浪 N 天」', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() => seedSmokeData(repository));
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
          ChangeNotifierProvider<NotificationService>.value(
            value: NotificationService(),
          ),
        ],
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 有房源也照样摆出来，跟「我的」页那行同一个说法
    expect(find.textContaining('你已流浪'), findsOneWidget);
  });

  testWidgets('首页：拍完取证能在「最近取证」看到照片，不只是个数字', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph1',
          propertyId: 'p1',
          room: '客厅',
          imageRef: 'media:p1/living.jpg',
          thumbRef: 'media:p1/living.thumb.jpg',
          timestamp: DateTime(2026, 10, 12, 20),
        ),
      );
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph2',
          propertyId: 'p1',
          room: '卧室',
          imageRef: 'media:p1/bedroom.jpg',
          thumbRef: 'media:p1/bedroom.thumb.jpg',
          timestamp: DateTime(2026, 10, 12, 21),
        ),
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          // 首页头部会读 Session（流浪天数），这个 Provider 不能少
          ChangeNotifierProvider<Session>.value(
            value: Session(repository.store),
          ),
        ],
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    // 缩略图在等真实的文件读取，FakeAsync 下会一直转圈，所以不用 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // 标题 + 数量 + 至少两张缩略图（ZPhoto）
    expect(find.text('最近取证'), findsOneWidget);
    expect(find.text('共 2 张'), findsOneWidget);
    expect(
      find.byType(ZPhoto),
      findsNWidgets(2),
      reason: '首页要能看到拍过的照片，而不是只有一个计数',
    );

    // 没有照片时给的是「去拍」入口，而不是空白
    await tester.runAsync(() async {
      await repository.deletePhoto('ph1');
      await repository.deletePhoto('ph2');
    });
    await tester.pumpAndSettle();
    expect(find.text('还没有取证照片'), findsOneWidget);
  });

  testWidgets('我的：头像 / 用户名 / 流浪天数三行，且不摆同步与统计信息', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() async {
      await seedSmokeData(repository);
      await session.enterGuestMode();
      await repository.updateSettings(
        repository.settings.copyWith(userName: '小王'),
      );
    });
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
        ],
        child: MaterialApp(theme: ZTheme.light(), home: const ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 第二行显示本机昵称，第三行是流浪天数
    expect(find.text('小王'), findsOneWidget);
    expect(find.textContaining('你已流浪'), findsOneWidget);

    // 云端同步 / 本机模式 / 几套房源 / 累计存证 都不该出现
    for (final gone in ['云端同步', '本机模式', '套房源', '累计存证']) {
      expect(find.textContaining(gone), findsNothing, reason: '$gone 不该显示');
    }
    // 数据备份 / 恢复也已去掉
    expect(find.textContaining('数据备份'), findsNothing);
  });

  testWidgets('我的：游客模式不能改资料（点资料卡只给提示）', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() => session.enterGuestMode());
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
          ChangeNotifierProvider<NotificationService>.value(
            value: NotificationService(),
          ),
        ],
        child: MaterialApp(theme: ZTheme.light(), home: const ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    // 游客的资料卡写明「登录后可修改资料」，不再摆「编辑资料」那套文案
    expect(find.text('编辑资料'), findsNothing);
    expect(find.text('登录后可修改资料'), findsOneWidget);

    // 点一下：不开编辑弹层，只给一条轻提示
    await tester.tap(find.text('未设置昵称'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(
      find.text('点击换头像'),
      findsNothing,
      reason: '游客不该打开编辑资料弹层',
    );
    expect(find.textContaining('游客模式不能修改资料'), findsOneWidget);
    expect(repository.settings.userName, isEmpty, reason: '资料也不该被改到');
  });

  testWidgets('设置：游客点「编辑资料」不弹资料弹层，只给提示', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() => session.enterGuestMode());
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
          ChangeNotifierProvider<NotificationService>.value(
            value: NotificationService(),
          ),
          ChangeNotifierProvider<ErrorLog>.value(
            value: ErrorLog(repository.store),
          ),
        ],
        child: MaterialApp(theme: ZTheme.light(), home: const AboutPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 设置页也不该摆版本号 / 应用说明 / 隐私与数据那一栏
    expect(find.textContaining('版本'), findsNothing);
    expect(find.text('应用说明'), findsNothing);
    expect(find.text('隐私与数据'), findsNothing);

    await tester.tap(find.text('编辑资料'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(
      find.text('点击换头像'),
      findsNothing,
      reason: '游客不该打开编辑资料弹层',
    );
    expect(find.textContaining('游客模式不能修改资料'), findsOneWidget);
  });

  testWidgets('我的：登录后能改用户名与生日，保存后页面跟着变', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);
    await tester.runAsync(
      () => session.saveLogin(
        token: 'T-1',
        phone: '13800138000',
        provider: 'code',
        user: {'nickName': '小张'},
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
          ChangeNotifierProvider<NotificationService>.value(
            value: NotificationService(),
          ),
        ],
        child: MaterialApp(theme: ZTheme.light(), home: const ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    // 登录后点头像卡 → 设置页（编辑资料现在收在这里）
    await tester.tap(find.text('小张'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget, reason: '资料卡应当跳到设置');
    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ZSheetHeader),
        matching: find.text('编辑资料'),
      ),
      findsOneWidget,
      reason: '弹层标题是「编辑资料」',
    );
    expect(find.text('点击换头像'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '李小明');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    // 落盘在 FakeAsync 下不会自己完成：轮询等它落完
    for (var i = 0; i < 20; i++) {
      if (repository.settings.userName == '李小明') break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(repository.settings.userName, '李小明', reason: '本机资料要写进去');

    // 退回「我的」页：名字要立刻跟着变（登录后以云端昵称为准）
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      if (find.text('李小明').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('李小明'), findsOneWidget, reason: '改完名字要立刻显示');

    // 登录态保存会排一次云端推送（900ms 防抖）：把这颗定时器走完，
    // 否则测试结束时会因为「还有 pending timer」报错
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('账号页不显示同步状态；维权指南 tab 与头部留了间距', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
        ],
        child: MaterialApp(theme: ZTheme.light(), home: const AccountPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('注销账号'), findsOneWidget);
    expect(
      find.textContaining('已同步'),
      findsNothing,
      reason: '账号页不摆同步状态',
    );

    await tester.pumpWidget(
      MaterialApp(theme: ZTheme.light(), home: const LegalGuidePage()),
    );
    await tester.pumpAndSettle();
    final appBar = tester.getRect(find.byType(ZAppBar));
    final tabs = tester.getRect(find.byType(ZChips<int>));
    expect(
      tabs.top - appBar.bottom,
      greaterThanOrEqualTo(9),
      reason: 'tab 不能顶着头部',
    );
  });

  testWidgets('添加房源：点下一步后不该还有输入框保持高亮', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyEditPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第 1 步：填完最后一个输入框（填满校验要求，才能真的翻到下一步）
    final name = find.byType(TextField).first;
    await tester.tap(name);
    await tester.enterText(name, '翠屏里 3 栋 502');
    await tester.pumpAndSettle();
    final address = find.byType(TextField).at(1);
    await tester.tap(address);
    await tester.enterText(address, '北京市朝阳区望京街道');
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus),
      isTrue,
      reason: '先在输入框里有焦点，才谈得上「翻页后还高亮」',
    );

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus),
      isFalse,
      reason: '翻页要收起键盘并取消焦点，否则上一个输入框会一直高亮',
    );
  });

  testWidgets('租住页：只留房东信息，合同要点与常用入口不再铺开', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.setActive('p1');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const TenancyPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 房东与联系方式留着：想打电话时一步到位
    expect(find.text('房东'), findsOneWidget);
    expect(find.text('房东电话'), findsOneWidget);

    // 合同要点与常用入口都收进房源详情页，这张卡片不再铺这些
    for (final gone in ['合同要点', '常用入口', '出租方式', '退租通知', '付款方式']) {
      expect(find.text(gone), findsNothing, reason: '$gone 不该再摆在租住页上');
    }
    // 户型与面积也不再展示
    expect(find.text('两室一厅'), findsNothing, reason: '不展示户型');
    expect(find.textContaining('㎡'), findsNothing, reason: '不展示面积');

    // 关键日期做成时间轴：入住 → 每月交租 → 到期
    expect(find.text('入住'), findsOneWidget);
    expect(find.text('每月交租'), findsOneWidget);
    expect(find.text('13 号'), findsOneWidget);
    expect(find.text('到期'), findsOneWidget);

    // 押金带进度：已缴纳 → 退租结算 → 已退还
    expect(find.text('已缴纳'), findsWidgets);
    expect(find.text('退租结算'), findsOneWidget);
    expect(find.text('已退还'), findsOneWidget);

    // 下一步：最该先做的那件待办（这套房还没拍入住取证）
    expect(find.textContaining('下一步'), findsWidgets);
  });

  testWidgets('房东要求：合同特殊条款也要展示，列表不再是红叉', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveRule(
        LandlordRule(
          id: 'rule1',
          propertyId: 'p1',
          content: '退租需提前 30 天通知',
          source: RuleSource.verbal,
          createdAt: DateTime(2026, 10, 1),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const RulesPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 编辑房源里写的特殊条款，在房东要求页也能看到（标明来自合同）
    expect(find.text('合同里的特殊条款'), findsOneWidget);
    expect(find.textContaining('不可养宠物'), findsOneWidget);
    expect(find.text('来自合同'), findsOneWidget);

    // 手动记的要求：内容 + 来源标签
    expect(find.text('退租需提前 30 天通知'), findsOneWidget);
    expect(find.text('口头约定'), findsOneWidget);

    // 上方提示改成「怎么用」的口径，不再是警告样式
    expect(find.textContaining('点右上角'), findsOneWidget);
  });

  testWidgets('切换深色：整棵树立刻换色，切到别的标签也不残留浅色', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => Z.applyBrightness(Brightness.light));

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() async {
      await seedSmokeData(repository);
      await session.enterGuestMode();
    });
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      ZudunApp(
        repository: repository,
        session: session,
        cloud: cloud,
        notifications: NotificationService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 取某张卡片的实际底色（渲染出来的那个）
    Color? cardColor() {
      final boxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(ZCard).first,
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>();
      for (final decoration in boxes) {
        if (decoration.color != null) return decoration.color;
      }
      return null;
    }

    expect(cardColor(), Z.card);

    // 切到「我的」再拨深色开关
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(repository.settings.appearance, AppAppearance.dark);

    // 落盘写入在 FakeAsync 里不会自己跑完（真实 App 里是毫秒级）：
    // 这里在 runAsync 里再写一次同样的设置，等价于「写完了、通知发出去了」
    await tester.runAsync(
      () => repository.updateSettings(
        repository.settings.copyWith(appearance: AppAppearance.dark),
      ),
    );
    await tester.pumpAndSettle();

    // 令牌与主题都该是深色，且不留任何浅色块（底栏、卡片、页面底色都在审计范围内）
    expect(Z.isDark, isTrue);
    expect(
      lightSurfaceOffenders(tester),
      isEmpty,
      reason: '切换深色后不该还有浅色卡片 / 底栏 / 页面底色',
    );
    expect(
      Theme.of(tester.element(find.byType(ProfilePage))).brightness,
      Brightness.dark,
    );

    // 再切到「租住」页：用户报的就是切过去还是浅色
    await tester.tap(find.byIcon(Icons.home_work_outlined));
    await tester.pumpAndSettle();
    expect(lightSurfaceOffenders(tester), isEmpty, reason: '租住页也要是深色');
    expect(Z.card, const Color(0xFF1A2231));

    // 切回浅色：同样的位置要变回白色
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => repository.updateSettings(
        repository.settings.copyWith(appearance: AppAppearance.light),
      ),
    );
    await tester.pumpAndSettle();
    expect(Z.isDark, isFalse);
    expect(cardColor(), const Color(0xFFFFFFFF), reason: '切回浅色要变回白底');
  });

  testWidgets('维修 / 沟通卡片：字段排布符合设计稿', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveRepair(
        RepairRecord(
          id: 'r1',
          propertyId: 'p1',
          item: '洗衣机',
          description: '洗衣机坏了',
          reportedAt: DateTime(2026, 10, 12),
          status: RepairStatus.pending,
          cost: 100,
          costPaidBy: CostBearer.landlord,
        ),
      );
      await repository.saveComm(
        CommunicationRecord(
          id: 'c1',
          propertyId: 'p1',
          content: '退租时退押金',
          tags: const ['押金'],
          isKeyPromise: true,
          timestamp: DateTime(2026, 10, 12),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const TimelinePage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 维修卡片：类型 + 状态 → 物品（带底色）+ 描述 → 时间 / 费用 / 承担方
    expect(find.text('维修'), findsOneWidget);
    expect(find.text('待处理'), findsOneWidget);
    expect(find.text('洗衣机'), findsOneWidget);
    expect(find.text('洗衣机坏了'), findsOneWidget);
    expect(find.text('维修时间'), findsOneWidget);
    expect(find.text('维修费用'), findsOneWidget);
    expect(find.text('承担方'), findsOneWidget);
    expect(find.text('房东承担'), findsOneWidget);

    // 沟通卡片：类型 + 标签 → 记录类型（带底色）+ 内容 → 沟通时间
    expect(find.text('沟通'), findsOneWidget);
    expect(find.text('关键承诺'), findsOneWidget);
    expect(find.text('退租时退押金'), findsOneWidget);
    expect(find.text('沟通时间'), findsOneWidget);
    expect(find.text('押金'), findsWidgets);
  });

  testWidgets('提示改成页面顶部的轻提示，并会自己消失', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ZTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => zToast(context, '已保存'),
                child: const Text('触发提示'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('已保存'), findsOneWidget);
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '不该再用页面底部的 SnackBar',
    );
    expect(
      tester.getTopLeft(find.text('已保存')).dy,
      lessThan(120),
      reason: '轻提示要出现在页面上方',
    );

    // 停 2.4 秒后自己收掉，不需要用户操作
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('已退租的房子：维修与沟通、水电燃气都是只读的', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await seedSmokeData(repository);
    });

    Future<void> pump(Widget page) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: Scaffold(body: page),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // 维修与沟通：有提示条，底部不再给新增入口
    await pump(const TimelinePage(propertyId: 'p2'));
    expect(find.textContaining('只能查看'), findsOneWidget, reason: '只读要有提示条');
    expect(find.text('记维修'), findsNothing);
    expect(find.text('记沟通'), findsNothing);

    // 水电燃气：去记录 / 修改本月 都不再出现
    await pump(const UtilityPage(propertyId: 'p2'));
    expect(find.textContaining('只能查看'), findsOneWidget);
    expect(find.text('去记录'), findsNothing);
    expect(find.text('修改本月'), findsNothing);

    // 抄表录入：提交按钮禁用（提示条也还在）
    await pump(const UtilityEditPage(propertyId: 'p2'));
    expect(find.textContaining('只能查看'), findsOneWidget);
    expect(
      tester.widget<ZButton>(find.widgetWithText(ZButton, '提交')).onTap,
      isNull,
      reason: '只读时提交要禁用',
    );
  });

  testWidgets('隐私与数据页只留两份协议入口', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: ZTheme.light(), home: const PrivacyPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('平台注册协议'), findsOneWidget);
    for (final gone in ['数据备份与恢复', '账号与同步', '权限说明', '注销账号', '相机']) {
      expect(find.text(gone), findsNothing, reason: '$gone 不该再摆在这个页面');
    }
  });

  testWidgets('房间相册：网格与幻灯片两种视图都能用', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      for (var i = 0; i < 3; i++) {
        await repository.addPhoto(
          EvidencePhoto(
            id: 'ph$i',
            propertyId: 'p1',
            room: '客厅',
            imageRef: 'a$i.jpg',
            thumbRef: 'a${i}_t.jpg',
            timestamp: DateTime(2026, 10, 1 + i),
            phase: PhotoPhase.moveIn,
          ),
        );
      }
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const Scaffold(
            body: RoomAlbumPage(
              propertyId: 'p1',
              room: '客厅',
              phase: PhotoPhase.moveIn,
            ),
          ),
        ),
      ),
    );
    // 缩略图在等真实的文件读取，FakeAsync 下会一直转圈，所以不用 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('已存证 3 张'), findsOneWidget);

    // 网格 → 幻灯片：翻页后标题里的页码要跟着走
    await tester.tap(find.byIcon(Icons.view_carousel_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1/3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('2/3'), findsOneWidget);
  });

  testWidgets('深色下照片占位不再是亮米色', (tester) async {
    addTearDown(() => Z.applyBrightness(Brightness.light));
    Z.applyBrightness(Brightness.dark);
    final repository = await openTestRepository(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          darkTheme: ZTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const Scaffold(
            body: SizedBox(width: 120, height: 90, child: ZPhoto(ref: null)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final placeholder = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(ZPhoto),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.gradient != null);
    final colors = (placeholder.gradient! as LinearGradient).colors;

    expect(colors.first, Z.surfaceMuted, reason: '深色下占位该用中性深色');
    expect(
      colors,
      isNot(contains(const Color(0xFFC3BBAE))),
      reason: '不该还是那块亮米色',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色下空状态也要换色（没有房子时的首页 / 费用页）', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => Z.applyBrightness(Brightness.light));
    Z.applyBrightness(Brightness.dark);

    // 故意不放任何数据：走的是「还没有房子」的空状态
    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    for (final page in <Widget>[
      const Scaffold(body: HomePage()),
      const Scaffold(body: ExpensePage()),
    ]) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Repository>.value(value: repository),
            ChangeNotifierProvider<Session>.value(value: session),
            ChangeNotifierProvider<CloudService>.value(value: cloud),
            Provider<ApiSettings>.value(value: settings),
            ChangeNotifierProvider<ErrorLog>.value(
              value: ErrorLog(repository.store),
            ),
          ],
          child: MaterialApp(
            theme: ZTheme.light(),
            darkTheme: ZTheme.dark(),
            themeMode: ThemeMode.dark,
            home: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 空状态里曾因为 children: const [...] 导致颜色被冻住，这里守住
      expect(
        lightSurfaceOffenders(tester),
        isEmpty,
        reason: '${page.runtimeType} 的空状态在深色下不该有浅色块',
      );
      for (var i = 0; i < 4; i++) {
        final scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isEmpty) break;
        await tester.drag(scrollable.first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(
          lightSurfaceOffenders(tester),
          isEmpty,
          reason: '${page.runtimeType} 滚下去也不该有浅色块',
        );
      }
    }
  });

  // 运行时切深色（而不是冷启动就是深色）：`const` 出来的组件很容易被「冻」在浅色，
  // 所以「没有房源的空状态」和「有房源的正常态」各守一遍。
  for (final withData in <bool>[false, true]) {
    testWidgets(
      '运行时切深色：${withData ? '有房源' : '空状态'}时首页 / 费用页要当场换色',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(() => Z.applyBrightness(Brightness.light));

        final repository = await openTestRepository(tester);
        final session = Session(repository.store);
        await tester.runAsync(() async {
          await session.enterGuestMode();
          if (withData) await seedSmokeData(repository);
        });
        final settings = ApiSettings(repository.store);
        final cloud = CloudService(
          repository: repository,
          session: session,
          settings: settings,
          httpClient: MockClient(
            (request) async => _jsonResponse({'code': '00000', 'data': {}}),
          ),
        );
        addTearDown(cloud.dispose);

        await tester.pumpWidget(
          ZudunApp(
            repository: repository,
            session: session,
            cloud: cloud,
            notifications: NotificationService(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 前提：浅色下确实能查到白底卡片，否则这个用例什么也没测到
        expect(
          lightSurfaceOffenders(tester),
          isNotEmpty,
          reason: '浅色下的白底卡片应该被审计抓到',
        );

        // 真实路径：外观设置一改就要整棵树重画，而不是等下次冷启动
        await tester.runAsync(() async {
          await repository.updateSettings(
            repository.settings.copyWith(appearance: AppAppearance.dark),
          );
        });
        await tester.pumpAndSettle();

        // 首页 / 费用页都在 AppShell 的 IndexedStack 里，审计会一起看
        expect(
          lightSurfaceOffenders(tester),
          isEmpty,
          reason: '切到深色后，首页 / 费用页不该再留下浅色块',
        );

        // 空状态的区块标题也得换色：用户报的「颜色和背景差不多、看不清」就是
        // 标题停在深墨色、压在已经变深的底上
        if (!withData) {
          expect(
            tester
                .widget<Text>(find.text('租盾能帮你做什么'))
                .style
                ?.color,
            Z.ink,
            reason: '深色下区块标题要跟着换成浅墨色',
          );
        }

        // ListView 只建可见项：滚到底再看一遍，别让没进视口的卡片漏过去
        Future<void> scrollThrough(Type page, String label) async {
          final scrollable = find.descendant(
            of: find.byType(page),
            matching: find.byType(Scrollable),
          );
          for (var i = 0; i < 4 && scrollable.evaluate().isNotEmpty; i++) {
            await tester.drag(scrollable.first, const Offset(0, -500));
            await tester.pumpAndSettle();
            expect(
              lightSurfaceOffenders(tester),
              isEmpty,
              reason: '$label 往下滚也不该有浅色块',
            );
          }
        }

        await scrollThrough(HomePage, '首页');
        // 底栏在 IndexedStack 之后，取最后一个同图标的就是「费用」这个 tab
        await tester.tap(
          find.byIcon(Icons.account_balance_wallet_outlined).last,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '切到费用页不该报错');
        await scrollThrough(ExpensePage, '费用页');

        // 再切回浅色：被冻住过的 const 子树要能原路变回去
        await tester.runAsync(() async {
          await repository.updateSettings(
            repository.settings.copyWith(appearance: AppAppearance.light),
          );
        });
        await tester.pumpAndSettle();
        expect(Z.isDark, isFalse);
        if (!withData) {
          expect(
            tester
                .widget<Text>(
                  find.text('租盾能帮你做什么', skipOffstage: false),
                )
                .style
                ?.color,
            const Color(0xFF0E1F3D),
            reason: '切回浅色要变回深墨色',
          );
        }
      },
    );
  }

  testWidgets('深色审计本身有效：白底大色块一定会被抓出来', (tester) async {
    addTearDown(() => Z.applyBrightness(Brightness.light));
    Z.applyBrightness(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: ZTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    expect(
      lightSurfaceOffenders(tester),
      isNotEmpty,
      reason: '审计要是抓不到白底，那它就是个摆设',
    );
  });

  testWidgets('外观设置：默认跟随系统，可在「设置」里选深色', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 令牌是全局的：跑完恢复浅色，避免污染其它用例
    addTearDown(() => Z.applyBrightness(Brightness.light));

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() async {
      await seedSmokeData(repository);
      await session.enterGuestMode();
    });
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      ZudunApp(
        repository: repository,
        session: session,
        cloud: cloud,
        notifications: NotificationService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
      reason: '默认外观是跟随系统',
    );

    // 我的 → 设置
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget, reason: '设置项要回显当前外观');

    // 外观 → 深色：三个选项都在，选完写进设置
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    expect(find.text('跟随系统'), findsWidgets);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '选外观不该抛异常');
    expect(repository.settings.appearance, AppAppearance.dark);
  });

  testWidgets('外观设置：设为深色后整个 App 按深色主题渲染', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => Z.applyBrightness(Brightness.light));

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(() async {
      await seedSmokeData(repository);
      await session.enterGuestMode();
      await repository.updateSettings(
        repository.settings.copyWith(appearance: AppAppearance.dark),
      );
    });
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      ZudunApp(
        repository: repository,
        session: session,
        cloud: cloud,
        notifications: NotificationService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      Theme.of(tester.element(find.byType(HomePage))).brightness,
      Brightness.dark,
      reason: '首页要落在深色主题上',
    );
    expect(Z.ink, const Color(0xFFE8EDF7), reason: '深色下令牌要跟着换');

    // 关于页要回显当前外观
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('深色'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ZScreen 在受限宽度下不再叠加第二层手机框', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: Z.contentMaxWidth,
            child: ZScreen(
              child: ColoredBox(
                key: Key('probe'),
                color: Color(0xFFFF0000),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(const Key('probe')));
    expect(size.width, Z.contentMaxWidth);
    // 旧实现会因为读到窗口宽度而再套一层 18px 上/下留白的容器（高度 864）
    expect(size.height, 900, reason: '页面应铺满外层给出的高度，不再重复套壳');
  });

  testWidgets('核心组件在 320 宽窄屏下不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ZTheme.light(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(Z.s4),
            children: const [
              ZCard(
                child: ZListRow(
                  icon: Icons.notifications_none_rounded,
                  title: '该交房租了 · ¥3,200 三个月一起付',
                  subtitle: '10-13 到期 · 押一付三 · 记得保留转账凭证',
                  trailing: ZTag(label: '待处理', tone: ZTone.warn),
                ),
              ),
              ZCard(
                child: Column(
                  children: [
                    ZKv(label: '房东姓名', value: '张建国'),
                    ZKv(
                      label: '合同到期',
                      value: '2026-12-31',
                      mono: true,
                      divider: false,
                    ),
                  ],
                ),
              ),
              ZSectionTitle(
                title: '待办提醒',
                icon: Icons.notifications_none_rounded,
                moreLabel: '3 项',
              ),
              ZButton(label: '保存并生成提醒计划'),
              SizedBox(height: Z.s3),
              ZHintBar(text: '每张照片自动加时间 / 位置 / 房间水印，不可编辑，仅可追加。'),
              SizedBox(height: Z.s3),
              ZField(
                label: '房源名称',
                required: true,
                child: TextField(decoration: InputDecoration()),
              ),
              Wrap(
                spacing: Z.s2,
                children: [
                  ZTag(label: '租住中', tone: ZTone.ok),
                  ZTag(label: '已缴纳', tone: ZTone.brand),
                  ZTag(label: '每月 13 号交租'),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: '窄屏下不应出现布局溢出');
  });

  testWidgets('抄表录入：本月读数留空、上月读数只读带入，月份锁定不可改', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final thisMonth = monthKey(DateTime.now());
    final prevMonth = previousMonthKey(thisMonth);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_prev',
          propertyId: 'p1',
          month: prevMonth,
          electricity: const UtilityReading(
            reading: 1200,
            previousReading: 1100,
            unitPrice: 0.62,
            unit: 'kWh',
          ),
          recordedAt: DateTime.now(),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityEditPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 月份是只读的：没有「选择年月」，也不能滑月份
    expect(find.text('选择年月'), findsNothing, reason: '月份不允许改');
    expect(find.text(monthLabel(thisMonth)), findsOneWidget);
    expect(find.text('不可修改'), findsOneWidget);

    // 上月读数只读带入上一月那条记录的值（不存在可编辑的上月读数输入框）
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '上月读数',
      ),
      findsNothing,
      reason: '上月读数不允许手改',
    );
    expect(find.text('1200'), findsWidgets, reason: '上月读数应显示上一月的值');

    // 本月没有记录 → 本月读数留空，不拿上个月的数糊上来
    // （单价输入框会带默认电价 / 水价，所以只看「本月读数」这几个框）
    final readingFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.decoration?.labelText == '本月读数')
        .toList();
    expect(readingFields, isNotEmpty);
    for (final field in readingFields) {
      expect(
        field.controller?.text,
        isEmpty,
        reason: '本月没有记录时，本月读数应该是空的',
      );
    }
    expect(find.text('提交'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('抄表录入：从年份页补录某个月只写那一个月，不碰别的月份', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final thisMonth = monthKey(DateTime.now());
    final prevMonth = previousMonthKey(thisMonth);
    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_this',
          propertyId: 'p1',
          month: thisMonth,
          electricity: const UtilityReading(
            reading: 1300,
            previousReading: 1200,
            unitPrice: 0.6,
            unit: 'kWh',
          ),
          recordedAt: DateTime.now(),
        ),
      );
    });

    // 直接按「补录上一月」的方式打开录入页
    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: UtilityEditPage(propertyId: 'p1', month: prevMonth),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(monthLabel(prevMonth)), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '1250');
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    final records = repository.utilitiesOf('p1');
    expect(records, hasLength(2), reason: '补录是一笔新记录，不该覆盖本月那条');
    final prev = records.firstWhere((r) => r.month == prevMonth);
    final current = records.firstWhere((r) => r.month == thisMonth);
    expect(prev.electricity?.reading, 1250);
    expect(
      current.electricity?.reading,
      1300,
      reason: '本月的记录必须原样不动',
    );
  });

  testWidgets('费用页：押金单独成块，租金日历有星期表头与状态行', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(contract: base.contract.copyWith(deposit: 800)),
      );
      await repository.setActive('p1');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(theme: ZTheme.light(), home: const ExpensePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 押金：金额 + 状态标签
    expect(find.text('¥800'), findsOneWidget, reason: '押金金额要看得见');
    expect(find.text('已缴纳'), findsWidgets);

    // 租金日历：星期表头 + 「几号交租 + 金额 + 状态」那一行
    for (final week in ['一', '二', '三', '四', '五', '六', '日']) {
      expect(find.text(week), findsOneWidget, reason: '星期表头缺了「$week」');
    }
    expect(find.text('13 号交租'), findsOneWidget, reason: '交租日要写在日历上方');

    // 点押金那块 → 押金追踪页，金额在那里也要能看到
    await tester.tap(find.text('¥800'));
    await tester.pumpAndSettle();
    expect(find.byType(DepositPage), findsOneWidget);
    expect(find.text('已缴纳押金'), findsOneWidget);
    expect(find.text('¥800'), findsWidgets);
  });

  testWidgets('登录页：渲染正常且未同意隐私说明时不提交', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
        ],
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 登录是主入口，游客模式是一个按钮
    expect(find.text('登录 / 注册'), findsWidgets);
    expect(find.text('手机号'), findsWidgets);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('或者'), findsOneWidget);
    expect(find.text('游客模式进入'), findsOneWidget);
    // 两份协议都能点开
    expect(find.text('《隐私政策》'), findsOneWidget);
    expect(find.text('《平台注册协议》'), findsOneWidget);
    // 服务器地址属于内部配置，不摆在登录页上
    expect(find.text('服务器地址'), findsNothing);
    expect(find.textContaining('让每一次租房'), findsOneWidget);

    // 按钮文案固定为「登录 / 注册」，未填写时给出轻提示（不是红色错误条）
    await tester.tap(find.text('登录 / 注册').last);
    await tester.pumpAndSettle();
    expect(find.text('请先输入手机号'), findsOneWidget);
    expect(find.byType(ZHintBar), findsNothing);

    // 按表单顺序逐项提示：手机号 → 验证码 → 协议
    await tester.enterText(find.byType(TextField).first, '13800138000');
    await tester.pumpAndSettle();
    expect(find.text('请先输入手机号'), findsNothing);
    await tester.tap(find.text('登录 / 注册').last);
    await tester.pumpAndSettle();
    expect(find.text('请先输入短信验证码'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录 / 注册').last);
    await tester.pumpAndSettle();
    expect(find.text('请先勾选下面的《隐私政策》和《平台注册协议》'), findsOneWidget);
    expect(session.loggedIn, isFalse);
    expect(tester.takeException(), isNull);

    // 点开《平台注册协议》能看到协议正文，关闭后回到登录页
    await tester.tap(find.text('《平台注册协议》'));
    await tester.pumpAndSettle();
    expect(find.text('平台注册协议'), findsOneWidget);
    // 协议正文只从服务端取：假网关没有配这个键，应给出失败与重试
    expect(find.textContaining('协议加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.textContaining('协议加载失败'), findsNothing);

    // 勾选协议后才会真的发请求；服务端返回异常时用醒目错误条
    final agreement = find.textContaining('我已阅读并同意', findRichText: true);
    await tester.tapAt(tester.getTopLeft(agreement) + const Offset(2, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录 / 注册').last);
    await tester.pumpAndSettle();
    expect(find.text('请先勾选下面的《隐私政策》和《平台注册协议》'), findsNothing);
    expect(find.textContaining('缺少访问凭证'), findsOneWidget);
    expect(session.loggedIn, isFalse);

    // 游客模式入口：点一下就完成选择，不需要再切面板
    expect(find.textContaining('数据只保存在这台设备'), findsOneWidget);
    // enterGuestMode 内部会先落地「首次使用时间」（真实文件写入），
    // 这里先在 runAsync 里完成它，避免被 FakeAsync 卡住后续步骤
    await tester.runAsync(() => session.ensureFirstSeen());
    // 出错提示条会把按钮顶到屏幕外，先滚动到可见位置再点
    final guestEntry = find.text('游客模式进入');
    await tester.ensureVisible(guestEntry);
    await tester.pumpAndSettle();
    await tester.tap(guestEntry);
    await tester.pumpAndSettle();
    expect(session.guestMode, isTrue);
    expect(cloud.needsLogin, isFalse);
  });

  testWidgets('账号页：已登录时展示账号与同步状态', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({'code': '00000', 'data': {}}),
      ),
    );
    addTearDown(cloud.dispose);
    await tester.runAsync(
      () => session.saveLogin(
        token: 'T-1',
        phone: '13800138000',
        provider: 'code',
        user: {'nickName': '小张'},
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Repository>.value(value: repository),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<CloudService>.value(value: cloud),
          Provider<ApiSettings>.value(value: settings),
        ],
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const AccountPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('小张'), findsWidgets);
    expect(find.text('138****8000'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('注销账号'), findsOneWidget);
    // 账号页只展示用户信息，不再展示同步细节与服务器地址
    expect(find.text('数据同步'), findsNothing);
    expect(find.text('服务器地址'), findsNothing);
    expect(find.text('上次同步'), findsNothing);
  });

  testWidgets('水电燃气页：表计读数列表在窄屏下不溢出', (tester) async {
    addTearDown(tester.view.reset);
    final repository = await openTestRepository(tester);
    final thisMonth = monthKey(DateTime.now());
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveUtility(
        UtilityRecord(
          id: 'u1',
          propertyId: 'p1',
          month: thisMonth,
          electricity: const UtilityReading(
            reading: 25814,
            previousReading: 25620,
            unitPrice: 0.55,
            unit: 'kWh',
          ),
          water: const UtilityReading(
            reading: 1842,
            previousReading: 1806,
            unitPrice: 3.5,
            unit: 'm³',
          ),
          propertyFee: 120,
          networkFee: 60,
          recordedAt: DateTime.now(),
        ),
      );
      // 只记录了电表的一条，用来覆盖「未记录 / 未使用」的明细行
      await repository.saveUtility(
        UtilityRecord(
          id: 'u2',
          propertyId: 'p1',
          month: previousMonthKey(thisMonth),
          electricity: const UtilityReading(
            reading: 25620,
            previousReading: 25430,
            unitPrice: 0.55,
            unit: 'kWh',
          ),
          recordedAt: DateTime.now(),
        ),
      );
    });

    // 320 是目标机型的最窄宽度，390 是常见机型
    for (final width in [320.0, 390.0]) {
      // 高度给足，保证两张抄表记录卡片都被布局出来
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: const UtilityPage(propertyId: 'p1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '宽度 $width 下不应溢出');

      // 表计读数：左边表名 + 右边读数与费用
      expect(find.text('电表'), findsWidgets);
      expect(find.text(fmtMoney((25814 - 25620) * 0.55)), findsWidgets);
      // 本月没记录的燃气表显示「去记录」
      expect(find.text('去记录'), findsWidgets);

      // 抄表记录列表：只展示有读数的表，不再出现「未使用 / 未记录」
      expect(find.text(monthLabel(thisMonth)), findsOneWidget);
      expect(
        find.text(monthLabel(previousMonthKey(thisMonth))),
        findsOneWidget,
      );
      expect(find.text('未使用'), findsNothing);
      expect(find.text('未记录'), findsNothing);
      expect(find.text('物业 / 网络'), findsOneWidget);
      // 记录页右侧有「全部记录」入口
      expect(find.text('全部记录'), findsOneWidget);
    }
  });

  groupSmoke();

  testWidgets('维修与沟通：两条以上记录时时间轴不报布局异常', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.saveRepair(
        RepairRecord(
          id: 'r1',
          propertyId: 'p1',
          item: '卫生间漏水',
          description: '楼上漏水到天花板，已通知房东',
          reportedAt: DateTime(2026, 10, 5),
        ),
      );
      await repository.saveComm(
        CommunicationRecord(
          id: 'c1',
          propertyId: 'p1',
          content: '房东答应周末来修',
          tags: const ['维修'],
          timestamp: DateTime(2026, 10, 4),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const TimelinePage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '时间轴不该抛布局异常');
    expect(find.text('卫生间漏水'), findsOneWidget);
    // 卡片标题与引用块都会出现这句
    expect(find.textContaining('房东答应周末来修'), findsWidgets);

    // 切换筛选也要能正常重建
    await tester.tap(find.text('待处理 1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('卫生间漏水'), findsOneWidget);
  });


    test('版本号比较与更新配置解析', () {
      expect(compareVersions('1.2.0', '1.1.9'), greaterThan(0));
      expect(compareVersions('1.0.1', '1.0.1'), 0);
      expect(compareVersions('1.1', '1.1.0'), 0);
      final fromString = parseAppUpdate(
        jsonEncode({
          'version': '1.2.0',
          'notes': '修复若干问题',
          'downloadUrl': 'https://a/b.apk',
        }),
      );
      expect(fromString?.version, '1.2.0');
      expect(fromString?.url, 'https://a/b.apk');
      final wrapped = parseAppUpdate({
        'paramValue': jsonEncode({'latestVersion': '2.0.0', 'forceUpdate': 1}),
      });
      expect(wrapped?.version, '2.0.0');
      expect(wrapped?.force, isTrue);
      expect(parseAppUpdate({'notes': '空配置'}), isNull);
      expect(parseAppUpdate(null), isNull);
    });

    testWidgets('版本更新弹窗：显示新版本并可关闭，同版本不弹', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> show(String version) => checkAppUpdateOnStart(
        context: tester.element(find.text('检查更新')),
        rawConfig: jsonEncode({'version': version, 'notes': '新增隐私确认页'}),
        currentVersion: '1.0.1',
        onConsumed: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ZTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => show('9.9.9'),
                  child: const Text('检查更新'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
      expect(find.text('新增隐私确认页'), findsOneWidget);
      await tester.tap(find.text('稍后再说'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v9.9.9'), findsNothing);

      // 同一个版本不再弹
      await show('1.0.1');
      await tester.pumpAndSettle();
      expect(find.textContaining('发现新版本'), findsNothing);
    });
}
