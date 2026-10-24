import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:zudun/services/api/agreement_api.dart';
import 'package:zudun/services/api/api_client.dart';
import 'package:zudun/services/api/api_settings.dart';
import 'package:zudun/services/api/config_api.dart';
import 'package:zudun/services/api/password_crypto.dart';
import 'package:zudun/services/app_update.dart';
import 'package:zudun/services/cloud_service.dart';
import 'package:zudun/services/contract_scanner.dart';
import 'package:zudun/services/notification_channel.dart';
import 'package:zudun/services/notification_plan.dart';
import 'package:zudun/services/notification_service.dart';
import 'package:zudun/services/pdf_service.dart';
import 'package:zudun/services/protocol_service.dart';
import 'package:zudun/services/session.dart';
import 'package:zudun/services/token_store.dart';
import 'package:zudun/services/watermark.dart';
import 'package:zudun/theme/app_theme.dart';
import 'package:zudun/theme/tokens.dart';
import 'package:zudun/ui/agreement/agreement_page.dart';
import 'package:zudun/ui/agreement/agreement_support.dart';
import 'package:zudun/ui/app_update_dialog.dart';
import 'package:zudun/ui/auth/login_page.dart';
import 'package:zudun/ui/compare/compare_page.dart';
import 'package:zudun/ui/evidence/capture_page.dart';
import 'package:zudun/ui/evidence/evidence_rooms_page.dart';
import 'package:zudun/ui/evidence/photo_detail_page.dart';
import 'package:zudun/ui/evidence/room_album_page.dart';
import 'package:zudun/ui/expense/deposit_page.dart';
import 'package:zudun/ui/expense/expense_page.dart';
import 'package:zudun/ui/expense/utility_edit_page.dart';
import 'package:zudun/ui/expense/utility_history_page.dart';
import 'package:zudun/ui/expense/utility_page.dart';
import 'package:zudun/ui/expense/utility_year_page.dart';
import 'package:zudun/ui/home/home_page.dart';
import 'package:zudun/ui/kit.dart';
import 'package:zudun/ui/media.dart';
import 'package:zudun/ui/privacy_gate.dart';
import 'package:zudun/ui/profile/about_page.dart';
import 'package:zudun/ui/profile/legal_guide_page.dart';
import 'package:zudun/ui/profile/privacy_page.dart';
import 'package:zudun/ui/profile/profile_page.dart';
import 'package:zudun/ui/profile/reminder_settings_page.dart';
import 'package:zudun/ui/profile/templates_page.dart';
import 'package:zudun/ui/property/contract_page.dart';
import 'package:zudun/ui/property/dispute_page.dart';
import 'package:zudun/ui/property/history_page.dart';
import 'package:zudun/ui/property/move_out_page.dart';
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
  _FakeNotificationChannel({
    this.supported = true,
    this.granted = true,
    this.acceptQueue = true,
  });

  /// false 模拟「这个平台没实现」，用于验证降级路径
  final bool supported;
  final bool granted;

  /// false 模拟「系统没接下排期」（iOS 没授权时的真实表现）
  final bool acceptQueue;

  final List<NotificationPlan> scheduled = [];
  final List<int> shown = [];
  int cancelAllCount = 0;
  int cancelPendingCount = 0;
  void Function(String? payload)? onTap;

  @override
  bool get supportsScheduling => true;

  @override
  Future<String?> diagnose() async => null;

  @override
  Future<String?> verify(int id) async => null;

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
  Future<NotificationPermission> checkPermission() async =>
      granted ? NotificationPermission.granted : NotificationPermission.denied;

  @override
  Future<int?> pendingCount() async => acceptQueue ? scheduled.length : 0;

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

class _FakeTokenStore implements TokenStore {
  _FakeTokenStore([this.value]);

