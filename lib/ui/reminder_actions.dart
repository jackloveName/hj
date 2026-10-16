import 'package:flutter/material.dart';

import '../models/models.dart';
import 'compare/compare_page.dart';
import 'evidence/evidence_rooms_page.dart';
import 'expense/expense_page.dart';
import 'expense/utility_page.dart';
import 'kit.dart';
import 'property/contract_page.dart';

/// 待办点进去该到哪个页面。
///
/// 首页的待办卡和租住页的「下一步」用的是同一套规则，所以放在这里，
/// 免得两处各写一份、以后加了新的待办类型只改了一边。
/// （规则：抄表去水电燃气、取证去入住取证、押金去退租对比、
/// 到期去合同页、入住表底数待补也去合同页（那三个输入框就在合同详情里）；
/// 该交租 / 逾期去费用页的租金日历处理。）
Future<void> openReminder(BuildContext context, ReminderItem item) async {
  switch (item.kind) {
    case ReminderKind.photoMissing:
      await zPush(context, EvidenceRoomsPage(propertyId: item.propertyId));
    case ReminderKind.utilityReading:
      await zPush(context, UtilityPage(propertyId: item.propertyId));
    case ReminderKind.rentDue:
      await zPush(context, const ExpensePage());
    case ReminderKind.depositReturn:
      await zPush(context, ComparePage(propertyId: item.propertyId));
    case ReminderKind.contractExpire:
      await zPush(context, ContractPage(propertyId: item.propertyId));
    // 补表底数也去合同页：那三个输入框就摆在合同详情里
    case ReminderKind.moveInReading:
      await zPush(context, ContractPage(propertyId: item.propertyId));
  }
}

/// 待办对应的图标：首页待办卡与租住页「下一步」保持一致
IconData reminderIcon(ReminderKind kind) => switch (kind) {
  ReminderKind.rentDue => Icons.account_balance_wallet_outlined,
  ReminderKind.contractExpire => Icons.description_outlined,
  ReminderKind.utilityReading => Icons.bolt_outlined,
  ReminderKind.depositReturn => Icons.savings_outlined,
  ReminderKind.photoMissing => Icons.photo_camera_outlined,
  ReminderKind.moveInReading => Icons.speed_outlined,
};
