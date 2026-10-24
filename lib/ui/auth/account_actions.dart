import 'package:flutter/material.dart';

import '../../services/cloud_service.dart';
import '../kit.dart';

/// 账号相关的两个动作。
///
/// 原来的「账号与同步」页已经并进「设置」了（设置 → 退出登录 / 注销账号），
/// 这里只留动作本身，不再有页面。

/// 138****6677
String maskPhone(String phone) {
  if (phone.length < 8) return phone;
  return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
}

/// 退出登录：只断开账号并清空本机数据，云端数据保留
Future<void> logoutAccount(BuildContext context, CloudService cloud) async {
  final ok = await zConfirm(
    context,
    title: '退出登录',
    message: '退出后将清除这台设备上的房源、照片和账号缓存，云端数据不会被删除。',
    confirmText: '退出',
  );
  if (!ok || !context.mounted) return;
  await cloud.logout();
  if (!context.mounted) return;
  zToast(context, '已退出登录');
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// 注销账号：删除云端账号与本机这份账号数据，需要二次确认
Future<void> destroyAccount(BuildContext context, CloudService cloud) async {
  final phone = maskPhone(cloud.session.phone);
  final ok = await zConfirm(
    context,
    title: '注销账号',
    message: '将删除 $phone 在服务器上的租盾数据（含照片）并注销账号，操作不可恢复。',
    confirmText: '继续',
    danger: true,
  );
  if (!ok || !context.mounted) return;

  final sure = await zConfirm(
    context,
    title: '再次确认注销',
    message: '删除后无法找回，本机这份账号数据也会被清掉。确定要注销吗？',
    confirmText: '注销账号',
    danger: true,
  );
  if (!sure || !context.mounted) return;

  try {
    await cloud.destroyAccount();
  } catch (error) {
    if (context.mounted) zToast(context, '注销失败：$error');
    return;
  }
  if (!context.mounted) return;
  zToast(context, '账号已注销');
  Navigator.of(context).popUntil((route) => route.isFirst);
}
