class LawItem {
  const LawItem({required this.title, required this.sub});

  final String title;
  final String sub;
}

class DisputeStep {
  const DisputeStep({
    required this.index,
    required this.title,
    this.tag,
    this.note,
  });

  final int index;
  final String title;
  final String? tag;
  final String? note;
}

class LegalBlock {
  const LegalBlock({this.heading, this.text, this.bullets = const []});

  final String? heading;
  final String? text;
  final List<String> bullets;
}

class LegalArticle {
  const LegalArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.blocks,
  });

  final String id;
  final String title;
  final String summary;
  final List<LegalBlock> blocks;
}

/// 《民法典》核心条款摘录（对应设计稿法规指南首屏）
const String lawQuoteTitle = '《民法典》第七百一十四条';
const String lawQuoteText =
    '承租人应当按照约定的方法使用租赁物。因承租人按照约定的方法或者根据租赁物的性质使用租赁物，'
    '使租赁物受到损耗的，承租人不承担赔偿责任的。';

/// 房东不可扣除押金（绿）
const List<LawItem> cannotDeduct = [
  LawItem(title: '正常使用产生的合理损耗', sub: '地板划痕、墙面轻微褪色、插座松动'),
  LawItem(title: '入住前已存在的房屋瑕疵', sub: '需要入住取证照片作为证据'),
  LawItem(title: '房东自身原因造成的损坏', sub: '管线老化、防水失效、电器自然老化'),
];

/// 房东可依法扣除（红）
const List<LawItem> canDeduct = [
  LawItem(title: '人为损坏且无法举证免责', sub: '举证责任在租户'),
  LawItem(title: '违反合同约定的使用方式', sub: '如养宠、擅自改结构、违规转租'),
  LawItem(title: '拖欠租金与水电燃气费', sub: '需房东提供真实欠费凭证'),
];

const List<DisputeStep> disputeSteps = [
  DisputeStep(index: 1, title: '与房东协商', tag: '附话术模板'),
  DisputeStep(index: 2, title: '居委会 / 街道调解', note: '免费'),
  DisputeStep(index: 3, title: '拨打 12345 市民热线', note: '7×24h'),
  DisputeStep(index: 4, title: '向住建部门投诉', note: '需对比报告', tag: '需对比报告'),
  DisputeStep(index: 5, title: '仲裁 / 法律诉讼', tag: '小额诉讼'),
];

const String legalDisclaimer =
    '以上内容依据现行法律法规整理，仅供参考，不构成法律意见。'
    '具体纠纷建议结合合同约定与证据材料，咨询专业律师或当地住建部门。';

