import '../models/models.dart';
import '../theme/tokens.dart';

class ContractRisk {
  const ContractRisk({
    required this.tone,
    required this.title,
    required this.detail,
    required this.advice,
  });

  final ZTone tone;
  final String title;
  final String detail;
  final String advice;
}

/// 本地关键词规则扫描：不联网，仅根据合同文字给出风险提示。
List<ContractRisk> scanContract(ContractInfo contract) {
  final text = [
    contract.specialTerms,
    contract.earlyTermination,
    contract.renewalTerms,
  ].join(' ');

  final risks = <ContractRisk>[];
  void check(
    List<String> keywords,
    ZTone tone,
    String title,
    String detail,
    String advice,
  ) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) {
        risks.add(
          ContractRisk(
            tone: tone,
            title: title,
            detail: detail,
            advice: advice,
          ),
        );
        return;
      }
    }
  }

  check(
    ['押金不退', '不予退还押金', '押金一律不退'],
    ZTone.danger,
    '存在“押金不退”约定',
    '合同中出现押金一律不退的表述。',
    '此类条款排除承租人主要权利，效力存疑。请保留合同原件，并在入住时完整取证。',
  );
  check(
    ['清洁费', '管理费', '折旧费'],
    ZTone.warn,
    '存在额外扣费名目',
    '合同约定了清洁费 / 管理费 / 折旧费等扣款项。',
    '要求房东明确扣费标准与上限，退租时索要真实凭证。',
  );
  check(
    ['恢复原状', '恢复原样', '原样返还'],
    ZTone.warn,
    '要求“恢复原状”',
    '“恢复原状”的范围容易产生争议。',
    '入住取证时把所有既有瑕疵拍照留证，避免退租时被要求承担原有问题。',
  );
  check(
    ['自动续租', '自动延期'],
    ZTone.warn,
    '自动续租条款',
    '合同约定了自动续租。',
    '记好合同到期日，如不续租需在约定时间前书面通知房东。',
  );
  check(
    ['涨租', '涨幅', '调整租金'],
    ZTone.warn,
    '涉及租金调整',
    '合同中出现涨租 / 租金调整约定。',
    '确认涨租周期与上限。租期内单方涨租无效，续租按约定协商。',
  );
  check(['违约金'], ZTone.brand, '约定违约金', '合同约定了违约金。', '注意违约金比例，明显过高的可请求法院调整。');
  check(
    ['断水', '断电', '押二付三', '押一付十二'],
    ZTone.danger,
    '高风险付款或强制条款',
    '合同中出现断水断电或高额预付租金的约定。',
    '断水断电属于违法自助行为；高额预付会显著增加资金风险，建议谨慎签署。',
  );

  if (contract.monthlyRent > 0 &&
      contract.deposit > contract.monthlyRent * 1.5) {
    risks.add(
      const ContractRisk(
        tone: ZTone.warn,
        title: '押金高于 1.5 个月租金',
        detail: '押金金额明显高于一个月租金。',
        advice: '确认押金退还条件与期限，并在合同中写明退还时间。',
      ),
    );
  }
  return risks;
}
