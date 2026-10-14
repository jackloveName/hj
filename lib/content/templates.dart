import '../utils/format.dart';

class TemplateField {
  const TemplateField({required this.key, required this.label, this.hint = ''});

  final String key;
  final String label;
  final String hint;
}

class DocTemplate {
  const DocTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.fields,
  });

  final String id;
  final String name;
  final String description;
  final String emoji;
  final List<TemplateField> fields;
}

const List<DocTemplate> docTemplates = [
  DocTemplate(
    id: 'demand',
    name: '押金退还催告函',
    description: '正式催告房东退还押金，明确期限与法律依据',
    emoji: '📮',
    fields: [
      TemplateField(key: 'tenant', label: '你的姓名', hint: '如：王小明'),
      TemplateField(key: 'landlord', label: '房东姓名', hint: '如：张建国'),
      TemplateField(key: 'address', label: '房屋地址', hint: '详细到门牌号'),
      TemplateField(key: 'deposit', label: '押金金额（元）', hint: '如：8000'),
      TemplateField(key: 'moveOut', label: '退租交接日期', hint: '如：2026-12-31'),
      TemplateField(key: 'deadline', label: '要求退还期限（天）', hint: '如：7'),
      TemplateField(
        key: 'reason',
        label: '房东扣款理由（如有）',
        hint: '如：主张地板划痕扣 800 元',
      ),
    ],
  ),
  DocTemplate(
    id: 'complaint',
    name: '投诉信模板',
    description: '向住建部门 / 12345 提交的书面投诉',
    emoji: '📨',
    fields: [
      TemplateField(key: 'tenant', label: '投诉人姓名'),
      TemplateField(key: 'phone', label: '联系电话'),
      TemplateField(key: 'landlord', label: '被投诉人（房东）'),
      TemplateField(key: 'address', label: '房屋地址'),
      TemplateField(key: 'deposit', label: '争议金额（元）'),
      TemplateField(key: 'fact', label: '事实经过', hint: '简述退租与扣押金过程'),
    ],
  ),
  DocTemplate(
    id: 'lawsuit',
    name: '民事起诉状',
    description: '小额诉讼：向法院起诉要求退还押金',
    emoji: '⚖️',
    fields: [
      TemplateField(key: 'tenant', label: '原告姓名'),
      TemplateField(key: 'tenantInfo', label: '原告身份信息', hint: '身份证号 / 住址 / 电话'),
      TemplateField(key: 'landlord', label: '被告姓名'),
      TemplateField(key: 'landlordInfo', label: '被告身份信息', hint: '地址 / 电话'),
      TemplateField(key: 'address', label: '房屋地址'),
      TemplateField(key: 'deposit', label: '诉讼请求金额（元）'),
      TemplateField(key: 'fact', label: '事实与理由'),
    ],
  ),
];

String _or(String? value, String fallback) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}

String buildDemandLetter(Map<String, String> v) {
  final tenant = _or(v['tenant'], '____');
  final landlord = _or(v['landlord'], '____');
  final address = _or(v['address'], '____');
  final deposit = _or(v['deposit'], '____');
  final moveOut = _or(v['moveOut'], '____');
  final deadline = _or(v['deadline'], '7');
  final reason = v['reason']?.trim() ?? '';
  final reasonBlock = reason.isEmpty
      ? ''
      : '\n对于贵方主张的「$reason」，本人不予认可。该情况在入住时即已存在，'
            '已由入住取证照片（带拍摄时间水印）记录在案。依据《民法典》第七百一十条，'
            '承租人按照约定的方法使用租赁物，致使租赁物受到损耗的，不承担赔偿责任。\n';

  return '''
押金退还催告函

致：$landlord（房东）

本人 $tenant，承租位于 $address 的房屋，已于 $moveOut 完成退租交接并将房屋返还。
依据双方租赁合同约定，本人入住时已支付押金人民币 $deposit 元。截至本函发出之日，
本人不存在拖欠租金、水电燃气等费用的情形，房屋亦无超出正常使用损耗的损坏。
$reasonBlock
根据《民法典》第七百一十条、第七百一十四条及相关规定，请贵方于收到本函之日起
$deadline 日内，将押金人民币 $deposit 元全额退还至以下账户：

    收款人：$tenant
    开户行：____________________
    账  号：____________________

逾期未退还的，本人将依法向房屋所在地人民法院提起诉讼，并要求贵方承担诉讼费用
及资金占用期间的相关损失。相关取证材料（入住 / 退租对比照片、租赁合同、缴费凭证）
均已完整保存，可随时提供。

特此函告。

催告人：$tenant
日期：${fmtDateCn(DateTime.now())}
''';
}