const List<LegalArticle> legalArticles = [
  LegalArticle(
    id: 'deposit',
    title: '押金退还法规',
    summary: '押金什么时候必须退、房东什么情况可以扣',
    blocks: [
      LegalBlock(
        heading: '押金的法律性质',
        text:
            '押金属于担保租赁合同履行的金钱担保，不是违约金。租赁关系结束、房屋已返还、'
            '且不存在承租人违约损失时，押金应当退还。《民法典》第七百一十四条规定：'
            '承租人应当按照约定的方法使用租赁物。',
      ),
      LegalBlock(
        heading: '应当全额退还的情形',
        bullets: [
          '合同已到期或依法解除，且承租人已返还房屋；',
          '不存在拖欠租金、水电燃气等费用；',
          '损坏属于正常使用造成的自然损耗（第七百一十条）；',
          '合同没有就押金扣除作出明确且合法的约定。',
        ],
      ),
      LegalBlock(
        heading: '可以合法扣除的情形',
        bullets: [
          '拖欠租金、物业费、水电燃气费；',
          '未按约定方法使用造成超出正常损耗的损坏（第七百一十一条）；',
          '擅自转租、改变房屋结构且未恢复原状；',
          '提前退租，合同明确约定违约金且金额合理。',
        ],
      ),
      LegalBlock(
        heading: '退还期限',
        text:
            '合同有约定的按约定；没有约定的，退房交接完成后应在合理期限内退还，'
            '实务中一般不超过 15 天。逾期不退，可以主张资金占用损失。',
      ),
    ],
  ),
  LegalArticle(
    id: 'landlord',
    title: '房东义务',
    summary: '房东必须做什么、不能做什么',
    blocks: [
      LegalBlock(
        heading: '保证房屋安全宜居',
        text:
            '出租人应当保证租赁物符合约定用途，并保证房屋及附属设施在租赁期间处于'
            '正常可使用状态，不得存在危及人身安全的情形。',
      ),
      LegalBlock(
        heading: '维修义务',
        bullets: [
          '《民法典》第七百一十二条：出租人应当履行租赁物的维修义务，当事人另有约定的除外；',
          '第七百一十三条：房屋需要维修，承租人可以请求出租人在合理期限内维修；'
              '出租人未履行维修义务的，承租人可以自行维修，费用由出租人负担；',
          '因维修影响承租人使用的，应当相应减少租金或者延长租期。',
        ],
      ),
      LegalBlock(
        heading: '不得随意涨租、不得随意收回',
        bullets: [
          '租期内租金标准按合同执行，房东不能单方面涨租；',
          '合同未到期，房东无正当理由不得要求承租人搬离；',
          '房东出售房屋不影响租赁合同效力（买卖不破租赁，第七百二十五条）。',
        ],
      ),
    ],
  ),
  LegalArticle(
    id: 'tenant',
    title: '我的权利',
    summary: '租客依法享有的四项关键权利',
    blocks: [
      LegalBlock(
        heading: '优先续租权',
        text:
            '《民法典》第七百三十四条：租赁期限届满，房屋承租人享有以同等条件优先承租的权利。'
            '租赁期限届满，承租人继续使用租赁物，出租人没有提出异议的，原租赁合同继续有效，'
            '但租赁期限为不定期。',
      ),
      LegalBlock(
        heading: '买卖不破租赁',
        text:
            '《民法典》第七百二十五条：租赁物在承租人按照租赁合同占有期限内发生所有权变动的，'
            '不影响租赁合同的效力。',
      ),
      LegalBlock(
        heading: '合理损耗不负责',
        text:
            '《民法典》第七百一十条：承租人按照约定的方法或者根据租赁物的性质使用租赁物，'
            '致使租赁物受到损耗的，不承担赔偿责任。',
      ),
      LegalBlock(
        heading: '提前退租的条件',
        bullets: [
          '合同有约定的按约定（常见为提前 30 天通知）；',
          '房屋存在安全隐患、无法正常居住时，可以解除合同并要求退还押金；',
          '房东违约导致无法居住，可解除合同且不担责；',
          '违约金明显过高的，可以请求调整。',
        ],
      ),
    ],
  ),
  LegalArticle(
    id: 'process',
    title: '纠纷流程',
    summary: '从协商到诉讼，5 步走完维权路径',
    blocks: [
      LegalBlock(
        heading: '第 1 步 · 与房东协商',
        text:
            '整理入住取证照片、退租照片、合同与缴费记录，形成对比说明后提出诉求与期限。'
            '参考话术：“该处瑕疵在入住时就已存在，依据《民法典》第七百一十条，'
            '希望您在 7 日内退还押金，我可以提供完整取证包。”',
      ),
      LegalBlock(
        heading: '第 2 步 · 居委会 / 街道调解',
        text:
            '向房屋所在地社区居委会、街道人民调解委员会申请调解，'
            '调解协议经司法确认后具有强制执行力。',
      ),
      LegalBlock(
        heading: '第 3 步 · 12345 市民热线',
        text:
            '拨打 12345 或通过当地政务 App 提交诉求，说明房东无正当理由扣押押金，'
            '请求住建部门介入协调。',
      ),
      LegalBlock(
        heading: '第 4 步 · 住建部门投诉',
        text:
            '向房屋所在地住建委（房管局）投诉，附上退租对比报告，'
            '说明“未按规定退还押金”等问题。',
      ),
      LegalBlock(
        heading: '第 5 步 · 仲裁或诉讼',
        text:
            '合同约定仲裁的走仲裁；没有约定的，可向被告住所地或合同履行地人民法院起诉。'
            '押金金额通常符合小额诉讼程序，一审终审、周期短、诉讼费低。',
      ),
    ],
  ),
  LegalArticle(
    id: 'docs',
    title: '文书模板',
    summary: '催告函 / 投诉信 / 起诉状，一键套用',
    blocks: [
      LegalBlock(
        heading: '使用顺序建议',
        bullets: [
          '先发《押金退还催告函》，给对方明确期限；',
          '无效后提交《投诉信》至 12345 / 住建部门；',
          '仍未解决再提交《民事起诉状》走小额诉讼。',
        ],
      ),
      LegalBlock(
        heading: '证据清单',
        bullets: [
          '租赁合同（含押金、退租条款）；',
          '押金与租金支付凭证；',
          '入住取证照片（带时间水印）与退租对比照片；',
          '与房东的沟通记录截图；',
          '水电燃气缴费记录与抄表照片。',
        ],
      ),
    ],
  ),
];