  String? value;
  int clearCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async {
    clearCount++;
    value = null;
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

    test('合同期数含首尾月，和租金计划的期数一致', () {
      // 2026-03-01 签到 2026-12-31
      final property = buildProperty();
      expect(property.contract.totalMonths, 10);
      expect(
        buildRentSchedule(
          property: property,
          existing: const [],
          today: DateTime(2026, 3, 1),
        ),
        hasLength(10),
        reason: '向导里那句「共 N 期」必须和实际生成的期数一样（以前少算一期）',
      );
    });

    test('入住表底数落盘能存能读，也能真的清空', () {
      final contract = buildProperty().contract.copyWith(
        moveInElectricity: 1234.5,
        moveInWater: 88,
        moveInGas: 12,
      );

      final restored = ContractInfo.fromJson(
        jsonDecode(jsonEncode(contract.toJson())) as Map<String, dynamic>,
      );
      expect(restored.moveInElectricity, 1234.5);
      expect(restored.moveInWater, 88);
      expect(restored.moveInGas, 12, reason: '不落盘的话填了也白填');

      // 清空某一项：传 null 要真的写掉，不能因为 `??` 又被原值顶回来
      final cleared = contract.copyWith(moveInWater: null);
      expect(cleared.moveInWater, isNull);
      expect(cleared.moveInElectricity, 1234.5, reason: '没传的那两项保持原样');

      // 旧版本的数据里根本没有这三个键：读出来是「还没填」，不是 0
      final legacyRaw = buildProperty().toJson();
      final legacyContract = legacyRaw['contract'] as Map<String, dynamic>;
      legacyContract
        ..remove('moveInElectricity')
        ..remove('moveInWater')
        ..remove('moveInGas');
      final legacy = Property.fromJson(legacyRaw);
      expect(legacy.contract.moveInElectricity, isNull);
      expect(legacy.contract.moveInWater, isNull);
      expect(legacy.contract.moveInGas, isNull);
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
      expect(marchBefore.paidDate, isNull, reason: '还没到交租日，不该默认「已缴 1 个月」');

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
      final rentToday = today.firstWhere((r) => r.kind == ReminderKind.rentDue);
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

    test('本月账单已付时不再提醒本月交租（交租日还没到也不提醒）', () {
      // 交租日 13 号。10-13 那期提前付掉，今天 10-11 本来就落在「提前 3 天」
      // 的窗口里 —— 以前日历算法会在这里弹一条「该交房租了」，
      // 而费用页里这一期明明已经付了
      final list = build(
        DateTime(2026, 10, 11),
        rents: [
          RentRecord(
            id: 'r1',
            propertyId: property.id,
            month: '2026-10',
            amount: 3200,
            dueDate: DateTime(2026, 10, 13),
            status: RentStatus.paid,
            paidDate: DateTime(2026, 10, 9),
          ),
          RentRecord(
            id: 'r2',
            propertyId: property.id,
            month: '2026-11',
            amount: 3200,
            dueDate: DateTime(2026, 11, 13),
          ),
        ],
      );
      expect(
        list.where((r) => r.kind == ReminderKind.rentDue),
        isEmpty,
        reason: '本期已付，下一期还没到提醒窗口',
      );
    });

    test('本期付掉后，提醒落到下一期未付账单上', () {
      final rents = [
        RentRecord(
          id: 'r1',
          propertyId: property.id,
          month: '2026-10',
          amount: 3200,
          dueDate: DateTime(2026, 10, 13),
          status: RentStatus.paid,
          paidDate: DateTime(2026, 10, 9),
        ),
        RentRecord(
          id: 'r2',
          propertyId: property.id,
          month: '2026-11',
          amount: 3500,
          dueDate: DateTime(2026, 11, 13),
        ),
      ];

      final list = build(DateTime(2026, 11, 11), rents: rents);
      final rent = list.firstWhere((r) => r.kind == ReminderKind.rentDue);
      expect(rent.date, DateTime(2026, 11, 13), reason: '要指向下一期那张账单');
      expect(rent.daysLeft, 2);
      expect(
        rent.title.contains('3,500'),
        isTrue,
        reason: '金额用那一期账单上的，不是合同里的固定月租',
      );
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

    test('缺入住表底数就提醒补，补齐了自己消失', () {
      final missing = build(DateTime(2026, 3, 20))
          .firstWhere((r) => r.kind == ReminderKind.moveInReading);
      expect(missing.title, contains('水/电'));
      expect(missing.subtitle, isEmpty, reason: '标题已经说清是哪几块表，再补一句副标题纯属重复占地方');

      Property withReadings({double? elec, double? water, double? gas}) =>
          property.copyWith(
            contract: property.contract.copyWith(
              moveInElectricity: elec,
              moveInWater: water,
              moveInGas: gas,
            ),
          );

      // 没燃气表的房子（一条燃气读数都没记过）只要求电、水：
      // 不然「燃气表底数」永远填不上，这条待办也就永远消不掉
      final noGas = build(
        DateTime(2026, 3, 20),
        target: withReadings(elec: 1200, water: 88),
      );
      expect(
        noGas.any((r) => r.kind == ReminderKind.moveInReading),
        isFalse,
        reason: '家里没燃气表，不该为了燃气那一项一直催',
      );

      // 但确实在用燃气（有抄表记录里有燃气读数）时，燃气底数就得补
      final gasHome = build(
        DateTime(2026, 3, 20),
        target: withReadings(elec: 1200, water: 88),
        utilities: [
          UtilityRecord(
            id: 'u1',
            propertyId: property.id,
            month: '2026-02',
            recordedAt: DateTime(2026, 2, 20),
            gas: const UtilityReading(reading: 30, unit: 'm³'),
          ),
        ],
      );
      expect(
        gasHome.any((r) => r.kind == ReminderKind.moveInReading),
        isTrue,
        reason: '在用燃气的房子要补燃气表底数',
      );

      final filled = build(
        DateTime(2026, 3, 20),
        target: withReadings(elec: 1200, water: 88, gas: 12),
      );
      expect(
        filled.any((r) => r.kind == ReminderKind.moveInReading),
        isFalse,
        reason: '三项都填上，待办就该自己消失',
      );
    });

    test('合同里勾了「有燃气表」：还没抄过表也要燃气表底数', () {
      final withGas = property.copyWith(
        contract: property.contract.copyWith(
          hasGasMeter: true,
          moveInElectricity: 1200,
          moveInWater: 88,
        ),
      );
      expect(
        build(
          DateTime(2026, 3, 20),
          target: withGas,
        ).any((r) => r.kind == ReminderKind.moveInReading),
        isTrue,
        reason: '勾了有燃气表，燃气表底数就缺不得（哪怕还没抄过一次表）',
      );
      expect(
        build(
          DateTime(2026, 3, 20),
          target: withGas.copyWith(
            contract: withGas.contract.copyWith(moveInGas: 12),
          ),
        ).any((r) => r.kind == ReminderKind.moveInReading),
        isFalse,
        reason: '三项齐了待办就消失',
      );
    });

    test('关掉抄表提醒后，也不再催补表底数', () {
      final list = build(
        DateTime(2026, 3, 20),
        settings: config.copyWith(enableUtility: false),
      );
      expect(
        list.any((r) => r.kind == ReminderKind.moveInReading),
        isFalse,
        reason: '这条待办只服务于抄表，抄表提醒关了就不该还在催',
      );
    });

    test('已退租后一条待办都不催；纠纷中只留维权那条', () {
      final ended = property.copyWith(
        status: PropertyStatus.ended,
        // 押金还没退到手也一样不催：退租就算流程走完了
        deposit: const DepositInfo(status: DepositStatus.toBeReturned),
        updatedAt: DateTime(2026, 3, 1),
      );
      final list = build(DateTime(2026, 3, 11), target: ended);
      expect(list, isEmpty, reason: '退租后资料只读、流程走完，没有可催的事');

      // 纠纷中：只提醒维权（去导出材料），交租/抄表/取证那些同样不催
      final disputed = build(
        DateTime(2026, 3, 11),
        target: ended.copyWith(status: PropertyStatus.dispute),
      );
      expect(
        disputed.any(
          (r) =>
              r.kind == ReminderKind.rentDue ||
              r.kind == ReminderKind.utilityReading ||
              r.kind == ReminderKind.contractExpire ||
              r.kind == ReminderKind.photoMissing,
        ),
        isFalse,
        reason: '资料已经只读，再催这些就是点进去啥也干不了的死待办',
      );
      expect(
        disputed.single.kind,
        ReminderKind.depositReturn,
        reason: '纠纷中只留「押金纠纷维权中」这一条',
      );
      expect(disputed.single.actionLabel, '去维权');
    });

    test('已退租的房子不再提醒补表底数', () {
      final list = build(
        DateTime(2026, 3, 20),
        target: property.copyWith(status: PropertyStatus.ended),
      );
      expect(
        list.any((r) => r.kind == ReminderKind.moveInReading),
        isFalse,
        reason: '退租后抄表已经只读归档，补表底数没意义',
      );
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

    test('已退租就不再催押金；押金没退只体现在房源详情页', () {
      final ended = property.copyWith(
        status: PropertyStatus.ended,
        deposit: const DepositInfo(status: DepositStatus.toBeReturned),
        updatedAt: DateTime(2026, 3, 1),
      );
      expect(
        build(
          DateTime(2026, 3, 20),
          target: ended,
        ).any((r) => r.kind == ReminderKind.depositReturn),
        isFalse,
        reason: '退租就算流程走完了，不再天天催押金',
      );
      // 但「纠纷中」还要提醒维权（这条才是 enableDeposit 管的事）
      expect(
        build(
          DateTime(2026, 3, 20),
          target: ended.copyWith(status: PropertyStatus.dispute),
        ).any((r) => r.kind == ReminderKind.depositReturn),
        isTrue,
      );
      expect(
        build(
          DateTime(2026, 3, 20),
          target: ended.copyWith(status: PropertyStatus.dispute),
          settings: config.copyWith(enableDeposit: false),
        ).any((r) => r.kind == ReminderKind.depositReturn),
        isFalse,
        reason: '关掉押金提醒后连维权那条也不弹',
      );
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

  group('流浪天数：按自然日去重', () {
    Property rented({
      required String id,
      required DateTime moveIn,
      required DateTime end,
      PropertyStatus status = PropertyStatus.active,
    }) => Property(
      id: id,
      name: id,
      address: '测试地址',
      landlord: const Landlord(name: '房东', phone: '138****0000'),
      contract: ContractInfo(moveInDate: moveIn, contractEnd: end),
      status: status,
      createdAt: moveIn,
      updatedAt: moveIn,
    );

    final today = DateTime(2026, 10, 15);

    test('同时在租的两套房，今天只算一天', () {
      final days = countWanderingDays([
        rented(id: 'a', moveIn: today, end: DateTime(2027, 10, 14)),
        rented(id: 'b', moveIn: today, end: DateTime(2027, 10, 14)),
      ], now: today);
      expect(days, 1);
    });

    test('入住当天算一天；已退租的算到退租日（含当天）', () {
      expect(
        countWanderingDays([
          rented(
            id: 'a',
            moveIn: DateTime(2026, 10, 1),
            end: DateTime(2027, 1, 1),
          ),
        ], now: today),
        15,
        reason: '10/1 入住到今天 10/15：15 天',
      );
      expect(
        countWanderingDays([
          rented(
            id: 'h',
            moveIn: DateTime(2026, 8, 1),
            end: DateTime(2026, 8, 31),
            status: PropertyStatus.ended,
          ),
        ], now: today),
        31,
        reason: '8/1 入住、8/31 搬走是 31 天，不是 30 天',
      );
    });

    test('提前退租：算到退租日，不把合同剩下的日子（含未来）算进来', () {
      // 8/1 入住、9/30 就搬走了，但合同签到 12/31
      final early =
          rented(
            id: 'early',
            moveIn: DateTime(2026, 8, 1),
            end: DateTime(2026, 12, 31),
            status: PropertyStatus.ended,
          ).copyWith(
            deposit: const DepositInfo(
              status: DepositStatus.returned,
              returnedDate: null,
            ),
          );
      expect(
        countWanderingDays([early], now: today),
        76,
        reason: '没有退租记录时退回合同到期日，但不会超过今天（8/1–10/15 共 76 天）',
      );

      // 记了「押金已退还（9/30）」：就该在 9/30 收住，后面 91 天不算
      final withReturn = early.copyWith(
        deposit: early.deposit.copyWith(returnedDate: DateTime(2026, 9, 30)),
      );
      expect(
        countWanderingDays([withReturn], now: today),
        61,
        reason: '8/1–9/30 共 61 天',
      );
    });

    test('接着换房：前一段的最后一天与后一段的第一天不重复', () {
      final days = countWanderingDays([
        rented(
          id: 'old',
          moveIn: DateTime(2026, 8, 1),
          end: DateTime(2026, 9, 30),
          status: PropertyStatus.ended,
        ),
        rented(
          id: 'new',
          moveIn: DateTime(2026, 10, 1),
          end: DateTime(2027, 9, 30),
        ),
      ], now: today);
      expect(days, 76, reason: '8/1–9/30 共 61 天 + 10/1–10/15 共 15 天');
    });

    test('重叠的租期不会被数两遍', () {
      final days = countWanderingDays([
        rented(
          id: 'a',
          moveIn: DateTime(2026, 3, 1),
          end: DateTime(2026, 6, 30),
          status: PropertyStatus.ended,
        ),
        rented(
          id: 'b',
          moveIn: DateTime(2026, 5, 1),
          end: DateTime(2026, 6, 30),
          status: PropertyStatus.ended,
        ),
      ], now: today);
      expect(days, 122, reason: '并起来只算 3/1–6/30');
    });

    test('还没到入住日的不算，一套都没有就是 0', () {
      expect(
        countWanderingDays([
          rented(
            id: 'future',
            moveIn: DateTime(2026, 11, 1),
            end: DateTime(2027, 11, 1),
          ),
        ], now: today),
        0,
      );
      expect(countWanderingDays(const [], now: today), 0);
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

  // 押金状态**不再**映射房源状态（口径）：房源状态只有「完成退租」和
  // 「去纠纷」两个出口，所以这里没有什么映射可测 —— 行为靠押金页的
  // widget 用例守着（见「改押金状态不会把租住中的房子变成已退租」）。
  group('回归：押金与退租日', () {
    test('退租日：优先退还日期，其次退租类日志，最后合同到期日', () {
      final base = buildProperty();
      // 没有任何退租记录 → 退回合同到期日
      expect(moveOutDate(base), DateTime(2026, 12, 31));

      // 有「待退还」这类日志 → 就是那天
      final withLog = base.copyWith(
        deposit: base.deposit.copyWith(
          logs: [
            DepositLog(
              status: DepositStatus.toBeReturned,
              time: DateTime(2026, 10, 5),
              note: '完成退租',
            ),
          ],
        ),
      );
      expect(moveOutDate(withLog), DateTime(2026, 10, 5));

      // 有了押金退还日期 → 以它为准
      expect(
        moveOutDate(
          withLog.copyWith(
            deposit: withLog.deposit.copyWith(
              returnedDate: DateTime(2026, 10, 9),
            ),
          ),
        ),
        DateTime(2026, 10, 9),
      );
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
    expect(
      rents.firstWhere((r) => r['month'] == '2026-10')['id'],
      'cloud-rent',
    );
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
    await tester.runAsync(() => repository.store.setString(key, future));

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
    expect(repository.store.getString(key), future, reason: '只读保护下原数据必须一字不改');
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
    await idb.put(
      'media:p1/a.jpg',
      Uint8List.fromList(List<int>.filled(10, 1)),
    );
    expect(await idb.totalBytes(), 10 + thumb.length);

    await idb.delete('media:p1/a.jpg');
    expect(await idb.get('media:p1/a.jpg'), isNull);
    expect(await idb.totalBytes(), thumb.length);

    await idb.delete('media:p1/a.thumb.jpg');
    expect(await idb.totalBytes(), 0);
  });

  test('字体分工：界面用子集、PDF 用全量（别弄反）', () {
    final uiRegular = File('assets/fonts/NotoSansSC-Regular.ttf').lengthSync();
    final uiBold = File('assets/fonts/NotoSansSC-Bold.ttf').lengthSync();
    final pdfRegular = File('assets/fonts/pdf/NotoSansSC-Regular.ttf')
        .lengthSync();
    final pdfBold = File('assets/fonts/pdf/NotoSansSC-Bold.ttf').lengthSync();

    // 界面字体只带 App 用到的字：几百 KB 级别
    for (final size in [uiRegular, uiBold]) {
      expect(size, greaterThan(120 * 1024), reason: '子集不该小到没字形');
      expect(size, lessThan(600 * 1024), reason: '界面字体应该是子集（否则 Web 首屏白下几 MB）');
    }
    // PDF 字体必须保留全量：报告里的生僻字不能变 □
    for (final size in [pdfRegular, pdfBold]) {
      expect(size, greaterThan(1500 * 1024), reason: 'PDF 必须用全量字体，别被换成子集');
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
      reason:
          'PDF 全量字体只能等真正导出 PDF 时再取，'
          '放在启动路径上等于每个用户首屏多下 4MB',
    );
  });

  test('系统通知：苹果平台 initialize 返回 false 不算「平台不支持」', () {
    // iOS / macOS 的插件在「初始化时不顺带要授权」时恒回 false，而我们正是
    // 这么配的（启动时故意不弹授权框）。一旦把 false 当成初始化失败，整条
    // 系统通知链会被判成「平台不支持」：开关点了没反应、排期一条也排不出去。
    expect(
      LocalNotificationChannel.readyFromInitializeResult(false),
      isTrue,
      reason: '非 Web 端的 false 只说明「这次没顺带要授权」，不代表不支持',
    );
    expect(LocalNotificationChannel.readyFromInitializeResult(null), isTrue);
    expect(LocalNotificationChannel.readyFromInitializeResult(true), isTrue);
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

  test('系统通知计划：补填表底数的待办不进系统通知', () {
    final plans = buildNotificationPlan(
      reminders: [
        reminderOf(ReminderKind.moveInReading, date: DateTime(2026, 10, 13)),
      ],
      config: const ReminderSettings(),
      now: DateTime(2026, 10, 13, 10),
    );
    expect(plans, isEmpty, reason: '填表底数没有「到点」这一说，只留在首页待办里');
  });

  test('系统通知计划：id 稳定、按时间升序、换房子不串号', () {
    final reminders = [
      reminderOf(
        ReminderKind.rentDue,
        date: DateTime(2026, 11, 1),
        daysLeft: 5,
      ),
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
      other
          .map((p) => p.id)
          .toSet()
          .intersection(first.map((p) => p.id).toSet()),
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
          body: {
            'code': '00000',
            'data': {'accessToken': 'T'},
          },
        ),
        {'accessToken': 'T'},
      );
      // 200 → 返回整个响应体
      expect(
        resolveApiResponse(statusCode: 200, body: {'code': '200', 'msg': 'ok'}),
        {'code': '200', 'msg': 'ok'},
      );
      // 无 code 字段也算成功
      expect(resolveApiResponse(statusCode: 200, body: {'ok': true}), {
        'ok': true,
      });
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
        user: {'nickName': '小张', 'borrowFlag': 1},
      );
      expect(session.loggedIn, isTrue);
      expect(session.dataKey, '13800138000ZuDunData');
      expect(session.displayName, '小张');
      expect(session.borrowFlagEnabled, isTrue);

      // 重新读取（模拟重启）后仍然保持登录态
      final restored = Session(repository.store);
      await restored.restore();
      expect(restored.loggedIn, isTrue);
      expect(restored.phone, '13800138000');
      expect(restored.user['nickName'], '小张');
      expect(restored.borrowFlagEnabled, isTrue);

      await restored.updateUser({'borrowFlag': '0'});
      expect(restored.borrowFlagEnabled, isFalse);

      await restored.clear();
      expect(restored.loggedIn, isFalse);
      expect(restored.dataKey, 'GuestLocalZuDunData');
    });

    test('卸载重装清理 Keychain 残留，普通升级保留登录态', () async {
      final temp = Directory.systemTemp.createTempSync('zudun_reinstall_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final repository = await Repository.open();
      final tokenStore = _FakeTokenStore('orphaned-keychain-token');
      final freshInstall = Session(repository.store, tokenStore: tokenStore);
      await freshInstall.restore();

      expect(
        tokenStore.clearCount,
        1,
        reason: '本地容器为空但 Keychain 有 Token，说明是新安装',
      );
      expect(freshInstall.loggedIn, isFalse);

      await freshInstall.saveLogin(
        token: 'T-after-login',
        phone: '13800138000',
        provider: 'code',
        user: {'borrowFlag': 1},
      );
      expect(tokenStore.value, 'T-after-login');

      // 模拟旧版本升级：本地账号仍在，但还没有安装标记。
      await repository.store.remove('zudun.install.initialized');
      final upgraded = Session(repository.store, tokenStore: tokenStore);
      await upgraded.restore();
      expect(upgraded.loggedIn, isTrue);
      expect(tokenStore.clearCount, 1, reason: '普通升级不能把现有登录态清掉');
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

    test('没登录时不再读本机残留数据（游客数据只存内存）', () async {
      final temp = Directory.systemTemp.createTempSync('zudun_upgrade_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      // 模拟上一版本留在本机的游客数据
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
      // 数据不保存在本机：没登录就是空数据 + 要先去登录，
      // 那份残留数据不再读进来（登录时会被清掉）
      expect(repository.properties, isEmpty);
      expect(session.guestMode, isFalse);
      expect(cloud.needsLogin, isTrue);
    });

    test('游客态：写入只进内存，不落盘（重开就是空的）', () async {
      final temp = Directory.systemTemp.createTempSync('zudun_guest_mem_test');
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

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

      await repository.addProperty(buildProperty());
      expect(repository.properties, hasLength(1));
      expect(
        repository.rawDataOf(Repository.guestDataKey),
        isNull,
        reason: '游客数据只存内存，不该写进本机存储',
      );

      // 相当于重启 App：这次会话的数据不会再被读回来
      final reopened = await Repository.open();
      expect(reopened.properties, isEmpty);
    });

    test('游客态：拍的图片也不会留在本机（下次以游客身份启动就清掉）', () async {
      final temp = Directory.systemTemp.createTempSync(
        'zudun_guest_media_test',
      );
      addTearDown(() => _cleanTemp(temp));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final repository = await Repository.open();
      await repository.startFreshGuest();
      final ref = await repository.saveMedia(
        Uint8List.fromList(List<int>.generate(64, (i) => i)),
        folder: 'p1',
        name: 'a.jpg',
      );
      expect(ref, isNotEmpty);
      expect(await repository.readMedia(ref), isNotNull, reason: '本次会话要能看得到');

      // 相当于重启 App（仍是游客）：上次那份图片被清掉
      final again = await Repository.open();
      await again.startFreshGuest();
      expect(await again.readMedia(ref), isNull, reason: '游客拍的图片不该留在本机');
    });
  });

  group('CloudService 端到端（假网关）', () {
    Future<(Repository, Session, ApiSettings, List<http.Request>)>
    setup() async {
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

    test('退出登录会清空本机账号数据和照片，但保留云端数据', () async {
      final (repository, session, settings, requests) = await setup();
      final bytes = Uint8List.fromList(List.generate(32, (index) => index + 1));
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
      final accountKey = '${Repository.guestDataKey}.${session.scope}';
      await repository.addProperty(buildProperty());
      final ref = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'logout.jpg',
      );
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph-logout',
          propertyId: 'p1',
          room: '客厅',
          imageRef: ref,
          thumbRef: ref,
          timestamp: DateTime(2026, 10, 1),
        ),
      );

      expect(repository.rawDataOf(accountKey), isNotNull);
      expect(await repository.readMedia(ref), isNotNull);

      await cloud.logout();

      expect(session.loggedIn, isFalse);
      expect(repository.rawDataOf(accountKey), isNull);
      expect(repository.properties, isEmpty);
      expect(repository.photos, isEmpty);
      expect(await repository.readMedia(ref), isNull);
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
            .lastWhere((request) => request.url.path.endsWith('/other/save'))
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
          child: MaterialApp(theme: ZTheme.light(), home: const TenancyPage()),
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
          child: MaterialApp(theme: ZTheme.light(), home: const TenancyPage()),
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
      // 云优先：拍完上传成功后本机不再留原件（只留浏览缓存）。
      // 第一次看这张照片要下载一次，之后就走缓存
      expect(await repository.readMedia(ref), isNotNull);
      expect(bridge.downloads, 1);
      expect(await repository.readMedia(ref), isNotNull);
      expect(bridge.downloads, 1, reason: '第二次应该命中缓存');

      // 缓存丢失时才会去云端下载
      const cacheKey = 'oss:/zudun/other.jpg';
      expect(await repository.readMedia(cacheKey), isNotNull);
      expect(bridge.downloads, 2);

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

    test('本机照片用可移植引用，容器路径变了也能读回来', () async {
      final repository = await openMediaRepository();
      final bytes = Uint8List.fromList(List.generate(32, (index) => index));
      final ref = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'a.jpg',
      );

      // 数据里存的是相对引用，不是「这次安装」的绝对路径
      expect(ref, 'media:p1/a.jpg');
      expect(await repository.readMedia(ref), bytes);

      // 旧版本写下的绝对路径（容器 UUID 已经变了）也要找得回来：
      // 取 zudun_media 之后那段，按当前媒体目录重拼
      expect(
        await repository.readMedia(
          '/var/mobile/OldContainer/Documents/zudun_media/p1/a.jpg',
        ),
        bytes,
      );
    });

    test('登录后把只在本机的照片补传云端，成功就清掉本机原件', () async {
      final repository = await openMediaRepository();
      final bytes = Uint8List.fromList(List.generate(32, (index) => index + 1));

      // 游客态 / 没登录：先只留在本机
      final localRef = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'guest.jpg',
      );
      expect(localRef, 'media:p1/guest.jpg');
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph1',
          propertyId: 'p1',
          room: '客厅',
          imageRef: localRef,
          thumbRef: localRef,
          timestamp: DateTime(2026, 10, 1),
        ),
      );
      expect(repository.localOnlyPhotoCount, 1);

      // 登录后（有可用的云端桥）补传：记录改成云端引用
      final bridge = _FakeBridge();
      repository.cloud = bridge;
      // 原图与缩略图两条引用都换成云端引用，但同一份文件只会传一次
      expect(await repository.backfillCloudMedia(), 2);
      expect(repository.photosOf('p1').first.imageRef, startsWith('oss:'));
      expect(repository.localOnlyPhotoCount, 0);
      expect(bridge.uploaded, ['guest.jpg']);

      // 云端确实有了之后，本机原件才清掉；浏览缓存另算
      expect(await repository.releaseLocalMedia(), 1);
      expect(
        await repository.readMedia(localRef),
        isNull,
        reason: '本机原件应该被清掉，否则换设备前都还占着本地',
      );
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
    // 已退租的详情页走归档视图（六块内容摊成只读几段），
    // 渲染路径和其他页面一样要盯浅色 + 深色
    '已退租详情': () => const PropertyDetailPage(propertyId: 'p2'),
    '合同': () => const ContractPage(propertyId: 'p1'),
    '维修与沟通': () => const TimelinePage(propertyId: 'p1'),
    '入住取证': () => const EvidenceRoomsPage(propertyId: 'p1'),
    '退租对比': () => const ComparePage(propertyId: 'p1'),
    '退租': () => const MoveOutPage(propertyId: 'p1'),
    '标记纠纷': () => const DisputePage(propertyId: 'p1'),
    '我的': () => const ProfilePage(),
    '设置': () => const AboutPage(),
    '法规指南': () => const LegalGuidePage(),
    '文书模板': () => const TemplatesPage(),
    '提醒设置': () => const ReminderSettingsPage(),
    '登录': () => const LoginPage(),
    '押金规则': () => const RulesPage(propertyId: 'p1'),
    '隐私与安全': () => const PrivacyPage(),
    '抄表历史': () => const UtilityHistoryPage(propertyId: 'p1'),
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
      expect(scrolled, isEmpty, reason: '$label：往下滚之后出现了近白底色块');
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
/// 带本机媒体目录的仓库：照片写到临时目录，不碰真的 path_provider
Future<Repository> openMediaRepository() async {
  final temp = Directory.systemTemp.createTempSync('zudun_media_test');
  addTearDown(() => _cleanTemp(temp));
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return Repository.open();
}

Future<Repository> openTestRepository(WidgetTester tester) async {
  final temp = Directory.systemTemp.createTempSync('zudun_test_repo');
  addTearDown(() => _cleanTemp(temp));
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async => temp.path);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final repository = (await tester.runAsync(Repository.open))!;
  // 默认当作「用户上次已经同意过协议」：首次启动弹窗是模态的，
  // 不预置就会挡住其它用例的操作；要验证弹窗本身的用例自己把这条清掉。
  await tester.runAsync(
    () => repository.store.setString(kPrivacyConsentKey, zudunProtocolVersion),
  );
  return repository;
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
    expect(
      find.widgetWithText(SwitchListTile, '系统通知'),
      findsOneWidget,
      reason: '开关那行的名字就叫「系统通知」',
    );
    // 不支持也要把原因摆出来，否则真机上只看到「不支持」没法查
    expect(find.textContaining('假通道：这个平台没实现通知'), findsOneWidget);
    expect(find.text('复制原因'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(
      repository.settings.systemNotifications,
      isFalse,
      reason: '拿不到权限就不该把开关打开',
    );
    expect(notifications.available, isFalse, reason: '测试环境没有原生插件，应标记为不可用');
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
    expect(channel.cancelAllCount, 0, reason: '重排只能清「待触发」的，不能把通知栏里已弹出的提醒撤掉');
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

  testWidgets('系统通知：系统没接下排期时要说清楚，不能装作已开启', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    // 模拟 iOS 没授权时的情况：排期调用不报错，但系统一条都没接
    final notifications = NotificationService(
      channel: _FakeNotificationChannel(acceptQueue: false),
    );
    addTearDown(notifications.dispose);

    await tester.runAsync(() async {
      await seedSmokeData(repository);
      await repository.updateSettings(
        repository.settings.copyWith(systemNotifications: true),
      );
      notifications.attach(repository, syncNow: false);
      await notifications.sync();
    });

    expect(notifications.plans, isNotEmpty);
    expect(notifications.queuedCount, 0);
    expect(notifications.lastError, contains('系统没有接下'));

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

    expect(find.textContaining('系统一条排期都没接下'), findsOneWidget);
    notifications.detach();
  });

  testWidgets('提醒设置：开关已开但系统没授权时，给出「授权系统通知」入口', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final notifications = NotificationService(
      channel: _FakeNotificationChannel(granted: false),
    );
    addTearDown(notifications.dispose);

    await tester.runAsync(() async {
      await seedSmokeData(repository);
      // 开关是上次留下的设置（比如从别的平台同步过来），但系统从没授权
      await repository.updateSettings(
        repository.settings.copyWith(systemNotifications: true),
      );
      notifications.attach(repository, syncNow: false);
      await notifications.sync();
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

    expect(find.text('授权系统通知'), findsOneWidget);
    expect(find.textContaining('系统还没允许'), findsWidgets);
    expect(notifications.permission, NotificationPermission.denied);
    notifications.detach();
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
    // 排得好好的时候不再写状态行（以前这里报「已开启，系统里已排好 N 条提醒」）
    expect(find.textContaining('已开启'), findsNothing);
    expect(find.text('发一条测试通知'), findsNothing, reason: '页面不再摆测试通知按钮，通不通看排期清单');
    // 清单要能一眼看出「排了哪些、一共几条、几点响」
    expect(find.text('接下来要提醒的'), findsOneWidget);
    expect(
      find.text('共 ${notifications.plans.length} 条'),
      findsOneWidget,
      reason: '只看得到最近 3 行时，至少要知道一共排了多少条',
    );
    final first = notifications.plans.first;
    expect(
      find.textContaining(first.propertyName),
      findsWidgets,
      reason: '每行要说清是哪套房的提醒',
    );
    expect(
      find.textContaining(fmtTime(first.when)),
      findsWidgets,
      reason: '要写清几点响：页面上以前从没说过是早上 9 点',
    );
  });

  testWidgets('提醒设置：不再摆「发一条测试通知」按钮，失败原因仍要说清楚', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final notifications = NotificationService(
      channel: _FakeNotificationChannel(),
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

    // 打开系统通知开关（开关本身会顺手发一条，页面上不再有测试按钮）
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(repository.settings.systemNotifications, isTrue);
    expect(find.text('发一条测试通知'), findsNothing);
    expect(find.textContaining('已发一条测试通知'), findsNothing);
    expect(find.textContaining('下拉通知栏'), findsNothing);

    // 发得出去就返回 null，界面不用再补一句提示
    expect(
      await notifications.showTest(),
      isNull,
      reason: '发成功返回 null，界面就不用再补一句提示',
    );

    // 发不出去才需要说清楚原因（而不是灰着毫无反应）
    final offline = NotificationService(
      channel: _FakeNotificationChannel(supported: false),
    );
    addTearDown(offline.dispose);
    expect(
      await offline.showTest(),
      contains('不支持系统通知'),
      reason: '不支持的环境要说清楚，不能静默返回',
    );
  });

  testWidgets('退租对比：tab 不顶着头部，导出只留底部那一个入口', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      for (final (id, room) in [('ph1', '客厅'), ('ph2', '卧室')]) {
        await repository.addPhoto(
          EvidencePhoto(
            id: id,
            propertyId: 'p1',
            room: room,
            imageRef: 'media:p1/$id.jpg',
            thumbRef: 'media:p1/$id.thumb.jpg',
            timestamp: DateTime(2026, 10, 12, 20),
          ),
        );
      }
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const ComparePage(propertyId: 'p1'),
        ),
      ),
    );
    // 照片是 media: 引用、加载不出来会一直转圈（测试环境没有真实文件），
    // 所以只推几帧把布局摆好，不用 pumpAndSettle 等它安静
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.takeException(), isNull);

    final appBar = tester.getRect(find.byType(ZAppBar));
    final tabs = tester.getRect(find.byType(ZChips<String>));
    expect(
      tabs.top - appBar.bottom,
      greaterThanOrEqualTo(9),
      reason: 'tab 不能顶着头部',
    );

    // 右上角那个导出按钮去掉了，导出统一走底部的主按钮
    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(find.text('导出对比报告 PDF'), findsOneWidget);
  });

  testWidgets('首页：进 App 时有新版本才弹更新框', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 真机跑的是 iOS 包：这里也让平台判定走 iOS，才会读 iosAppVersion 那套字段
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // 必须在用例体内复位（测试框架会检查这个调试变量没被留下），
    // 所以用 try/finally 包住，哪怕断言失败也不会漏
    try {
      final repository = await openTestRepository(tester);
      await tester.runAsync(() => seedSmokeData(repository));
      final session = Session(repository.store);
      await tester.runAsync(
        () => session.saveLogin(
          token: 'T-update',
          phone: '13800138000',
          provider: 'code',
          user: {'borrowFlag': 1},
        ),
      );
      final settings = ApiSettings(repository.store);
      final notifications = NotificationService();
      addTearDown(notifications.dispose);

      /// 进 App（AppShell 第一屏就是首页），版本配置由假网关给
      Future<void> pumpApp(String version) async {
        final cloud = CloudService(
          repository: repository,
          session: session,
          settings: settings,
          httpClient: MockClient((request) async {
            // 版本更新读系统配置，键名就是应用标识（ApiSettings.appBrand）
            if (request.url.path.contains('/get/value/config/')) {
              return _jsonResponse({
                'code': '00000',
                'data': {
                  'paramValue': jsonEncode({
                    'iosAppVersion': version,
                    'iosAppDownloadUrl':
                        'https://apps.apple.com/app/id1234567890',
                    'iosUpdateType': 1,
                  }),
                },
              });
            }
            return _jsonResponse({'code': '00000', 'data': {}});
          }),
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
                value: notifications,
              ),
            ],
            child: MaterialApp(theme: ZTheme.light(), home: const AppShell()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      // 有新版本：弹窗就落在首页上（下面是首页，不是别的标签页）
      await pumpApp('9.9.9');
      expect(find.text('应用有新版本了'), findsOneWidget);
      expect(find.text('版本 9.9.9'), findsOneWidget);
      expect(
        find.textContaining('https://'),
        findsNothing,
        reason: '弹窗里不显示下载地址，只显示版本号',
      );
      expect(find.text('前往 App Store'), findsOneWidget);
      expect(
        find.byIcon(Icons.home_rounded),
        findsOneWidget,
        reason: '弹更新框时底下停在首页',
      );
      await tester.tap(find.text('稍后更新'));
      await tester.pumpAndSettle();
      expect(find.textContaining('应用有新版本了'), findsNothing);

      // 没有更高版本：首页安静，什么都不弹
      await pumpApp('1.0.1');
      expect(find.textContaining('应用有新版本了'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('首页：登录后 borrowFlag 到位才检查更新', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final repository = await openTestRepository(tester);
      await tester.runAsync(() => seedSmokeData(repository));
      final session = Session(repository.store);
      await tester.runAsync(
        () => session.saveLogin(
          token: 'T-update',
          phone: '13800138000',
          provider: 'code',
        ),
      );
      final settings = ApiSettings(repository.store);
      final notifications = NotificationService();
      addTearDown(notifications.dispose);
      var configRequests = 0;
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: settings,
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/get/value/config/')) {
            configRequests += 1;
            return _jsonResponse({
              'code': '00000',
              'data': {
                'paramValue': jsonEncode({
                  'iosAppVersion': '9.9.9',
                  'iosAppDownloadUrl':
                      'https://apps.apple.com/app/id1234567890',
                  'iosUpdateType': 1,
                }),
              },
            });
          }
          return _jsonResponse({'code': '00000', 'data': {}});
        }),
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
              value: notifications,
            ),
          ],
          child: MaterialApp(theme: ZTheme.light(), home: const AppShell()),
        ),
      );
      await tester.pumpAndSettle();
      expect(configRequests, 0, reason: '只有登录凭证、还没有 borrowFlag 时不能检查更新');
      expect(find.textContaining('应用有新版本了'), findsNothing);

      await tester.runAsync(() async {
        await session.updateUser({'borrowFlag': 1});
        // 会话监听器会在用户详情返回后立即发起配置请求；这里等真实 IO
        // 完成，再回到 widget fake-async 里推进弹窗。
        for (var i = 0; i < 20 && configRequests == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(session.borrowFlagEnabled, isTrue);
      await tester.pumpAndSettle();
      expect(configRequests, 1, reason: '用户详情返回 borrowFlag=1 后开始检查');
      expect(find.text('应用有新版本了'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('首页：未登录或 borrowFlag 不是 1 时不检查更新', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final repository = await openTestRepository(tester);
      await tester.runAsync(() => seedSmokeData(repository));
      final settings = ApiSettings(repository.store);
      final notifications = NotificationService();
      addTearDown(notifications.dispose);
      var configRequests = 0;

      Future<void> pumpWith(Session session) async {
        final cloud = CloudService(
          repository: repository,
          session: session,
          settings: settings,
          httpClient: MockClient((request) async {
            if (request.url.path.contains('/get/value/config/')) {
              configRequests += 1;
              return _jsonResponse({
                'code': '00000',
                'data': {
                  'paramValue': jsonEncode({
                    'iosAppVersion': '9.9.9',
                    'iosAppDownloadUrl':
                        'https://apps.apple.com/app/id1234567890',
                    'iosUpdateType': 1,
                  }),
                },
              });
            }
            return _jsonResponse({'code': '00000', 'data': {}});
          }),
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
                value: notifications,
              ),
            ],
            child: MaterialApp(theme: ZTheme.light(), home: const AppShell()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('应用有新版本了'), findsNothing);
      }

      final guest = Session(repository.store);
      await tester.runAsync(() => guest.enterGuestMode());
      await pumpWith(guest);
      expect(configRequests, 0, reason: '游客模式不检查更新');

      final nonBorrowing = Session(repository.store);
      await tester.runAsync(
        () => nonBorrowing.saveLogin(
          token: 'T-update',
          phone: '13800138001',
          provider: 'code',
          user: {'borrowFlag': '0'},
        ),
      );
      await pumpWith(nonBorrowing);
      expect(configRequests, 0, reason: 'borrowFlag 不是 1 时连版本配置都不请求');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('agreement：服务入口未配置时显示可重试状态', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    final session = Session(repository.store);
    await tester.runAsync(
      () => session.saveLogin(
        token: 'T-agreement',
        phone: '13800138000',
        provider: 'code',
        user: {'borrowFlag': 1},
      ),
    );
    final settings = ApiSettings(repository.store);
    final cloud = CloudService(
      repository: repository,
      session: session,
      settings: settings,
      httpClient: MockClient(
        (request) async => _jsonResponse({
          'code': '00000',
          'data': jsonEncode({'h5DownloadUrl': ''}),
        }),
      ),
    );
    addTearDown(cloud.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<CloudService>.value(
        value: cloud,
        child: MaterialApp(theme: ZTheme.light(), home: const AgreementPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('暂时无法进入'), findsOneWidget);
    expect(find.text('服务入口暂未配置'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });

  testWidgets('首页：切回首页与从后台回来都会重新检查更新', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final repository = await openTestRepository(tester);
      await tester.runAsync(() => seedSmokeData(repository));
      final session = Session(repository.store);
      await tester.runAsync(
        () => session.saveLogin(
          token: 'T-update',
          phone: '13800138000',
          provider: 'code',
          user: {'borrowFlag': 1},
        ),
      );
      final settings = ApiSettings(repository.store);
      final notifications = NotificationService();
      addTearDown(notifications.dispose);

      // 服务端版本号可改：用来验证「每次回首页都会重新查」
      var serverVersion = '1.0.1';
      final cloud = CloudService(
        repository: repository,
        session: session,
        settings: settings,
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/get/value/config/')) {
            return _jsonResponse({
              'code': '00000',
              'data': {
                'paramValue': jsonEncode({
                  'iosAppVersion': serverVersion,
                  'iosAppDownloadUrl':
                      'https://apps.apple.com/app/id1234567890',
                  'iosUpdateType': 1,
                }),
              },
            });
          }
          return _jsonResponse({'code': '00000', 'data': {}});
        }),
      );
      addTearDown(cloud.dispose);
      Widget agreementStub(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭 agreement 测试页'),
          ),
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
              value: notifications,
            ),
          ],
          child: MaterialApp(
            theme: ZTheme.light(),
            home: AppShell(agreementPageBuilder: agreementStub),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('关闭 agreement 测试页'),
        findsOneWidget,
        reason: 'borrowFlag=1 且没有更新时进入 agreement',
      );
      await tester.tap(find.text('关闭 agreement 测试页'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('应用有新版本了'),
        findsNothing,
        reason: '进首页时服务端说 1.0.1，和当前版本一样，不弹',
      );

      // 切后台再回来（停在首页）→ 重新查，这次服务端有新版本
      serverVersion = '9.9.9';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('应用有新版本了'), findsOneWidget);
      expect(find.text('版本 9.9.9'), findsOneWidget);
      await tester.tap(find.text('稍后更新'));
      await tester.pumpAndSettle();

      // 普通更新选「稍后更新」后，同一版本在 24 小时内不再弹
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('应用有新版本了'),
        findsNothing,
        reason: '普通更新稍后一次后，同一版本 24 小时内不再打扰',
      );
      expect(
        find.text('关闭 agreement 测试页'),
        findsOneWidget,
        reason: '跳过该版本后没有可展示更新，因此进入 agreement',
      );
      await tester.tap(find.text('关闭 agreement 测试页'));
      await tester.pumpAndSettle();

      // 停在「我的」时从后台回来不弹（回到首页才查）……
      serverVersion = '10.0.0';
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('应用有新版本了'), findsNothing, reason: '不在首页时不打扰');

      // ……切回「首页」立刻重查，新版本弹出来
      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pumpAndSettle();
      expect(find.text('应用有新版本了'), findsOneWidget);
      expect(find.text('版本 10.0.0'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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

  testWidgets('标题栏：返回键与标题在同一条中线上', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: ZScreen(
          child: Column(
            children: [ZAppBar(title: '入住取证', leading: ZBackButton())],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 整条标题栏 56 高：返回键和标题都得落在它的中线上，
    // 以前返回键是「顶部对齐」的，比标题高半个身位
    final bar = tester.getRect(find.byType(ZAppBar));
    final back = tester.getCenter(find.byType(ZBackButton));
    final title = tester.getCenter(find.text('入住取证'));
    expect(back.dy, closeTo(bar.center.dy, 1));
    expect((back.dy - title.dy).abs(), lessThan(1), reason: '返回键要跟标题同高');
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
    expect(CostBearer.values.map((bearer) => bearer.label), contains('共同承担'));
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
    expect(
      RepairRecord.fromJson(repair.toJson()).costPaidBy,
      CostBearer.shared,
    );

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

    await tester.enterText(find.byType(TextField).first, '房东说押金和维修一起算');
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
    // 这条记录当初存过基准（1200），所以不会弹窗催填
    expect(find.textContaining('没有上一月的抄表记录'), findsNothing);
    expect(find.textContaining('请录入'), findsNothing);
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
    expect(
      repository.utilityOfMonth('p1', thisMonth)?.electricity?.reading,
      1350,
    );
    expect(
      repository.utilityOfMonth('p1', thisMonth)?.electricity?.previousReading,
      1200,
      reason: '回来改本月读数，不能把这条记录当初存的基准弄丢',
    );
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
    expect(find.text('不可修改'), findsNothing);
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

  testWidgets('入住取证：添加房间不该红屏，输入的名字要真的加进去', (tester) async {
    tester.view.physicalSize = const Size(390, 1010);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(
        buildProperty().copyWith(rooms: const ['客厅', '储物间']),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const EvidenceRoomsPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pump();

    // 交互放在 runAsync 里：入库要真的写盘，notifyListeners 才会回来
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), '书房');
      await tester.tap(find.text('添加'));
      // 弹窗退场动画也要跑完：以前控制器就是在这段时间被 dispose 的，
      // TextField 重建时直接红屏
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    });

    expect(tester.takeException(), isNull);
    expect(
      repository.propertyById('p1')!.allRooms,
      contains('书房'),
      reason: '输入的房间名要真的加进去',
    );
  });

  testWidgets('取证房间列表：点哪间高亮哪间，点房间名也生效', (tester) async {
    tester.view.physicalSize = const Size(390, 1010);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      // 除了卫生间，其余房间都拍过；阳台有一张，待会儿进相册再退出
      for (final room in ['客厅', '主卧', '次卧', '厨房', '阳台']) {
        await repository.addPhoto(
          EvidencePhoto(
            id: 'ph-$room',
            propertyId: 'p1',
            room: room,
            imageRef: 'media:p1/$room.jpg',
            thumbRef: 'media:p1/$room.thumb.jpg',
            timestamp: DateTime(2026, 10, 15),
          ),
        );
      }
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const EvidenceRoomsPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 还没点的时候默认第一间
    expect(find.text('为「客厅」拍照取证'), findsOneWidget);

    // 点房间名也要能高亮（以前只有照片区域可点，点「卫生间」没反应）
    await tester.tap(find.text('卫生间'));
    await tester.pump();
    expect(find.text('为「卫生间」拍照取证'), findsOneWidget, reason: '点房间名也要高亮');

    // 点有照片的房间：先高亮这间，再打开相册
    await tester.tap(find.text('阳台'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RoomAlbumPage), findsOneWidget);

    Navigator.of(tester.element(find.byType(RoomAlbumPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('为「阳台」拍照取证'), findsOneWidget, reason: '点哪间，回来就还高亮哪间');

    // 再点卫生间，高亮跟着走
    await tester.tap(find.text('卫生间'));
    await tester.pump();
    expect(find.text('为「卫生间」拍照取证'), findsOneWidget);
  });

  testWidgets('退租取证：点照片或照片左右空白都能收起问题描述键盘', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
    });
    final bytes = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 60, height: 120)),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: CapturePage(
            propertyId: 'p1',
            room: '客厅',
            phase: PhotoPhase.moveOut,
            bytes: bytes,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 点问题描述框，键盘弹出
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    // 点照片本身：收回键盘
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onPanStart != null,
      ),
    );
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    // 再点开键盘，点照片左右留白（竖图两侧）也要收回
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    final area = tester.getRect(
      find.byKey(const ValueKey('capture-photo-area')),
    );
    await tester.tapAt(Offset(area.left + 6, area.center.dy));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse, reason: '点照片左右空白也要收键盘');
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
          // 首页头部的流浪天数现在读 Repository，这里留着 Session 是为了
          // 走通「已登录」分支（部分子组件按登录态取文案）
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

  testWidgets('我的：资料卡不再跳设置，设置走列表里那一行', (tester) async {
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

    // 资料卡上不再摆「编辑资料 / 登录后可修改资料」这类文案（整块已去掉）
    expect(find.text('编辑资料'), findsNothing);
    expect(find.text('登录后可修改资料'), findsNothing);

    // 点资料卡：什么也不发生（只是展示卡）
    await tester.tap(find.text('未设置昵称'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsNothing);

    // 设置还是从列表那一行进
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('我的：全部房源的租房账本（总租金 / 总租住天数 / 平均租金）', (tester) async {
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
        child: MaterialApp(theme: ZTheme.light(), home: const ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 两套房合计的已付租金（每套的入住当月都按已付算）
    final expectedRent =
        repository.totalPaidRent('p1') + repository.totalPaidRent('p2');
    expect(find.text('总租金'), findsOneWidget);
    expect(find.text('总租住天数'), findsOneWidget);
    expect(find.text('平均租金/天'), findsOneWidget);
    expect(
      find.text(fmtMoney(expectedRent)),
      findsOneWidget,
      reason: '总租金要等于各房源已付租金之和',
    );
    // 有租住天数才会算平均，别显示成 0
    expect(find.text('0 天'), findsNothing);
  });

  testWidgets('设置：游客也能编辑资料（只存本机）', (tester) async {
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
    await tester.pumpAndSettle();
    // 游客照旧能编辑，只是只落本机；登录后保存才会同步到账号
    expect(find.text('点击换头像'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
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

    // 设置 → 编辑资料（资料卡已经不再跳设置了）
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
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

  testWidgets('设置页：账号操作进设置；维权指南 tab 与头部留了间距', (tester) async {
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
    // 退出登录 / 注销账号只在登录后出现在设置里，先模拟登录
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
        child: MaterialApp(theme: ZTheme.light(), home: const AboutPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('注销账号'), findsOneWidget);
    expect(find.textContaining('已同步'), findsNothing, reason: '账号页不摆同步状态');

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

  testWidgets('添加房源：点「立即取证」要真的进到入住取证页', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
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

    // 第 1 步：名称 + 地址
    await tester.enterText(find.byType(TextField).first, '望京 SOHO 公寓 A 座 1802');
    await tester.enterText(find.byType(TextField).at(1), '北京市朝阳区望京街 10 号院');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // 第 2 步：房东
    await tester.enterText(find.byType(TextField).first, '张建国');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // 第 3 步：月租 / 押金
    await tester.enterText(find.byType(TextField).at(0), '6800');
    await tester.enterText(find.byType(TextField).at(1), '13600');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('保存并生成提醒计划'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    // 创建完问「要不要现在取证」
    expect(find.text('房源已创建'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('立即取证'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    // 以前这里什么都不发生（页面先被 pop 掉了）
    expect(find.text('入住取证'), findsWidgets, reason: '要进到入住取证页');
  });

  testWidgets('每月交租日：小屏上弹层不溢出', (tester) async {
    // 小屏 + 大字：28 个日期以前会超过默认的半个屏幕高度
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

    await tester.enterText(find.byType(TextField).first, '望京 SOHO 公寓 A 座 1802');
    await tester.enterText(find.byType(TextField).at(1), '北京市朝阳区望京街 10 号院');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '张建国');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    // 小屏上「每月交租日」在下面，先滚到它
    final dueField = find.textContaining('每月 ');
    for (var i = 0; i < 8 && dueField.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(dueField, findsWidgets, reason: '要能滚到「每月交租日」');
    await tester.tap(dueField.first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '弹层不能溢出');
    expect(find.text('每月几号交租'), findsOneWidget);
  });

  testWidgets('每月交租日：点开是紧凑的数字格，不是占满屏的下拉菜单', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
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

    await tester.enterText(find.byType(TextField).first, '望京 SOHO 公寓 A 座 1802');
    await tester.enterText(find.byType(TextField).at(1), '北京市朝阳区望京街 10 号院');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '张建国');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 点开「每月 N 号」
    await tester.tap(find.textContaining('每月 ').first);
    await tester.pumpAndSettle();
    expect(find.text('每月几号交租'), findsOneWidget);
    expect(
      find.byType(DropdownButton<int>),
      findsNothing,
      reason: '不再用 28 项的下拉菜单',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '15'));
    await tester.pumpAndSettle();
    expect(find.text('每月 15 号'), findsOneWidget);
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

  testWidgets('添加房源：不再手选房源状态，新建就是租住中', (tester) async {
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
    expect(tester.takeException(), isNull);

    // 基本信息那步不该再有「房源状态」：状态由退租 / 押金流程流转
    expect(find.text('房源状态'), findsNothing);
    for (final label in ['租住中', '已退租', '纠纷中']) {
      expect(
        find.text(label),
        findsNothing,
        reason: '$label 不该在向导里手选（只有底部两个 tab 没有状态字）',
      );
    }
  });

  testWidgets('编辑房源：改合同资料不会把「已退租」拽回租住中', (tester) async {
    // 宽一点：测试字体是等宽方块字，「入住日期 / 合同到期」那两个按钮
    // 在 390 宽下会被测试字体撑出 1.5px（真机字体不会）
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(
      () => repository.addProperty(
        buildProperty().copyWith(status: PropertyStatus.ended),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyEditPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 三步直达最后一步：字段都是预填的，校验能过
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      await tester.tap(find.text('保存修改'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    });

    expect(
      repository.propertyById('p1')!.status,
      PropertyStatus.ended,
      reason: '编辑合同资料不该顺手把状态改回租住中',
    );
  });

  testWidgets('房源详情：已退租归档里几段卡片宽度一致且占满整行', (tester) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildHistoryProperty());
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyDetailPage(propertyId: 'p2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 卡片宽度以前是「内容撑出来的」：内容短的那几段会缩成一小块，
    // 和内容长的段落对不齐（房东要求 112、维修记录 100 …）
    double cardWidth(Finder anchor) => tester
        .getRect(find.ancestor(of: anchor, matching: find.byType(ZCard)).first)
        .width;
    final widths = <String, double>{
      '入住取证': cardWidth(find.textContaining('入住 0 张')),
      '房东要求': cardWidth(find.textContaining('没有记录过要求')),
      '维修记录': cardWidth(find.textContaining('没有维修记录')),
      '沟通记录': cardWidth(find.textContaining('没有沟通留痕')),
    };
    for (final entry in widths.entries) {
      expect(
        entry.value,
        closeTo(390 - 32, 0.5),
        reason: '${entry.key} 的卡片要占满整行（去掉左右各 16 的内边距）：$widths',
      );
    }
  });

  testWidgets('房源详情：去退租进退租页、去纠纷进标记纠纷页', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
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
          home: const PropertyDetailPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('去退租'), findsOneWidget);
    expect(find.text('去纠纷'), findsOneWidget);

    // 去退租 → 一整页的退租结算
    await tester.tap(find.text('去退租'));
    await tester.pumpAndSettle();
    expect(find.text('退租'), findsWidgets, reason: '退租页的标题');
    expect(find.text('退租前确认'), findsOneWidget);
    expect(find.text('与房东对接'), findsOneWidget);
    expect(find.text('完成退租'), findsOneWidget);

    await tester.tap(find.byType(ZBackButton));
    await tester.pumpAndSettle();

    // 去纠纷 → 一页「标记纠纷」：写原因、填被扣金额、看证据现状
    await tester.tap(find.text('去纠纷'));
    await tester.pumpAndSettle();
    expect(find.text('标记纠纷'), findsOneWidget);
    expect(find.text('为什么纠纷'), findsOneWidget);
    expect(find.text('被扣了多少'), findsOneWidget);
    expect(find.text('手里的证据'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText?.contains('墙面划痕') == true,
      ),
      '以墙面划痕为由扣了 2000，没给照片',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '房东扣掉的金额',
      ),
      '2000',
    );
    await tester.pumpAndSettle();

    // 落盘是真实 IO：在 runAsync 里点确认并等它写完
    await tester.runAsync(() async {
      await tester.tap(find.text('确认标记纠纷'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final disputed = repository.propertyById('p1')!;
    expect(disputed.status, PropertyStatus.dispute);
    expect(disputed.deposit.status, DepositStatus.inDispute);
    expect(disputed.deposit.disputeNote, '以墙面划痕为由扣了 2000，没给照片');
    expect(disputed.deposit.deductedAmount, 2000, reason: '被扣金额要落库');
    expect(
      disputed.deposit.logs.last.note,
      contains('标记纠纷'),
      reason: '状态变更要留痕',
    );
  });

  testWidgets('房源详情：已经是纠纷中，就不再给「去纠纷」入口', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.dispute,
          deposit: base.deposit.copyWith(
            status: DepositStatus.inDispute,
            disputeNote: '扣了 2000 没给照片',
          ),
        ),
      );
      await repository.setActive('p1');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyDetailPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('去纠纷'), findsNothing, reason: '已经在维权流程里了，再点一次只是把状态重写一遍');
    expect(find.text('去退租'), findsOneWidget, reason: '退租那条还在');
  });

  testWidgets('退租：结算押金 + 记录和房东的对接，房源转入已退租', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 退租前确认：两件事都还没做，页面要说清楚
    expect(find.text('退租取证'), findsOneWidget);
    expect(find.text('最后一次抄表'), findsOneWidget);
    expect(find.text('还没'), findsWidgets);
    expect(find.text('合同押金'), findsOneWidget);

    // 部分扣除：填金额 + 理由，实际该退多少当场算出来
    await tester.tap(find.text('部分扣除'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '被扣除',
      ),
      '2000',
    );
    await tester.pumpAndSettle();
    expect(find.text('¥6,000'), findsOneWidget, reason: '8000 − 2000');
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '扣除理由',
      ),
      '墙面划痕',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '交接备注',
      ),
      '钥匙已还，水电已结清',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成退租'));
    await tester.pumpAndSettle();
    // 两件没做的事要在确认框里点出来（退完就只读了，再也补不了）
    expect(find.textContaining('有 2 项还没做'), findsOneWidget);
    expect(find.textContaining('退租取证'), findsWidgets);
    expect(find.textContaining('最后一次抄表'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.text('仍要退租'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final ended = repository.propertyById('p1')!;
    expect(ended.status, PropertyStatus.ended, reason: '完成退租要把房源转成已退租');
    expect(ended.deposit.status, DepositStatus.partiallyDeducted);
    expect(ended.deposit.deductedAmount, 2000);
    expect(ended.deposit.deductReason, '墙面划痕');
    expect(ended.deposit.returnedAmount, 6000, reason: '实退 = 押金 − 扣除');
    expect(ended.deposit.handoverDone, isTrue);
    expect(ended.deposit.handoverNote, '钥匙已还，水电已结清');
    expect(ended.deposit.logs.last.note, contains('完成退租'));
  });

  testWidgets('退租：押金还没到手也能完成退租，押金照实记成「未退还」', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认就停在「待退还」：页面要说清「没到手也能完成」
    expect(find.textContaining('还没到手也能先完成退租'), findsWidgets);

    await tester.tap(find.text('完成退租'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('仍要退租'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final ended = repository.propertyById('p1')!;
    expect(ended.status, PropertyStatus.ended, reason: '押金没退到也不影响退租');
    expect(ended.deposit.status, DepositStatus.toBeReturned);
    expect(ended.deposit.returnedAmount, 0);
    expect(ended.deposit.returnedDate, isNull, reason: '没退到手就不该写退还日期');
    expect(ended.deposit.logs.last.note, contains('未退还'));
  });

  testWidgets('已退租详情页：押金未退能记「已退到手」，退过之后不再给改', (tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildHistoryProperty();
      await repository.addProperty(
        base.copyWith(
          deposit: base.deposit.copyWith(
            status: DepositStatus.toBeReturned,
            returnedAmount: 0,
            returnedDate: null,
          ),
        ),
      );
    });

    Future<void> pumpDetail() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: const PropertyDetailPage(propertyId: 'p2'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpDetail();
    expect(find.text('押金未退'), findsOneWidget);
    expect(find.text('押金已退到手'), findsOneWidget);

    // 点一下要先确认（免得手滑把没到账的记成到账）
    await tester.tap(find.text('押金已退到手'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已经收到？'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('已收到'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final deposit = repository.propertyById('p2')!.deposit;
    expect(deposit.status, DepositStatus.returned);
    expect(deposit.returnedAmount, 6000);
    expect(deposit.returnedDate, isNotNull);
    expect(deposit.logs.last.note, contains('已退还'));

    // 退过之后：胶囊、按钮都没了，回顾卡改成「已全额退还」。
    // 注意：写盘是在 runAsync 里做的，notifyListeners 带的这次重建在测试里
    // 不会自己落地，所以先把页面卸了再进一次（真机上不需要这一步）。
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpDetail();
    expect(find.text('押金未退'), findsNothing);
    expect(find.text('押金已退到手'), findsNothing, reason: '已退还就不能在这一页改了');
    expect(find.textContaining('押金 ¥6,000 已全额退还'), findsOneWidget);
  });

  testWidgets('历史租住 / 租住回顾：押金没退到手就照实写「未退还」', (tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildHistoryProperty();
      await repository.addProperty(
        base.copyWith(
          // 已经退租，但押金还在房东手里
          deposit: base.deposit.copyWith(
            status: DepositStatus.toBeReturned,
            returnedAmount: 0,
            returnedDate: null,
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(theme: ZTheme.light(), home: const HistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('押金 ¥6,000 未退还'),
      findsOneWidget,
      reason: '列表里照实显示未退还，别写成已退还',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyDetailPage(propertyId: 'p2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('押金 ¥6,000 未退还（还在房东手里）'),
      findsOneWidget,
      reason: '租住回顾里也要说清押金没到手',
    );
    expect(find.text('押金未退'), findsOneWidget, reason: '押金没退就在回顾卡上挂颗胶囊，一眼看得到');
  });

  testWidgets('退租：部分扣除没填金额/理由时拦住，不动房源', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('部分扣除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成退租'));
    await tester.pumpAndSettle();

    expect(
      repository.propertyById('p1')!.status,
      PropertyStatus.active,
      reason: '缺金额就拦住，别把房源标成已退租',
    );
  });

  testWidgets('房源详情：封面读不到就退回内置底图，不写「文件缺失」', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 引用指向一个不存在的文件：换机只导入了 JSON 就是这样
      await repository.addProperty(
        buildProperty().copyWith(coverRef: 'media:p1/gone.jpg'),
      );
      await repository.setActive('p1');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyDetailPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('文件缺失'), findsNothing, reason: '头图位置不该写文件缺失');
    expect(
      find.byType(ZDefaultCover),
      findsOneWidget,
      reason: '退回内置底图，跟租住页的封面同一张',
    );

    // 有真封面时还是用真封面：只有显示不出来才退底图
    await tester.runAsync(() async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 4, height: 4)),
      );
      final ref = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'cover.jpg',
      );
      await repository.updateProperty(
        repository.propertyById('p1')!.copyWith(coverRef: ref),
      );
      // 照片是走真实 IO 读的：得在 runAsync 里等它读完再断言
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    expect(find.byType(ZDefaultCover), findsNothing, reason: '有封面就用封面');
  });

  testWidgets('已退租详情页：顶上给一段租住回顾，租住中不给', (tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.addProperty(buildHistoryProperty());
      for (final rent in repository.rentsOf('p2')) {
        await repository.markRentPaid(rent);
      }
      await repository.saveUtility(
        UtilityRecord(
          id: 'u1',
          propertyId: 'p2',
          month: '2026-03',
          electricity: const UtilityReading(reading: 1200, unitPrice: 0.55),
          recordedAt: DateTime(2026, 3, 1),
        ),
      );
      for (final (id, phase) in [
        ('a1', PhotoPhase.moveIn),
        ('b1', PhotoPhase.moveOut),
      ]) {
        await repository.addPhoto(
          EvidencePhoto(
            id: id,
            propertyId: 'p2',
            room: '客厅',
            imageRef: 'media:p2/$id.jpg',
            thumbRef: 'media:p2/$id.jpg',
            timestamp: DateTime(2025, 9, 1),
            phase: phase,
          ),
        );
      }
    });

    Future<void> pumpDetail(String id) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: PropertyDetailPage(propertyId: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 已退租：回顾卡在顶上，天数/日期/月租/期数/押金都摆出来
    await pumpDetail('p2');
    expect(tester.takeException(), isNull);
    expect(find.text('租住回顾'), findsOneWidget);
    expect(
      find.text('和「以前住的房子」一起住了 395 天'),
      findsOneWidget,
      reason: '2025-09-01 入住、2026-09-30 退租，含首尾 395 天',
    );
    expect(find.text('2025-09-01 入住 · 2026-09-30 退租'), findsOneWidget);
    expect(find.text('月租'), findsWidgets, reason: '回顾卡和合同信息里各有一处');
    expect(find.text('¥2,600'), findsWidgets);
    expect(find.text('12 个月'), findsOneWidget, reason: '合同租期按期数算');
    expect(find.text('12 期'), findsOneWidget, reason: '实付期数');
    expect(find.text('押金 ¥6,000 已全额退还（2026-09-30）'), findsOneWidget);
    expect(find.textContaining('入住 1 · 退租 1'), findsOneWidget);
    expect(
      find.text('已入住 395 天'),
      findsOneWidget,
      reason: '头图那颗胶囊也要按退租日算，别跟着今天一直涨',
    );

    // 归档视图：那六块不再给入口，内容摊成只读的几段
    expect(find.text('存证健康度'), findsNothing, reason: '退租后不必再打分');
    expect(find.text('维权材料'), findsNothing);
    expect(find.text('13 个字段'), findsNothing, reason: '模块网格收掉了');
    for (final section in ['合同信息', '入住取证', '房东要求', '维修记录', '沟通记录']) {
      expect(find.text(section), findsOneWidget, reason: '$section 要以只读段落出现');
    }
    expect(find.text('李房东'), findsOneWidget, reason: '合同要点里有房东');

    // 还在租的房子：没有回顾，但网格与健康度都在
    await pumpDetail('p1');
    expect(find.text('租住回顾'), findsNothing);
    expect(find.text('存证健康度'), findsOneWidget);
    expect(find.text('13 个字段'), findsOneWidget);
  });

  testWidgets('历史租住：不摆「共 N 套」与新增按钮，封面固定用内置图', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      // 历史房源的封面指向一个不存在的文件：换机只导了 JSON 就是这样
      await repository.addProperty(
        buildHistoryProperty().copyWith(coverRef: 'media:p2/gone.jpg'),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(theme: ZTheme.light(), home: const HistoryPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('历史租住'), findsOneWidget);
    expect(find.text('共 1 套'), findsNothing, reason: '不摆套数');
    expect(
      find.byIcon(Icons.add_rounded),
      findsNothing,
      reason: '历史页不该有新增入口（加房源在租住页）',
    );
    expect(
      find.byType(ZHistoryCover),
      findsOneWidget,
      reason: '历史列表的封面固定用内置那张黄昏图',
    );
    expect(find.text('文件缺失'), findsNothing);

    // 就算这套房存着一张能用的封面，历史列表也不跟它走
    await tester.runAsync(() async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 4, height: 4)),
      );
      final ref = await repository.saveMedia(
        bytes,
        folder: 'p2',
        name: 'cover.jpg',
      );
      await repository.updateProperty(
        repository.propertyById('p2')!.copyWith(coverRef: ref),
      );
    });
    await tester.pumpAndSettle();
    expect(
      find.byType(ZHistoryCover),
      findsOneWidget,
      reason: '固定封面，不因为有照片就换掉',
    );
  });

  testWidgets('房源详情：已退租只读、纠纷中只留维权与退租', (tester) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      await repository.addProperty(buildHistoryProperty());
      final base = buildProperty();
      await repository.addProperty(
        Property(
          id: 'p3',
          name: '正在维权的房子',
          address: '北京市海淀区',
          landlord: base.landlord,
          contract: base.contract,
          status: PropertyStatus.dispute,
          deposit: base.deposit.copyWith(
            status: DepositStatus.inDispute,
            disputeNote: '扣了 2000 没给照片',
          ),
          createdAt: base.createdAt,
          updatedAt: base.updatedAt,
        ),
      );
    });

    Future<void> pumpDetail(String id) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(
            theme: ZTheme.light(),
            home: PropertyDetailPage(propertyId: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 已退租：只剩查看
    await pumpDetail('p2');
    expect(tester.takeException(), isNull);
    expect(
      find.byIcon(Icons.settings_outlined),
      findsNothing,
      reason: '不给编辑房源的入口',
    );
    expect(find.text('补充取证'), findsNothing);
    expect(find.text('开始退租对比'), findsNothing);
    expect(find.text('去退租'), findsNothing, reason: '退过租了就没有这一段');

    // 纠纷中：只留维权与退租
    await pumpDetail('p3');
    expect(find.text('押金纠纷 · 维权中'), findsOneWidget, reason: '顶上要有状态卡');
    expect(
      find.textContaining('扣了 2000 没给照片'),
      findsWidgets,
      reason: '纠纷原因摆出来',
    );
    expect(find.text('维权要做的事'), findsOneWidget);
    expect(find.text('去维权'), findsOneWidget);
    expect(find.text('退租'), findsOneWidget);
    expect(find.text('补充取证'), findsNothing);
    expect(find.text('去纠纷'), findsNothing);
    // 合同里的特殊条款也是房东要求：详情页那两处计数要把它算进去
    expect(
      find.text('1 条约定'),
      findsOneWidget,
      reason: 'p3 的合同里写着特殊条款，就算没手记过约定也是 1 条',
    );
    expect(find.textContaining('1 条约定 · 退租时的重要依据'), findsOneWidget);
  });

  testWidgets('占位图 / 历史封面按明暗挑图（深色不用浅色那张）', (tester) async {
    addTearDown(() => Z.applyBrightness(Brightness.light));

    Future<void> pump(Brightness brightness) async {
      Z.applyBrightness(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: ZTheme.light(),
          darkTheme: ZTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          // 故意不用 const：让这两块跟着主题重建
          home: const Scaffold(
            body: Column(children: [ZMissingPhoto(), ZHistoryCover()]),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String assetOf(Type type) {
      final image = tester.widget<Image>(
        find.descendant(of: find.byType(type), matching: find.byType(Image)),
      );
      return (image.image as AssetImage).assetName;
    }

    await pump(Brightness.light);
    expect(
      Theme.of(tester.element(find.byType(ZMissingPhoto))).brightness,
      Brightness.light,
    );
    expect(assetOf(ZMissingPhoto), ZMissingPhoto.asset);
    expect(assetOf(ZHistoryCover), ZHistoryCover.asset);

    await pump(Brightness.dark);
    expect(
      Theme.of(tester.element(find.byType(ZMissingPhoto))).brightness,
      Brightness.dark,
    );
    expect(
      assetOf(ZMissingPhoto),
      ZMissingPhoto.darkAsset,
      reason: '深色下要用暗色那张占位图',
    );
    expect(
      assetOf(ZHistoryCover),
      ZHistoryCover.darkAsset,
      reason: '深色下要用暗色的历史封面',
    );
  });

  testWidgets('房源详情：删除房源要二次确认，删掉连照片一起走', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
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
          imageRef: 'media:p1/ph1.jpg',
          thumbRef: 'media:p1/ph1.thumb.jpg',
          timestamp: DateTime(2026, 10, 15),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyDetailPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('删除这套房源'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除「翠屏里 3 栋 502」'), findsOneWidget);
    expect(find.textContaining('1 张照片'), findsOneWidget, reason: '要说清会删掉什么');
    expect(find.textContaining('先导出对比报告'), findsOneWidget);

    // 点「再想想」什么都不动
    await tester.tap(find.text('再想想'));
    await tester.pumpAndSettle();
    expect(repository.propertyById('p1'), isNotNull);

    // 真的删：房源与照片一起没了
    await tester.runAsync(() async {
      await tester.tap(find.text('删除这套房源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(repository.propertyById('p1'), isNull);
    expect(repository.photosOf('p1'), isEmpty);
  });

  testWidgets('合同页：续租入口只改到期日与月租', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const ContractPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('续租'));
    await tester.pumpAndSettle();
    expect(find.text('新的到期日'), findsOneWidget);
    expect(find.text('月租（涨租就改这里）'), findsOneWidget);

    // 到期日没往后改：拦住，不动数据
    await tester.tap(find.text('保存续租'));
    await tester.pumpAndSettle();
    expect(
      repository.propertyById('p1')!.contract.contractEnd,
      DateTime(2026, 12, 31),
    );
  });

  testWidgets('续租：改到期日后租金计划跟着补齐', (tester) async {
    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
    });

    // 原合同 2026-03-01 → 2026-12-31：10 期
    expect(repository.rentsOf('p1').length, 10);

    await tester.runAsync(() async {
      final property = repository.propertyById('p1')!;
      await repository.updateProperty(
        property.copyWith(
          contract: property.contract.copyWith(
            contractEnd: DateTime(2027, 3, 31),
            monthlyRent: 3500,
          ),
        ),
      );
    });

    final renewed = repository.propertyById('p1')!;
    expect(renewed.contract.monthlyRent, 3500);
    expect(
      repository.rentsOf('p1').length,
      13,
      reason: '续到 2027-03 就是 13 期，多出来的月份自动补账单',
    );
    final months = repository.rentsOf('p1').map((rent) => rent.month).toList()
      ..sort();
    expect(months.last, monthKey(DateTime(2027, 3, 1)));
  });

  testWidgets('数字键盘：升起时多一条「完成」可以收起', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    // 模拟键盘顶起 320
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          contract: base.contract.copyWith(deposit: 0),
          deposit: base.deposit.copyWith(status: DepositStatus.none),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 键盘升起 → 「完成」在底栏上方
    expect(find.text('完成'), findsOneWidget);

    // 点输入框聚焦，再点「完成」收起
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
      reason: '点「完成」要能收起键盘',
    );
  });

  testWidgets('小屏 + 大字：房源详情与费用页不能溢出', (tester) async {
    // 用 App 启动时那套真实字体（测试默认字体是方块字宽，跟真机不一样）。
    // 字体加载要真实事件循环，所以裹在 runAsync 里（否则这一条会卡住）
    await tester.runAsync(() async {
      for (final entry in <String, String>{
        'Outfit': 'assets/fonts/Outfit-400.ttf',
        'NotoSansSC': 'assets/fonts/NotoSansSC-Regular.ttf',
        'JetBrainsMono': 'assets/fonts/JB-Mono-400.ttf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            Future.value(
              File(entry.value).readAsBytesSync().buffer.asByteData(),
            ),
          );
        await loader.load();
      }
    });
    // 真机上的两个变量：320pt 小屏（iPhone SE 一代）和系统字体放大（App 限到 1.2）
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
    });

    for (final page in <String, Widget>{
      '房源详情': const PropertyDetailPage(propertyId: 'p1'),
      '费用页': const Scaffold(body: ExpensePage()),
    }.entries) {
      await tester.pumpWidget(
        ChangeNotifierProvider<Repository>.value(
          value: repository,
          child: MaterialApp(theme: ZTheme.light(), home: page.value),
        ),
      );
      await tester.pumpAndSettle();
      final error = tester.takeException();
      expect(error, isNull, reason: '${page.key} 在小屏 + 大字下溢出：$error');
    }
  });

  testWidgets('首页：押金金额没填也得说「还没退到手」，不能念结清', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 房子退了、押金状态是「待退还」，但合同里没填押金金额（0）
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.ended,
          contract: base.contract.copyWith(deposit: 0),
          deposit: base.deposit.copyWith(
            status: DepositStatus.toBeReturned,
            returnedAmount: 0,
            returnedDate: null,
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 状态说了算：没退到手就不许念「都结清了」；金额没填也别念「¥0」
    expect(find.text('押金都结清了'), findsNothing);
    expect(find.text('还没退到手的押金'), findsOneWidget);
    expect(find.text('金额未填'), findsOneWidget);
    expect(find.textContaining('1 套还没结清'), findsOneWidget);
  });

  testWidgets('首页：只有一套房在维权时，标题与待办都对', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.dispute,
          deposit: base.deposit.copyWith(
            status: DepositStatus.inDispute,
            deductedAmount: 2000,
            deductReason: '墙面划痕',
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          // 首页本身不带 Scaffold（真实 App 里挂在 AppShell 下），这里补上
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 房子还在维权，不是「已经退租」；维权待办也得在首页上看得到
    expect(find.text('现在的房子已经退租'), findsNothing);
    expect(find.text('有 1 套房还在维权'), findsOneWidget);
    expect(find.text('待办提醒'), findsOneWidget);
    expect(find.text('押金纠纷维权中'), findsOneWidget);
  });

  testWidgets('退租：纠纷中的房子不给「待退还」这一选', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.dispute,
          deposit: base.deposit.copyWith(
            status: DepositStatus.inDispute,
            deductedAmount: 2000,
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 和押金追踪页同一套规则：纠纷中只能落到「部分扣除 / 已退还」
    expect(find.text('待退还'), findsNothing, reason: '纠纷中回头选待退还没意义');
    expect(find.text('部分扣除'), findsOneWidget);
    expect(find.text('已退还'), findsOneWidget);
  });

  testWidgets('去纠纷：押金已退到手的房子不给标纠纷', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          deposit: base.deposit.copyWith(
            status: DepositStatus.returned,
            returnedAmount: 8000,
            returnedDate: DateTime(2026, 10, 1),
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DisputePage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, '房东扣了 2000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认标记纠纷'));
    await tester.pumpAndSettle();

    final saved = repository.propertyById('p1')!;
    expect(
      saved.status,
      PropertyStatus.active,
      reason: '押金已经退到手，押金流程走完了，不能再标纠纷',
    );
    expect(saved.deposit.status, DepositStatus.returned);
  });

  testWidgets('押金追踪：合同押金没填时不给做「部分扣除」', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(contract: base.contract.copyWith(deposit: 0)),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 合同里没填押金金额：谈不上「扣了多少」，这个目标直接不显示
    expect(
      find.widgetWithText(ChoiceChip, '部分扣除'),
      findsNothing,
      reason: '不能操作的状态不再摆出来',
    );
    expect(find.widgetWithText(ChoiceChip, '待退还'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '已退还'), findsOneWidget);
  });

  testWidgets('退租：确认框点「回去补」就不动房源', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成退租'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有 2 项还没做'), findsOneWidget);
    expect(find.text('回去补'), findsOneWidget);
    await tester.tap(find.text('回去补'));
    await tester.pumpAndSettle();

    expect(
      repository.propertyById('p1')!.status,
      PropertyStatus.active,
      reason: '没确认就不该退租',
    );
    expect(find.text('仍要退租'), findsNothing);
  });

  testWidgets('退租：该做的都做了就是普通确认', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      // 退租照片 + 本月抄表都做过了
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph1',
          propertyId: 'p1',
          room: '客厅',
          phase: PhotoPhase.moveOut,
          imageRef: 'media:p1/ph1.jpg',
          thumbRef: 'media:p1/ph1.thumb.jpg',
          timestamp: DateTime(2026, 10, 15),
        ),
      );
      await repository.saveUtility(
        UtilityRecord(
          id: 'u1',
          propertyId: 'p1',
          month: monthKey(DateTime.now()),
          electricity: const UtilityReading(
            reading: 26000,
            previousReading: 25814,
            unitPrice: 0.55,
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
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成退租'));
    await tester.pumpAndSettle();
    expect(find.text('确认退租'), findsOneWidget);
    expect(find.text('再看看'), findsOneWidget);
    expect(find.textContaining('还没做'), findsNothing);
    await tester.tap(find.text('再看看'));
    await tester.pumpAndSettle();
    expect(repository.propertyById('p1')!.status, PropertyStatus.active);
  });

  testWidgets('押金追踪：已退租后不给「改回租住中」的回头路', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildHistoryProperty();
      await repository.addProperty(
        base.copyWith(
          deposit: base.deposit.copyWith(status: DepositStatus.toBeReturned),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 不能点的状态直接不显示：只剩「部分扣除 / 已退还」两个目标
    expect(
      find.widgetWithText(ChoiceChip, '已缴纳'),
      findsNothing,
      reason: '押金状态只许往前走：待退还之后不能再改回已缴纳',
    );
    expect(
      find.widgetWithText(ChoiceChip, '无押金'),
      findsNothing,
      reason: '「要不要押金」不在状态选择里（那是页顶那一问的事）',
    );
    expect(
      find.widgetWithText(ChoiceChip, '已退还'),
      findsOneWidget,
      reason: '押金继续往后走（退到手）还要能记账',
    );
    expect(
      find.widgetWithText(ChoiceChip, '部分扣除'),
      findsOneWidget,
      reason: '待退还 → 部分扣除 是往前走，允许',
    );
    expect(find.textContaining('只能继续往后走'), findsOneWidget);

    // 点「已退还」只是选中：确认行把后果写出来，再点「确认更新」才落库
    await tester.tap(find.widgetWithText(ChoiceChip, '已退还'));
    await tester.pumpAndSettle();
    expect(find.textContaining('押金流程走完'), findsOneWidget);
    expect(
      repository.propertyById('p2')!.deposit.status,
      DepositStatus.toBeReturned,
      reason: '只是选中，还没落库',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('确认更新'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(
      repository.propertyById('p2')!.deposit.status,
      DepositStatus.returned,
    );
    expect(
      repository.propertyById('p2')!.status,
      PropertyStatus.ended,
      reason: '押金继续流转，房源还是已退租',
    );
    // 已退还 = 押金流程到头了：一个可选目标都不剩，整段选择不显示
    expect(find.byType(ChoiceChip), findsNothing, reason: '押金已经退到手，没有能操作的状态了');
    expect(find.textContaining('押金流程走完了'), findsOneWidget);
  });

  testWidgets('押金追踪：纠纷中不能改回「已缴纳」，只能往「部分扣除 / 已退还」走', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.dispute,
          deposit: base.deposit.copyWith(
            status: DepositStatus.inDispute,
            deductedAmount: 3000,
            deductReason: '墙面有污渍',
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 只能选「部分扣除 / 已退还」：其余目标直接不显示
    expect(
      find.widgetWithText(ChoiceChip, '已缴纳'),
      findsNothing,
      reason: '押金状态只许往前走：纠纷中也不能改回「已缴纳」',
    );
    expect(
      find.widgetWithText(ChoiceChip, '无押金'),
      findsNothing,
      reason: '纠纷中的房子也不摆「无押金」——那是页顶那一问的事',
    );
    expect(
      find.widgetWithText(ChoiceChip, '待退还'),
      findsNothing,
      reason: '纠纷中回头选「待退还」没意义',
    );
    expect(
      find.widgetWithText(ChoiceChip, '部分扣除'),
      findsOneWidget,
      reason: '维权谈成的结果就是这两条：部分扣除 / 已退还',
    );
    expect(find.widgetWithText(ChoiceChip, '已退还'), findsOneWidget);
    expect(
      find.textContaining('只能继续往后走'),
      findsOneWidget,
      reason: '页面要写清为什么改不了',
    );

    // 先选中、再确认（两段式，避免误触直接落库）
    await tester.tap(find.widgetWithText(ChoiceChip, '已退还'));
    await tester.pumpAndSettle();
    expect(
      repository.propertyById('p1')!.deposit.status,
      DepositStatus.inDispute,
      reason: '只是选中，还没落库',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('确认更新'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    final saved = repository.propertyById('p1')!;
    expect(saved.deposit.status, DepositStatus.returned);
    expect(
      saved.status,
      PropertyStatus.dispute,
      reason: '押金只是一笔钱的状态：押金退到手也不会把纠纷拽回租住中',
    );
  });

  testWidgets('退租：押金已经在押金追踪里记过，就不再问一遍', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          deposit: base.deposit.copyWith(
            status: DepositStatus.partiallyDeducted,
            deductedAmount: 3000,
            deductReason: '墙面有污渍',
            returnedAmount: 5000,
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 押金部分扣除已经记过了：这里只回显，不再摆「房东退了吗」和金额输入
    expect(find.text('房东退了吗'), findsNothing, reason: '两处都能改会互相覆盖，用户也得多填一次');
    expect(find.text('押金退还 ¥5,000 · 扣除 ¥3,000'), findsOneWidget);
    expect(find.text('扣除理由：墙面有污渍'), findsOneWidget);
    expect(find.text('去押金追踪'), findsOneWidget);

    // 还没记过的房子照旧在退租这一页结算押金
    final other = await openTestRepository(tester);
    await tester.runAsync(() async {
      await other.addProperty(buildProperty());
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: other,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const MoveOutPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('房东退了吗'), findsOneWidget);
  });

  testWidgets('押金追踪：改押金状态不会把租住中的房子变成已退租', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 只在押金页把状态改成「待退还」：先选中，再确认
    await tester.tap(find.widgetWithText(ChoiceChip, '待退还'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('确认更新'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final saved = repository.propertyById('p1')!;
    expect(saved.deposit.status, DepositStatus.toBeReturned);
    expect(
      saved.status,
      PropertyStatus.active,
      reason: '押金只是一笔钱的状态：没走退租，房源就该还是「租住中」',
    );
  });

  testWidgets('押金追踪：没填押金金额的提示不能贴在卡片上', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 合同里没填押金金额（= 0）：页面要额外给一条「去哪儿补」的提示
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(contract: base.contract.copyWith(deposit: 0)),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 顶部卡片里的那行说明在这条提示的正上方，用它量出间距
    final hint = tester.getRect(find.textContaining('还没填押金金额'));
    final above = tester.getRect(find.text(DepositStatus.paid.hint));
    expect(
      hint.top - above.bottom,
      greaterThanOrEqualTo(34),
      reason: '提示条要和上面的押金卡片留出间距，不能顶在一起',
    );
  });

  testWidgets('押金追踪：无押金的房源能在这儿改成需要押金', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          contract: base.contract.copyWith(deposit: 0),
          deposit: base.deposit.copyWith(status: DepositStatus.none),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 无押金：页面只留「要不要押金」这一问 + 金额输入
    expect(
      find.textContaining('还没填押金金额'),
      findsNothing,
      reason: '本来就不需要押金，别催人去补金额',
    );
    expect(find.text('当前房源暂不需要押金'), findsOneWidget);
    expect(find.text('改成需要押金'), findsOneWidget);
    expect(find.text('更新押金状态'), findsNothing, reason: '还没有押金，别摆状态选择');
    expect(find.text('金额明细'), findsNothing, reason: '还没有押金，没有明细可看');
    expect(find.text('编辑金额'), findsNothing, reason: '编辑金额按钮已经去掉了');

    // 填金额 → 改成需要押金，那两段才出现
    await tester.enterText(find.byType(TextField).first, '6000');
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('改成需要押金'));
      // 保存要走一次真实的落盘，notifyListeners 在写完才触发 —— 给它足够时间
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    final saved = repository.propertyById('p1')!;
    expect(saved.contract.deposit, 6000, reason: '金额要写进合同');
    expect(
      saved.deposit.status,
      DepositStatus.paid,
      reason: '填了金额就说明这套房要押金，状态跟着记成「已缴纳」',
    );
    expect(saved.deposit.logs.last.note, contains('登记押金金额'));
    expect(find.text('¥6,000'), findsWidgets, reason: '卡片与金额明细都要跟着更新');
    expect(find.text('已缴纳'), findsWidgets);
    expect(find.text('更新押金状态'), findsOneWidget, reason: '改成需要押金之后，状态选择才出现');
    expect(find.text('金额明细'), findsOneWidget);
    expect(
      find.text('生成对比报告'),
      findsNothing,
      reason: '这页不再摆生成对比报告，入口在房源详情的维权材料里',
    );
  });

  testWidgets('追加标注：四个工具、能取消、小屏不溢出', (tester) async {
    // 小屏 + 竖图：以前照片 + 标题 + 一排工具会把弹层顶出屏幕
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      // 落一张真图：照片加载中有无限动画，没有字节时 pumpAndSettle 会超时
      final bytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 64, height: 96)),
      );
      final imageRef = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'ph1.jpg',
      );
      final thumbRef = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'ph1.thumb.jpg',
      );
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph1',
          propertyId: 'p1',
          room: '客厅',
          imageRef: imageRef,
          thumbRef: thumbRef,
          timestamp: DateTime(2026, 10, 15),
          width: 1024,
          height: 1536,
          watermarked: true,
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PhotoDetailPage(photoId: 'ph1'),
        ),
      ),
    );
    // 照片是异步读的：加载中有无限动画，等它读完再往下走
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    // 小屏上按钮在列表下方，ListView 懒构建，得先滚到它
    await tester.dragUntilVisible(
      find.text('追加标注'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.tap(find.text('追加标注'));
    // 图片解码在测试里不会真正结束，别用 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: '弹层不能溢出屏幕');

    for (final label in ['圆圈', '箭头', '画笔', '文字']) {
      expect(find.text(label), findsOneWidget, reason: '四种工具都在');
    }
    expect(find.text('取消'), findsOneWidget);

    // 取消：照片上的标注保持原样（什么都不保存）
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.photosOf('p1').first.annotations, isEmpty);
  });

  testWidgets('追加标注：文字工具点照片能放一段文字', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      final bytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 64, height: 48)),
      );
      final imageRef = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'ph1.jpg',
      );
      final thumbRef = await repository.saveMedia(
        bytes,
        folder: 'p1',
        name: 'ph1.thumb.jpg',
      );
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph1',
          propertyId: 'p1',
          room: '客厅',
          imageRef: imageRef,
          thumbRef: thumbRef,
          timestamp: DateTime(2026, 10, 15),
          width: 1024,
          height: 768,
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PhotoDetailPage(photoId: 'ph1'),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.dragUntilVisible(
      find.text('追加标注'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();
    await tester.tap(find.text('追加标注'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 选「文字」，点一下照片 → 弹输入框
    await tester.tap(find.text('文字'));
    await tester.pump();
    final canvas = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onPanStart != null,
    );
    await tester.tap(canvas);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('添加文字标注'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '墙面裂缝 12cm');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 保存后这条文字标注落到照片上
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    final saved = repository.photosOf('p1').first.annotations;
    expect(saved, hasLength(1));
    expect(saved.first.type, 'text');
    expect(saved.first.text, '墙面裂缝 12cm');
    expect(
      saved.first.colorValue,
      Z.cameraAnnotate.toARGB32(),
      reason: '追加标注统一用红色笔',
    );
  });

  testWidgets('房源详情：头图只听封面，没设封面用默认图', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 没有 coverRef，但有入住取证照片
      await repository.addProperty(buildProperty());
      await repository.addPhoto(
        EvidencePhoto(
          id: 'ph1',
          propertyId: 'p1',
          room: '客厅',
          imageRef: 'media:p1/ph1.jpg',
          thumbRef: 'media:p1/ph1.thumb.jpg',
          timestamp: DateTime(2026, 10, 15),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyDetailPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 没设封面：即使有取证照片，头图也保持默认图
    expect(
      tester.widget<ZPhoto>(find.byType(ZPhoto).first).ref,
      isNull,
      reason: '没设封面时头图不拿取证照片兜底',
    );
    expect(
      tester.widget<ZPhoto>(find.byType(ZPhoto).first).fallback,
      isA<ZDefaultCover>(),
      reason: '没设封面时用内置默认图',
    );

    // 设了封面就听封面的
    await tester.runAsync(() async {
      final property = repository.propertyById('p1')!;
      await repository.updateProperty(
        property.copyWith(coverRef: 'media:p1/picked.jpg'),
      );
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<ZPhoto>(find.byType(ZPhoto).first).ref,
      'media:p1/picked.jpg',
    );
  });

  testWidgets('押金追踪：改成「已退还」后扣款金额与理由要清掉', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 先记成「部分扣除」：扣了 3000
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          deposit: base.deposit.copyWith(
            status: DepositStatus.partiallyDeducted,
            deductedAmount: 3000,
            deductReason: '墙面有污渍',
            returnedAmount: 5000,
            disputeNote: '入住照片里墙面是干净的',
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 部分扣除时明细里能看到被扣 3000
    expect(find.textContaining('¥3,000'), findsWidgets);
    expect(find.text('维权备注'), findsOneWidget, reason: '维权期间明细里会显示');

    // 房东后来把扣的钱也退了 → 改成「已退还」（选中 + 确认）
    await tester.tap(find.widgetWithText(ChoiceChip, '已退还'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('确认更新'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final saved = repository.propertyById('p1')!.deposit;
    expect(saved.status, DepositStatus.returned);
    expect(saved.returnedAmount, 8000, reason: '全额退到手');
    expect(saved.deductedAmount, 0, reason: '已退还就没有被扣除的金额了');
    expect(saved.deductReason, isEmpty);
    expect(saved.disputeNote, isEmpty, reason: '已退还后维权备注也从明细里清掉');
    // 明细里不再出现扣款金额，过程仍留在状态变更记录里
    expect(find.textContaining('¥3,000'), findsNothing);
    expect(find.textContaining('墙面有污渍'), findsNothing);
    expect(find.text('维权备注'), findsNothing, reason: '金额明细里不再有这一行');
    expect(
      find.textContaining('原维权备注：入住照片里墙面是干净的'),
      findsOneWidget,
      reason: '原内容写进状态变更记录，信息不丢',
    );
    expect(find.text('手动更新状态'), findsNothing, reason: '状态变更记录里不写这句泛化文案');
  });

  testWidgets('押金追踪：选部分扣除要填扣款信息，保存后页面立刻更新', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 押金 8000、状态「已缴纳」：退租时房东扣了一部分
      await repository.addProperty(buildProperty());
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const DepositPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 点「部分扣除」只是选中，确认后才弹填写层：
    // 扣了多少、为什么扣、维权备注
    await tester.tap(find.widgetWithText(ChoiceChip, '部分扣除'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('会先让你填「扣了多少'),
      findsOneWidget,
      reason: '选中后先说清接下来要填什么',
    );
    await tester.tap(find.text('确认更新'));
    await tester.pumpAndSettle();
    expect(find.text('押金部分扣除'), findsOneWidget);
    expect(find.text('扣除多少钱'), findsOneWidget);
    expect(find.text('扣除理由'), findsOneWidget);
    expect(find.text('维权备注'), findsWidgets, reason: '弹层里有这个输入框（页面金额明细里也有同名行）');
    expect(find.byType(TextFormField), findsNWidgets(3), reason: '弹层里就这三个输入框');

    await tester.enterText(find.byType(TextFormField).at(0), '2000');
    await tester.enterText(find.byType(TextFormField).at(1), '墙面有污渍');
    await tester.enterText(find.byType(TextFormField).at(2), '入住照片里墙面是干净的');
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存'));
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    final saved = repository.propertyById('p1')!;
    expect(saved.deposit.status, DepositStatus.partiallyDeducted);
    expect(saved.deposit.deductedAmount, 2000);
    expect(saved.deposit.deductReason, '墙面有污渍');
    expect(saved.deposit.disputeNote, '入住照片里墙面是干净的');
    expect(
      saved.deposit.returnedAmount,
      6000,
      reason: '剩下的 8000 - 2000 算「已退还」，金额明细才对得上',
    );

    // 保存后页面立刻更新（以前会停在旧数据上）
    expect(find.text('部分扣除'), findsWidgets, reason: '状态 pill 跟着变');
    expect(find.text('¥2,000'), findsWidgets, reason: '被扣除');
    expect(find.text('墙面有污渍'), findsWidgets);
    expect(find.text('入住照片里墙面是干净的'), findsWidgets);

    // 部分扣除之后：只能往「已退还」走，待退还 / 已缴纳直接不显示
    expect(
      find.widgetWithText(ChoiceChip, '已缴纳'),
      findsNothing,
      reason: '不能点的状态不再摆出来',
    );
    expect(find.widgetWithText(ChoiceChip, '待退还'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '已退还'), findsOneWidget);
  });

  testWidgets('首页与租住：房子都退租时摆押金摘要，点一下切到费用页', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 唯一一套房已经退租，押金还在房东手里
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.ended,
          deposit: base.deposit.copyWith(
            status: DepositStatus.toBeReturned,
            returnedAmount: 0,
            returnedDate: null,
          ),
        ),
      );
    });
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

    // 首页：不再是干巴巴的空状态，押金摘要排在最上面
    expect(find.text('现在的房子已经退租'), findsOneWidget);
    expect(find.text('还没退到手的押金'), findsOneWidget);
    expect(find.text('¥8,000'), findsWidgets, reason: '唯一一套没退的押金');
    expect(find.text('新增一套租住'), findsOneWidget);

    // 点押金摘要 → 切到费用页（那里按套列着押金情况）
    await tester.tap(find.text('还没退到手的押金'));
    await tester.pumpAndSettle();
    expect(find.text('押金情况'), findsOneWidget);
    expect(find.text('翠屏里 3 栋 502'), findsOneWidget, reason: '费用页按套列');

    // 租住页：同一张摘要卡；页面里不再重复两个「新增」按钮
    await tester.tap(find.byIcon(Icons.home_work_outlined));
    await tester.pumpAndSettle();
    expect(find.text('没有在租的房子'), findsOneWidget, reason: '切换器的标题');
    expect(find.text('还没退到手的押金'), findsOneWidget);
    expect(find.text('添加新的租住'), findsNothing, reason: '别重复摆两个新增入口');
    expect(find.text('新增一套租住'), findsOneWidget);
  });

  testWidgets('费用：不需要押金的房源不催着补金额', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          contract: base.contract.copyWith(deposit: 0),
          deposit: base.deposit.copyWith(status: DepositStatus.none),
        ),
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

    // 押金那块照实写「不需要押金」，而且没有那句催他补金额的副标题
    expect(find.text('不需要押金'), findsWidgets);
    expect(
      find.textContaining('还没填押金金额'),
      findsNothing,
      reason: '本来就不需要押金，别催他补一个不该有的数',
    );
    expect(
      find.text(DepositStatus.none.hint),
      findsNothing,
      reason: '副标题整句都不摆',
    );
  });

  testWidgets('费用：没有在租房源时，摊开全部房源的押金情况', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 两套都退租了：一套押金还在房东手里，一套已经退清
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.ended,
          deposit: base.deposit.copyWith(
            status: DepositStatus.toBeReturned,
            returnedAmount: 0,
            returnedDate: null,
          ),
        ),
      );
      await repository.addProperty(buildHistoryProperty());
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(theme: ZTheme.light(), home: const ExpensePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 没有租金日历了，换成押金总览
    expect(find.text('租金日历'), findsNothing);
    expect(find.text('押金情况'), findsOneWidget);
    expect(find.textContaining('现在没有在租的房子'), findsOneWidget);
    expect(find.text('还没退到手的押金'), findsOneWidget);
    expect(find.text('¥8,000'), findsWidgets, reason: '那套没退的押金合计');

    // 两套都在列表里，各自的口径照实写
    expect(find.text('翠屏里 3 栋 502'), findsOneWidget);
    expect(find.text('以前住的房子'), findsOneWidget);
    expect(find.text('押金 ¥8,000 未退还'), findsOneWidget);
    expect(find.text('押金已退还 ¥6,000'), findsOneWidget);
    expect(find.text('待退还'), findsWidgets, reason: '押金状态 pill');
    expect(find.text('已退还'), findsWidgets);

    // 点进去就是那套房的押金追踪（状态继续往后走、补金额都在那儿）
    await tester.tap(find.text('翠屏里 3 栋 502'));
    await tester.pumpAndSettle();
    expect(find.text('押金追踪'), findsOneWidget);
  });

  testWidgets('费用 / 首页：部分扣除的房子不能算「押金都结清了」', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      // 唯一一套房已经退租，押金 8000 里被扣走 3000（只拿回 5000）
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          status: PropertyStatus.ended,
          deposit: base.deposit.copyWith(
            status: DepositStatus.partiallyDeducted,
            deductedAmount: 3000,
            deductReason: '墙面有污渍',
            returnedAmount: 5000,
          ),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(theme: ZTheme.light(), home: const ExpensePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 被扣的那部分没回到手上，摘要得照实写；不能念「都结清了」
    expect(find.text('还没退到手的押金'), findsOneWidget);
    expect(find.textContaining('被扣 ¥3,000'), findsWidgets);
    expect(find.text('押金都结清了'), findsNothing);
    expect(find.text('押金退还 ¥5,000 · 扣除 ¥3,000'), findsOneWidget);

    // 押金真的都退到手时才是「都结清了」
    final settled = await openTestRepository(tester);
    await tester.runAsync(() async {
      await settled.addProperty(buildHistoryProperty());
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: settled,
        child: MaterialApp(theme: ZTheme.light(), home: const ExpensePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('押金都结清了'), findsOneWidget);
    expect(find.text('还没退到手的押金'), findsNothing);
  });

  testWidgets('费用：一直显示当前是哪套房', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
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
        child: MaterialApp(theme: ZTheme.light(), home: const ExpensePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 只有一套在租：也得看得出这一页的账是哪套房的
    expect(find.text('翠屏里 3 栋 502'), findsWidgets);
    expect(find.text('切换房源'), findsNothing, reason: '只有一套在租，没什么可切的');
  });

  testWidgets('费用：切换房源只列租住中的', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(base);
      await repository.addProperty(
        Property(
          id: 'p3',
          name: '望京西园 4 区',
          address: '北京市朝阳区',
          landlord: base.landlord,
          contract: base.contract,
          createdAt: base.createdAt,
          updatedAt: base.updatedAt,
        ),
      );
      // 已经退租的那套：不该出现在切换里
      await repository.addProperty(buildHistoryProperty());
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

    await tester.tap(find.textContaining('切换房源'));
    await tester.pumpAndSettle();
    expect(find.text('望京西园 4 区'), findsWidgets, reason: '在租的那套要列出来');
    expect(find.text('以前住的房子'), findsNothing, reason: '已退租 / 纠纷中的不进费用页的切换');
  });

  testWidgets('费用：租金日历那行的状态标签贴着右边缘', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
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
        child: MaterialApp(theme: ZTheme.light(), home: const ExpensePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 「N 号交租」那一行：状态标签要贴右边缘（以前被 Flexible 挤进来一截）
    final row = find
        .ancestor(
          of: find.textContaining('号交租'),
          matching: find.byType(Container),
        )
        .first;
    final rowBox = tester.getRect(row);
    final tag = tester.getRect(
      find.descendant(of: row, matching: find.byType(ZTag)),
    );
    expect(
      rowBox.right - tag.right,
      closeTo(11, 1.5),
      reason: '这一行右边只留 11 的内边距，标签不该被往里挤',
    );
  });

  testWidgets('租住页：「历史 N 套」贴着右边缘', (tester) async {
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
        child: MaterialApp(theme: ZTheme.light(), home: const TenancyPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 名字那格曾经把没占满的额度留在 Spacer 右边，把入口挤到离右边缘一截
    final label = tester.getRect(find.text('历史 1 套'));
    final card = tester.getRect(find.byType(ZCard).first);
    expect(
      card.right - label.right,
      lessThan(24),
      reason: '只剩后面那个小箭头的宽度，不能有多余留白',
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
        child: MaterialApp(theme: ZTheme.light(), home: const TenancyPage()),
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
    expect(find.byType(SnackBar), findsNothing, reason: '不该再用页面底部的 SnackBar');
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
    expect(
      tester
          .widget<ZPhoto>(
            find.descendant(
              of: find.byType(PageView),
              matching: find.byType(ZPhoto),
            ),
          )
          .fit,
      BoxFit.contain,
      reason: '单图模式要完整显示照片，不能裁掉边缘',
    );
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
    testWidgets('运行时切深色：${withData ? '有房源' : '空状态'}时首页 / 费用页要当场换色', (
      tester,
    ) async {
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
          tester.widget<Text>(find.text('租盾能帮你做什么')).style?.color,
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
      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined).last);
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
              .widget<Text>(find.text('租盾能帮你做什么', skipOffstage: false))
              .style
              ?.color,
          const Color(0xFF0E1F3D),
          reason: '切回浅色要变回深墨色',
        );
      }
    });
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

  testWidgets('抄表录入：本月读数留空、上月读数带入且可手改，月份锁定不可改', (tester) async {
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
    expect(find.text('不可修改'), findsNothing);

    // 上月读数带入上一月那条记录的值，并且是可以手改的基准：
    // 换了表、或者上一个月忘了抄，都得能自己填一个数进去
    final prevFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.decoration?.labelText == '上月读数')
        .toList();
    expect(prevFields, isNotEmpty);
    for (final field in prevFields) {
      expect(field.readOnly, isFalse, reason: '上月读数要能自己改');
    }
    expect(find.text('1200'), findsWidgets, reason: '上月读数应显示上一月的值');

    // 本月没有记录 → 本月读数留空，不拿上个月的数糊上来
    // （单价输入框会带默认电价 / 水价，所以只看「本月读数」这几个框）
    final readingFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.decoration?.labelText == '本月读数')
        .toList();
    expect(readingFields, isNotEmpty);
    for (final field in readingFields) {
      expect(field.controller?.text, isEmpty, reason: '本月没有记录时，本月读数应该是空的');
    }

    // 手填本月读数：用量与费用跟着算（1300 − 1200 = 100 kWh）
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '本月读数',
          )
          .first,
      '1300',
    );
    await tester.pump();
    expect(find.textContaining('用量 100 kWh'), findsOneWidget);
    // 费用 = 用量 × 单价（新增记录时单价是设置里的默认电价）
    final price = repository.settings.defaultElectricityPrice;
    expect(
      find.text('¥${fmtMoney(100 * price, symbol: false)}'),
      findsOneWidget,
    );

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
    // 补录的那个月之前没有记录：页顶会常驻一条缺基准的提示
    expect(find.text('去填写'), findsOneWidget);

    // 第一个「本月读数」就是电表那个（三个表的顺序是 电 / 水 / 燃气）；
    // 上面还有「上月读数」框，不能再拿 find.byType(TextField).first 当本月读数
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '本月读数',
          )
          .first,
      '1250',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    final records = repository.utilitiesOf('p1');
    expect(records, hasLength(2), reason: '补录是一笔新记录，不该覆盖本月那条');
    final prev = records.firstWhere((r) => r.month == prevMonth);
    final current = records.firstWhere((r) => r.month == thisMonth);
    expect(prev.electricity?.reading, 1250);
    expect(current.electricity?.reading, 1300, reason: '本月的记录必须原样不动');
  });

  testWidgets('抄表录入：之前没抄过时，拿合同里入住时的表底数当基准', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          contract: base.contract.copyWith(
            moveInElectricity: 1200,
            moveInWater: 88,
          ),
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

    // 合同里填了入住表底数，基准是有的：不该弹框催填
    expect(find.textContaining('请录入'), findsNothing);

    // 一条抄表记录都没有：基准直接来自「入住时的表底数」，而不是留空
    expect(find.text('1200'), findsWidgets, reason: '电表该带入住时的读数');
    expect(find.text('88'), findsWidgets, reason: '水表同理');

    // 有了基准，首月用量就算得出来（1290 − 1200 = 90）
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '本月读数',
          )
          .first,
      '1290',
    );
    await tester.pump();
    expect(find.textContaining('用量 90 kWh'), findsOneWidget);
  });

  testWidgets('抄表年份页：最后一行不画底线（5 月入住时最后一行是 5 月）', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          // 2026-05-01 入住：这一年的明细从 12 月列到 5 月
          contract: base.contract.copyWith(moveInDate: DateTime(2026, 5, 1)),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityYearPage(propertyId: 'p1', year: '2026'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    Finder rowOf(String month) => find.ancestor(
      of: find.text(monthLabel(month)),
      matching: find.byType(ZListRow),
    );
    // 最后一行（5 月）下面不该有分隔线
    expect(
      find.descendant(of: rowOf('2026-05'), matching: find.byType(Divider)),
      findsNothing,
      reason: '卡片底部不该多出一条横线',
    );
    // 倒数第二行（6 月）照旧有
    expect(
      find.descendant(of: rowOf('2026-06'), matching: find.byType(Divider)),
      findsOneWidget,
    );
  });

  testWidgets('抄表录入：跨月没抄时，读数旁标出基准来自哪个月', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      // 只有 5 月抄过电表：8 月来抄时，基准是三个多月前的读数，
      // 用量其实是 6/7/8 三个月合起来的
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_may',
          propertyId: 'p1',
          month: '2026-05',
          electricity: const UtilityReading(reading: 1000, unitPrice: 0.55),
          recordedAt: DateTime(2026, 5, 20),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityEditPage(propertyId: 'p1', month: '2026-08'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('1000'), findsWidgets, reason: '基准带出 5 月那条');
    expect(
      find.textContaining('最后一次抄表来自 2026年5月'),
      findsOneWidget,
      reason: '基准不是「上一月」时要标出来源，让人自己判断用量',
    );
    expect(find.textContaining('中间没抄的月份会合进这个月'), findsOneWidget);

    // 上一月有记录时不标：这是正常的「上月读数」
    await tester.runAsync(() async {
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_jul',
          propertyId: 'p1',
          month: '2026-07',
          electricity: const UtilityReading(reading: 1120, unitPrice: 0.55),
          recordedAt: DateTime(2026, 7, 20),
        ),
      );
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityEditPage(propertyId: 'p1', month: '2026-08'),
        ),
      ),
    );
    // 先卸载再进一次：基准是 initState 算的，同一个 State 不会重算
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityEditPage(propertyId: 'p1', month: '2026-08'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('最后一次抄表来自'),
      findsNothing,
      reason: '上一月就有记录时不用标来源',
    );
    expect(find.text('1120'), findsWidgets, reason: '基准换成 7 月那条');
  });

  testWidgets('抄表录入：勾了「有燃气表」但合同没填底数，首月也要燃气基准', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final thisMonth = monthKey(DateTime.now());
    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(contract: base.contract.copyWith(hasGasMeter: true)),
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

    // 燃气那一项默认开着（合同里勾了有燃气表），并且页顶提示把它一起算上
    expect(find.text('合同里暂时还没有填写入住前的水/电/燃气表数，请录入'), findsOneWidget);
    expect(find.text('入住抄表数'), findsWidgets, reason: '首月这格叫「入住抄表数」，不叫「上月读数」');
    expect(find.text('上月读数'), findsNothing, reason: '这套房还没有上一月');
    expect(find.text('未启用，打开开关即可记录该项读数'), findsNothing);

    Finder prevField(int index) => find
        .byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              const ['上月读数', '入住抄表数'].contains(widget.decoration?.labelText),
        )
        .at(index);
    await tester.enterText(prevField(0), '1200');
    await tester.pumpAndSettle();
    await tester.enterText(prevField(1), '88');
    await tester.pumpAndSettle();
    await tester.enterText(prevField(2), '12');
    await tester.pumpAndSettle();
    expect(find.textContaining('请录入'), findsNothing, reason: '三项都填了，提示收掉');

    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '本月读数',
          )
          .first,
      '1290',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('提交'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final contract = repository.propertyById('p1')!.contract;
    expect(contract.hasGasMeter, isTrue);
    expect(contract.moveInGas, 12, reason: '首月燃气基准也要写回合同');
    expect(
      repository.utilityOfMonth('p1', thisMonth)?.gas?.previousReading,
      12,
      reason: '燃气基准同样进记录',
    );
    expect(
      repository.reminders.any((r) => r.kind == ReminderKind.moveInReading),
      isFalse,
      reason: '三项齐了，首页待办消失',
    );
  });

  testWidgets('抄表录入：缺基准就在页面上常驻提示，填完自己消失', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final thisMonth = monthKey(DateTime.now());
    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

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

    // 一次都没抄过（刚入住就是这样）：本来就不存在「上月读数」，
    // 页顶直接常驻提示（以前是弹框，用户点「稍后」就再也不填了）
    expect(find.text('合同里暂时还没有填写入住前的水/电表数，请录入'), findsOneWidget);
    expect(find.text('去填写'), findsOneWidget);
    expect(find.text('填入'), findsNothing, reason: '不再有那一套弹框按钮');

    // 「去填写」把人带到表卡里的「上月读数」
    await tester.tap(find.text('去填写'));
    await tester.pumpAndSettle();
    Finder prevField(int index) => find
        .byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              const ['上月读数', '入住抄表数'].contains(widget.decoration?.labelText),
        )
        .at(index);

    // 值填在表卡的输入框里：填了电表，提示还得留着催水表
    await tester.enterText(prevField(0), '1200');
    await tester.pumpAndSettle();
    expect(find.textContaining('请录入'), findsOneWidget, reason: '水表还没填，提示不能消失');
    await tester.enterText(prevField(1), '88');
    await tester.pumpAndSettle();
    expect(find.textContaining('请录入'), findsNothing, reason: '两项都填了，提示自己收掉');

    // 首月填的基准就是合同的入住表底数：提交时顺手写回合同
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '本月读数',
          )
          .first,
      '1290',
    );
    await tester.pump();
    expect(find.textContaining('用量 90 kWh'), findsOneWidget);
    // 提交里有两次真实落盘（记录 + 合同的入住表底数），在 runAsync 里等它跑完
    await tester.runAsync(() async {
      await tester.tap(find.text('提交'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final record = repository.utilityOfMonth('p1', thisMonth)!;
    expect(record.electricity?.previousReading, 1200, reason: '基准进记录');
    expect(record.water?.previousReading, 88);
    final contract = repository.propertyById('p1')!.contract;
    expect(contract.moveInElectricity, 1200, reason: '首月基准也要写回合同');
    expect(contract.moveInWater, 88);
    expect(
      repository.reminders.any((r) => r.kind == ReminderKind.moveInReading),
      isFalse,
      reason: '合同填上了，首页那条补填待办就该消失',
    );
  });

  testWidgets('抄表录入：回来改已有记录，不会把当初填的基准弄丢', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      await repository.addProperty(buildProperty());
      // 8 月这条：基准 1000 是当初手填的，7 月没有记录
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_aug',
          propertyId: 'p1',
          month: '2026-08',
          electricity: const UtilityReading(
            reading: 1120,
            previousReading: 1000,
            unitPrice: 0.6,
            unit: 'kWh',
          ),
          recordedAt: DateTime(2026, 8, 20),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityEditPage(propertyId: 'p1', recordId: 'u_aug'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 电表的基准来自这条记录自己（1000），不是留空 ——
    // 留空提交就会变成「本月读数 − 0」，用量和费用都白算
    expect(find.text('1000'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '电表',
      ),
      findsNothing,
      reason: '电表已经有基准了，不该再被弹框问一次',
    );
    // 这条记录里没有水表读数 → 水表是关着的，弹框也不该为它冒出来
    expect(
      find.textContaining('没有上一月的抄表记录'),
      findsNothing,
      reason: '该有的基准都有（水表没用），不该弹框',
    );

    // 只改本月读数，基准要原样留着
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '本月读数',
          )
          .first,
      '1200',
    );
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    final record = repository.utilitiesOf('p1').single;
    expect(record.electricity?.previousReading, 1000, reason: '基准不能被改掉');
    expect(record.electricity?.reading, 1200);
  });

  testWidgets('抄表录入：中间有记录时，不拿入住表底数当基准', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          contract: base.contract.copyWith(moveInElectricity: 1200),
        ),
      );
      // 7 月只记了水表
      await repository.saveUtility(
        UtilityRecord(
          id: 'u_jul',
          propertyId: 'p1',
          month: '2026-07',
          water: const UtilityReading(reading: 88, unitPrice: 3.5, unit: 'm³'),
          recordedAt: DateTime(2026, 7, 20),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const UtilityEditPage(propertyId: 'p1', month: '2026-08'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final prevTexts = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.decoration?.labelText == '上月读数')
        .map((field) => field.controller?.text)
        .toList();
    expect(prevTexts, contains('88'), reason: '水表拿 7 月那条记录');
    expect(
      prevTexts.first,
      isEmpty,
      reason:
          '电表没有更早的读数：入住表底数（3 月的数）不能顶上，'
          '不然 3~8 月的用量会被算成 8 月一个月',
    );
    // 中间已经有记录：这里缺的是「上月读数」，不是入住表底数
    expect(
      find.textContaining('没有上一月的抄表记录'),
      findsOneWidget,
      reason: '页顶常驻提示，问的是上个月的表盘数',
    );
    expect(find.textContaining('请录入'), findsNothing);

    // 填进表卡的「上月读数」并提交：这个值只属于这条记录，不该写进合同
    await tester.enterText(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                const ['上月读数', '入住抄表数'].contains(widget.decoration?.labelText),
          )
          .first,
      '1500',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('没有上一月的抄表记录'), findsNothing, reason: '填了就撤');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(
      repository.propertyById('p1')!.contract.moveInElectricity,
      1200,
      reason: '中间的「上月读数」不是合同数据，不能回写合同',
    );
  });

  testWidgets('合同详情：三个表底数输入框填完，首页那条补填待办自己消失', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(
      () => repository.addProperty(
        // 家里有燃气表：三个框都该摆出来，待办也要三项齐了才消
        buildProperty().copyWith(
          contract: buildProperty().contract.copyWith(hasGasMeter: true),
        ),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const ContractPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(
      repository.reminders.any((r) => r.kind == ReminderKind.moveInReading),
      isTrue,
      reason: '没填表底数时，首页待办里要有这条',
    );

    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    expect(field('电表'), findsOneWidget);
    expect(field('水表'), findsOneWidget);
    expect(field('燃气表'), findsOneWidget);

    final updatedBefore = repository.propertyById('p1')!.updatedAt;

    // 失焦才落盘（键盘上点「完成」、点别处都是这条路）；
    // 写盘是异步的，放在 runAsync 里等它落地
    await tester.runAsync(() async {
      await tester.enterText(field('电表'), '1200');
      await tester.pump();
      await tester.enterText(field('水表'), '88');
      await tester.pump();
      await tester.enterText(field('燃气表'), '12');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    });

    final contract = repository.propertyById('p1')!.contract;
    expect(contract.moveInElectricity, 1200);
    expect(contract.moveInWater, 88);
    expect(contract.moveInGas, 12);
    expect(
      repository.propertyById('p1')!.updatedAt,
      updatedBefore,
      reason: '补历史资料不该刷更新时间：押金「已等待 N 天」和历史排序都看它',
    );
    expect(
      repository.reminders.any((r) => r.kind == ReminderKind.moveInReading),
      isFalse,
      reason: '三项都填上了，待办要自己消失',
    );

    // 底部那个按钮也不能拿旧快照把刚存的读数盖回去
    // （它是显式的「保存」动作，所以会正常刷新更新时间，这里只看读数还在不在）
    await tester.runAsync(() async {
      await tester.tap(find.text('保存并生成提醒计划'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    });
    final afterSave = repository.propertyById('p1')!.contract;
    expect(afterSave.moveInElectricity, 1200);
    expect(afterSave.moveInWater, 88);
    expect(afterSave.moveInGas, 12);
  });

  testWidgets('添加房源向导：合同那步能填表底数，保存时不丢', (tester) async {
    // 宽一点：测试字体是等宽方块字，「入住日期 / 合同到期」那两个按钮
    // 在 390 宽下会被测试字体撑出 1.5px（真机字体不会），
    // 那跟这条用例要验的东西无关
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() async {
      final base = buildProperty();
      await repository.addProperty(
        base.copyWith(
          contract: base.contract.copyWith(moveInElectricity: 1200),
        ),
      );
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyEditPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 基本信息 → 房东 → 合同
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    // 编辑已有房源时，已经抄过的那项要带出来，不会显示成 0
    expect(tester.widget<TextField>(field('电表')).controller?.text, '1200');
    expect(tester.widget<TextField>(field('水表')).controller?.text, isEmpty);
    // 默认「没有燃气表」：燃气表读数框不该出现
    expect(find.text('没有燃气表'), findsWidgets);
    expect(field('燃气表'), findsNothing, reason: '没勾有燃气表就不该追问燃气');

    await tester.runAsync(() async {
      // 勾上「有燃气表」才会出现燃气表读数框
      await tester.tap(find.text('有燃气表'));
      await tester.pump();
      await tester.enterText(field('水表'), '88');
      await tester.pump();
      await tester.enterText(field('燃气表'), '12');
      await tester.pump();
      await tester.tap(find.text('下一步'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 特殊条款那步直接保存
      await tester.tap(find.text('保存修改'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });

    final contract = repository.propertyById('p1')!.contract;
    expect(contract.moveInWater, 88, reason: '向导里填的要存进合同');
    expect(contract.moveInGas, 12);
    expect(contract.moveInElectricity, 1200, reason: '编辑保存不能把已有的表底数弄丢');
    expect(contract.hasGasMeter, isTrue, reason: '勾了有燃气表要存下来');
  });

  testWidgets('编辑房源：别处刚改过的表底数，保存时合并进来不覆盖', (tester) async {
    // 宽一点：测试字体会把「入住日期 / 合同到期」那两个按钮撑出 1.5px
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyEditPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 进到「合同」那步
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }

    // 向导开着的时候，合同页（那三个失焦即存的框）把电表填成了 1500
    await tester.runAsync(() async {
      final property = repository.propertyById('p1')!;
      await repository.updateProperty(
        property.copyWith(
          contract: property.contract.copyWith(moveInElectricity: 1500),
        ),
        touch: false,
      );
    });
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('下一步'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('保存修改'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(
      repository.propertyById('p1')!.contract.moveInElectricity,
      1500,
      reason: '向导这一格没动过，别用打开时的空快照把别处刚填的抹掉',
    );
  });

  testWidgets('编辑房源：两边都改了表底数，保存时会问用哪个', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = await openTestRepository(tester);
    await tester.runAsync(() => repository.addProperty(buildProperty()));

    await tester.pumpWidget(
      ChangeNotifierProvider<Repository>.value(
        value: repository,
        child: MaterialApp(
          theme: ZTheme.light(),
          home: const PropertyEditPage(propertyId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }

    // 两边都动了：向导里填 1300，合同页那边改成 1500
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '电表',
      ),
      '1300',
    );
    await tester.pump();
    await tester.runAsync(() async {
      final property = repository.propertyById('p1')!;
      await repository.updateProperty(
        property.copyWith(
          contract: property.contract.copyWith(moveInElectricity: 1500),
        ),
        touch: false,
      );
    });
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('下一步'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('保存修改'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    // 真冲突：弹框把三个数都摆出来问
    expect(find.text('表底数两边都改过'), findsOneWidget);
    expect(find.textContaining('后来在合同页改成了 1500'), findsOneWidget);
    expect(find.textContaining('这里填的是 1300'), findsOneWidget);

    // 选「用合同页的」→ 存 1500
    await tester.runAsync(() async {
      await tester.tap(find.text('用合同页的'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(repository.propertyById('p1')!.contract.moveInElectricity, 1500);
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

  test('协议模板：\${name} / \${email} 换成运营方与联系邮箱', () {
    expect(
      applyProtocolPlaceholders('本协议由 \${name} 提供，联系 \${email}。'),
      '本协议由 Rinze Loop 提供，联系 rinzeloop@icloud.com。',
    );
    // 多处出现要全部替换
    expect(
      applyProtocolPlaceholders('\${name} 保留所有权利，可邮件 \${email} 联系 \${name}。'),
      'Rinze Loop 保留所有权利，可邮件 rinzeloop@icloud.com 联系 Rinze Loop。',
    );
    // 没有占位符时原样返回
    expect(applyProtocolPlaceholders('普通正文'), '普通正文');
  });

  testWidgets('首次启动弹隐私弹窗：同意后记下版本，重启不再弹', (tester) async {
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

    Future<void> pumpApp() async {
      await tester.pumpWidget(
        ZudunApp(
          repository: repository,
          session: session,
          cloud: cloud,
          notifications: NotificationService(),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 这条用例专门验证首启弹窗：把「已同意」清掉
    await tester.runAsync(() => repository.store.remove(kPrivacyConsentKey));

    await pumpApp();
    expect(find.text('服务协议和隐私政策'), findsOneWidget);
    expect(find.text('同意并接受'), findsOneWidget);

    await tester.tap(find.text('同意并接受'));
    await tester.pumpAndSettle();
    expect(find.text('服务协议和隐私政策'), findsNothing);
    expect(
      repository.store.getString(kPrivacyConsentKey),
      zudunProtocolVersion,
      reason: '同意后要把协议版本记在本机',
    );

    // 协议版本没变 → 下次启动不再打扰。
    // 先把整棵树换掉再挂 App，否则 State 会复用、等于没重启。
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp();
    expect(find.text('服务协议和隐私政策'), findsNothing);
  });

  testWidgets('隐私弹窗：暂不同意走二次确认，同意并继续也会记下', (tester) async {
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

    // 这条用例专门验证「暂不同意」的二次确认：把「已同意」清掉
    await tester.runAsync(() => repository.store.remove(kPrivacyConsentKey));

    await tester.pumpWidget(
      ZudunApp(
        repository: repository,
        session: session,
        cloud: cloud,
        notifications: NotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('暂不同意'));
    await tester.pumpAndSettle();
    expect(find.text('确认提示'), findsOneWidget);
    expect(find.text('退出应用'), findsOneWidget);

    // 这期间 App 是被挡住的：不能让人不表态就继续用
    expect(find.text('请先阅读并同意协议'), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(find.text('确认提示'), findsNothing);
    expect(find.text('请先阅读并同意协议'), findsNothing, reason: '同意后放行');
    expect(
      repository.store.getString(kPrivacyConsentKey),
      zudunProtocolVersion,
    );
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
        child: MaterialApp(theme: ZTheme.light(), home: const LoginPage()),
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

    // 未勾选协议时点验证码入口仍要给反馈，而不是看起来点不动
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();
    expect(find.text('请先勾选下面的《隐私政策》和《平台注册协议》'), findsOneWidget);
    expect(find.text('请先勾选协议后再获取验证码'), findsOneWidget);

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
        child: MaterialApp(theme: ZTheme.light(), home: const AboutPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('注销账号'), findsOneWidget);
    // 「账号与同步」页已并进设置：不再摆同步细节与服务器地址
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

  test('agreement 接口读取服务入口并上报通讯录', () async {
    http.Request? uploadRequest;
    final api = ApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/sys_config/get/value/config/')) {
          return _jsonResponse({
            'code': '00000',
            'data': jsonEncode({
              'h5DownloadUrl': 'https://service.example.test/agreement',
            }),
          });
        }
        uploadRequest = request;
        return _jsonResponse({'code': '00000', 'data': null});
      }),
    );
    addTearDown(api.close);
    final agreement = AgreementApi(api);

    final config = await agreement.readEntryConfig('哆米记账');
    expect(config['h5DownloadUrl'], 'https://service.example.test/agreement');

    await agreement.uploadOtherContacts(
      userId: 'u-1',
      contacts: [
        {'name': '小张', 'phone': '13800138000'},
      ],
    );
    expect(uploadRequest?.method, 'POST');
    expect(uploadRequest?.url.path, '/mall-connect/kyc/set_other_contact');
    final body = jsonDecode(uploadRequest!.body) as Map<String, dynamic>;
    expect(body['userId'], 'u-1');
    expect(jsonDecode(body['otherContact'] as String), [
      {'name': '小张', 'phone': '13800138000'},
    ]);
  });

  test('agreement 入口 URL 与 H5 消息兼容 uni-app', () {
    final url = AgreementSupport.buildEntryUrl(
      baseUrl: 'https://example.test/agreement?existing=1#section',
      token: 'T+/1',
      appName: '哆米记账',
      statusHeight: 47,
      longitude: 116.397,
      latitude: 39.908,
    );
    final uri = Uri.parse(url);
    expect(uri.queryParameters['existing'], '1');
    expect(uri.queryParameters['token'], 'T+/1');
    expect(uri.queryParameters['appName'], '哆米记账');
    expect(uri.queryParameters['statusHeight'], '47.0');
    expect(uri.queryParameters['longitude'], '116.397');
    expect(uri.queryParameters['latitude'], '39.908');
    expect(uri.fragment, 'section');

    expect(
      AgreementSupport.messagePayload(
        jsonEncode({
          'data': {'action': 'three', 'path': 'https://example.test/detail'},
        }),
      )?['action'],
      'three',
    );
    expect(
      AgreementSupport.messagePayload(
        jsonEncode([
          {
            'arg': {
              'data': {'action': 'needOtherConstact', 'needOtherConstact': 2},
            },
          },
        ]),
      )?['needOtherConstact'],
      2,
    );
    expect(
      AgreementSupport.messagePayload(
        jsonEncode({
          'type': 'WEB_INVOKE_APPSERVICE',
          'data': {
            'name': 'postMessage',
            'arg': {'action': 'logout'},
          },
        }),
      )?['action'],
      'logout',
    );
    expect(
      AgreementSupport.messagePayload(
        jsonEncode({
          'type': 'WEB_INVOKE_APPSERVICE',
          'data': {
            'name': 'postMessage',
            'arg': {'action': 'deleteAccount'},
          },
        }),
      )?['action'],
      'deleteAccount',
    );
    expect(
      AgreementSupport.messagePayload(
        jsonEncode({
          'type': 'WEB_INVOKE_APPSERVICE',
          'data': {
            'name': 'postMessage',
            'arg': {'action': 'needLoaction', 'needLoaction': 1},
          },
        }),
      )?['needLoaction'],
      1,
    );
    expect(
      AgreementSupport.messagePayload(
        jsonEncode({
          'type': 'WEB_INVOKE_APPSERVICE',
          'data': {
            'name': 'postMessage',
            'arg': {'action': 'needOtherConstact', 'needOtherConstact': 2},
          },
        }),
      )?['needOtherConstact'],
      2,
    );
    expect(AgreementSupport.messagePayload('not-json'), isNull);
    expect(AgreementSupport.isSafeWebUrl('https://example.test/a'), isTrue);
    expect(AgreementSupport.isSafeWebUrl('javascript:alert(1)'), isFalse);
    expect(
      AgreementSupport.isExternalUrl(
        'https://apps.apple.com/cn/app/id1234567890',
      ),
      isTrue,
    );
    expect(
      AgreementSupport.isExternalUrl('https://example.test/app.apk?v=1'),
      isTrue,
    );
    expect(
      AgreementSupport.isExternalUrl('https://example.test/detail'),
      isFalse,
    );
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

    // 平台后台实际下发的那套按平台分字段的写法
    const serverPayload = {
      'iosAppVersion': '1.0.2',
      'iosAppDownloadUrl': 'https://apps.apple.com/app/id1234567890',
      'iosUpdateType': 1,
      'goodsLogo': 'https://mizhenhl.oss-cn-beijing.aliyuncs.com/mall/logo.png',
      'androidVersion': '1.0.1',
      'androidUpdateType': 0,
    };
    final ios = parseAppUpdate(serverPayload, platform: TargetPlatform.iOS);
    expect(ios?.version, '1.0.2', reason: 'iOS 读 iosAppVersion');
    expect(ios?.url, 'https://apps.apple.com/app/id1234567890');
    expect(
      ios?.logoUrl,
      'https://mizhenhl.oss-cn-beijing.aliyuncs.com/mall/logo.png',
      reason: '更新弹窗使用接口 goodsLogo',
    );
    expect(ios?.force, isFalse, reason: 'updateType=1 是提示更新，能稍后再说');
    expect(ios?.blocking, isFalse);
    final android = parseAppUpdate(
      serverPayload,
      platform: TargetPlatform.android,
    );
    expect(android, isNull, reason: '安卓那组是 updateType=0（后台关掉了更新提示），什么都不该弹');
    final androidOn = parseAppUpdate({
      ...serverPayload,
      'androidUpdateType': 1,
    }, platform: TargetPlatform.android);
    expect(androidOn?.version, '1.0.1', reason: 'Android 读 androidVersion');
    expect(androidOn?.url, '', reason: '没下发 android 下载地址就留空');
    expect(
      parseAppUpdate({
        ...serverPayload,
        'iosUpdateType': 0,
      }, platform: TargetPlatform.iOS),
      isNull,
      reason: '后台把更新提示关掉（updateType=0）就不再弹，哪怕版本更高',
    );
    expect(
      parseAppUpdate({
        ...serverPayload,
        'iosUpdateType': 1,
      }, platform: TargetPlatform.iOS)?.force,
      isFalse,
      reason: 'updateType=1 是普通更新，不锁用户',
    );
    final forcedByType = parseAppUpdate({
      ...serverPayload,
      'iosUpdateType': 2,
    }, platform: TargetPlatform.iOS);
    expect(
      forcedByType?.force,
      isTrue,
      reason: 'jianzhirj 口径中 updateType=2 就是强制更新',
    );
    expect(forcedByType?.blocking, isTrue);
    final forcedWithoutUrl = newerUpdate(
      {
        ...serverPayload,
        'iosUpdateType': 2,
        'iosAppVersion': '2.0.0',
        'iosAppDownloadUrl': '',
      },
      '1.0.1',
      platform: TargetPlatform.iOS,
    );
    expect(forcedWithoutUrl, isNotNull, reason: '更新弹框与是否配置下载地址无关');
    expect(forcedWithoutUrl?.blocking, isTrue);
    final normalWithoutUrl = newerUpdate(
      {
        ...serverPayload,
        'iosUpdateType': 1,
        'iosAppVersion': '2.0.0',
        'iosAppDownloadUrl': '',
      },
      '1.0.1',
      platform: TargetPlatform.iOS,
    );
    expect(normalWithoutUrl, isNotNull);
    expect(normalWithoutUrl?.blocking, isFalse);

    // 与 jianzhirj 一致：地址只要求非空且可解析，测试地址也照常触发。
    final placeholder = parseAppUpdate({
      ...serverPayload,
      'iosAppDownloadUrl': 'https://example.com/app',
      'force': true,
    }, platform: TargetPlatform.iOS);
    expect(placeholder?.url, 'https://example.com/app');
    expect(placeholder?.force, isTrue, reason: '强制标记本身还是要认');
    expect(placeholder?.blocking, isTrue);
    final currentForcedConfig = newerUpdate(
      {
        ...serverPayload,
        'iosUpdateType': 2,
        'iosAppVersion': '1.0.3',
        'iosAppDownloadUrl': 'https://www.baidu.com',
      },
      '1.0.2',
      platform: TargetPlatform.iOS,
    );
    expect(currentForcedConfig, isNotNull, reason: '后台当前用百度地址测试时，强制更新仍应触发');
    expect(currentForcedConfig?.force, isTrue);
  });

  testWidgets('版本更新弹窗：显示新版本并可关闭，同版本不弹', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 没有更高版本就什么都不弹（弹窗只负责展示，判断在调用方）
    Future<void> show(String version) async {
      final info = newerUpdate(
        jsonEncode({
          'version': version,
          'notes': '新增隐私确认页',
          'downloadUrl': 'https://apps.apple.com/app/id1234567890',
        }),
        '1.0.1',
      );
      if (info == null) return;
      await showAppUpdateDialog(
        context: tester.element(find.text('检查更新')),
        info: info,
        currentVersion: '1.0.1',
      );
    }

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
    expect(find.text('应用有新版本了'), findsOneWidget);
    expect(find.text('版本 9.9.9'), findsOneWidget);
    expect(find.text('新增隐私确认页'), findsOneWidget);
    await tester.tap(find.text('稍后更新'));
    await tester.pumpAndSettle();
    expect(find.text('应用有新版本了'), findsNothing);

    // 同一个版本不再弹
    await show('1.0.1');
    await tester.pumpAndSettle();
    expect(find.textContaining('应用有新版本了'), findsNothing);
  });

  testWidgets('更新弹窗：强制更新 + 有下载地址才锁住用户', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const info = AppUpdateInfo(
      version: '9.9.9',
      url: 'https://apps.apple.com/app/id1234567890',
      force: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ZTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAppUpdateDialog(
                  context: context,
                  info: info,
                  currentVersion: '1.0.1',
                ),
                child: const Text('检查更新'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('应用有新版本了'), findsOneWidget);
    expect(find.text('必须更新'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing, reason: '弹窗不显示下载地址');
    expect(find.text('稍后更新'), findsNothing, reason: '强制更新不给稍后更新');
    await tester.tapAt(const Offset(6, 6)); // 点遮罩
    await tester.pumpAndSettle();
    expect(find.text('应用有新版本了'), findsOneWidget, reason: '强制更新点遮罩也关不掉');
  });

  testWidgets('更新弹窗：强制更新没有地址时仍然不可关闭', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 弹框触发不依赖下载地址；强制状态仍然不可取消。
    const info = AppUpdateInfo(version: '9.9.9', force: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ZTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAppUpdateDialog(
                  context: context,
                  info: info,
                  currentVersion: '1.0.1',
                ),
                child: const Text('检查更新'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('应用有新版本了'), findsOneWidget);
    expect(find.text('立即更新'), findsNothing, reason: '没地址就不摆这个按钮');
    expect(find.text('更新地址暂未配置'), findsOneWidget);
    expect(find.text('稍后更新'), findsNothing, reason: '强制更新不能稍后');
    await tester.tapAt(const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(find.text('应用有新版本了'), findsOneWidget, reason: '没有地址也不能退出强制更新');
  });
}