String buildComplaintLetter(Map<String, String> v) {
  final tenant = _or(v['tenant'], '____');
  final phone = _or(v['phone'], '____');
  final landlord = _or(v['landlord'], '____');
  final address = _or(v['address'], '____');
  final deposit = _or(v['deposit'], '____');
  final fact = _or(
    v['fact'],
    '本人依约承租上述房屋，退租时已完成房屋交接并将房屋返还。房东以房屋存在瑕疵为由'
    '拒绝退还押金，但相关瑕疵在入住时即已存在，有入住取证照片（带时间水印）为证，'
    '并非本人使用造成。',
  );

  return '''
关于房东无正当理由扣押押金的投诉

投诉人：$tenant
联系电话：$phone
被投诉人：$landlord（房东）
房屋地址：$address
争议金额：人民币 $deposit 元

一、事实经过
$fact

二、投诉请求
1. 请贵部门督促被投诉人依法退还押金人民币 $deposit 元；
2. 请对被投诉人房屋租赁活动中未按规定办理租赁合同备案等问题进行核查；
3. 请将处理结果书面告知投诉人。

三、证据材料
1. 房屋租赁合同；
2. 押金及租金支付凭证；
3. 入住取证照片、退租对比照片（含拍摄时间水印）；
4. 与房东的沟通记录（微信 / 短信截图）。

投诉人：$tenant
日期：${fmtDateCn(DateTime.now())}
''';
}

String buildLawsuit(Map<String, String> v) {
  final tenant = _or(v['tenant'], '____');
  final tenantInfo = _or(v['tenantInfo'], '____');
  final landlord = _or(v['landlord'], '____');
  final landlordInfo = _or(v['landlordInfo'], '____');
  final address = _or(v['address'], '____');
  final deposit = _or(v['deposit'], '____');
  final fact = _or(
    v['fact'],
    '被告以房屋存在瑕疵为由拒绝退还押金，但该瑕疵系入住时既已存在，'
    '有原告入住取证照片为证，并非原告使用造成。',
  );

  return '''
民事起诉状

原告：$tenant
身份信息：$tenantInfo

被告：$landlord
身份信息：$landlordInfo

案由：房屋租赁合同纠纷

诉讼请求
1. 请求判令被告退还押金人民币 $deposit 元；
2. 请求判令被告支付逾期退还押金的资金占用损失（自退租交接之日起至实际付清之日止，
   按全国银行间同业拆借中心公布的贷款市场报价利率计算）；
3. 本案诉讼费用由被告承担。

事实与理由
原告与被告就 $address 房屋签订租赁合同，并按约定支付了押金。租赁期满（或依法解除）后，
原告已完成房屋交接并将房屋返还给被告。$fact

依据《中华人民共和国民法典》第七百一十条、第七百一十四条、第七百三十四条之规定，
承租人按照约定的方法使用租赁物，致使租赁物受到损耗的，不承担赔偿责任。
被告无正当理由扣押押金，已构成违约，依法应予退还。

证据清单
1. 房屋租赁合同；
2. 押金、租金支付凭证；
3. 入住取证照片及退租对比照片（含拍摄时间水印）；
4. 双方沟通记录；
5. 其他相关证据。

此致
$address 所在地人民法院

具状人：$tenant
日期：${fmtDateCn(DateTime.now())}
''';
}

String renderTemplate(String id, Map<String, String> values) => switch (id) {
  'demand' => buildDemandLetter(values),
  'complaint' => buildComplaintLetter(values),
  'lawsuit' => buildLawsuit(values),
  _ => '',
};
