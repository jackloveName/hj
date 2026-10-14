// 把「界面用的中文字体」裁成 App 真正用到的字符（Node 版，无需 Python）。
//
// 为什么要拆成两份字体：
//   - 界面（assets/fonts/NotoSansSC-*.ttf）：只需要 App 里出现的字，200KB 出头，
//     Web 首屏就只下这点；生僻字走引擎兜底（手机用系统字体、Web 在线时用 Noto 兜底）。
//   - PDF 导出（assets/fonts/pdf/NotoSansSC-*.ttf）：保留全量（GB2312 全覆盖），
//     用 rootBundle 在**导出那一刻**才读，正常使用不会下载它。
//     报告是证据材料，不能因为生僻字变 □。
//
// 用法（仓库根目录）：
//   cd .fontwork && npm install && cd ..
//   node .fontwork/subset_ui_fonts.mjs
//
// 注意：重跑会覆盖 assets/fonts/NotoSansSC-*.ttf；全量字体在 assets/fonts/pdf/。
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import subsetFont from 'subset-font';

const require = createRequire(import.meta.url);
const fontkit = require('fontkit');

const root = process.cwd();
const fullDir = join(root, 'assets', 'fonts', 'pdf');
const uiDir = join(root, 'assets', 'fonts');

/** 收集 lib/ 下所有 dart 文件里出现的字符（去掉注释，注释不渲染） */
function collectChars(dir) {
  const chars = new Set();
  const visit = (path) => {
    for (const name of readdirSync(path)) {
      const full = join(path, name);
      if (statSync(full).isDirectory()) {
        visit(full);
      } else if (name.endsWith('.dart')) {
        if (name === 'font_charset.dart') continue; // 那是 PDF 白名单，不是界面文案
        const text = readFileSync(full, 'utf8')
          .replace(/\/\*[\s\S]*?\*\//g, '')
          .replace(/\/\/[^\n]*/g, '');
        for (const char of text) chars.add(char);
      }
    }
  };
  visit(dir);
  return chars;
}

/// 兜底字符：ASCII、数字、常用中英标点与界面符号
const SAFETY =
  ' 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' +
  '.,:;!?()[]{}<>+-*/=%￥¥$@#&_|~^"\'`\\' +
  '　·—–…“”‘’《》〈〉「」『』（）【】〔〕，。、；：？！' +
  '¥￥＄×÷＋－＝％‰°℃㎡㎥①-⑳ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ' +
  '→←↑↓⇄✓✔✗✘★☆●○■□◆◇▲△⚡💧🔥';

const charset = collectChars(join(root, 'lib'));
for (const char of SAFETY) charset.add(char);
console.log(`界面用到的字符（去重）：${charset.size}`);

let saved = 0;
for (const name of ['NotoSansSC-Regular.ttf', 'NotoSansSC-Bold.ttf']) {
  const sourcePath = join(fullDir, name);
  if (!existsSync(sourcePath)) {
    throw new Error(`缺少全量字体：${sourcePath}`);
  }
  const before = readFileSync(sourcePath);
  const after = await subsetFont(before, [...charset].join(''), {
    targetFormat: 'truetype',
  });
  writeFileSync(join(uiDir, name), after);
  saved += before.length - after.length;
  console.log(
    `${name}: ${(before.length / 1024).toFixed(0)}KB → ${(after.length / 1024).toFixed(0)}KB`,
  );
}

// 自检：全量字体里有的字形，子集不能少（emoji 之类本来就不在中文字体里，跳过）
const fullRegular = fontkit.openSync(join(fullDir, 'NotoSansSC-Regular.ttf'));
const subset = fontkit.openSync(join(uiDir, 'NotoSansSC-Regular.ttf'));
const missing = [...charset].filter(
  (char) =>
    fullRegular.hasGlyphForCodePoint(char.codePointAt(0)) &&
    !subset.hasGlyphForCodePoint(char.codePointAt(0)),
);
if (missing.length > 0) {
  throw new Error(`子集缺少界面用到的字形（前 20 个）：${missing.slice(0, 20).join('')}`);
}
for (const name of ['NotoSansSC-Regular.ttf', 'NotoSansSC-Bold.ttf']) {
  if (!fontkit.openSync(join(fullDir, name)).hasGlyphForCodePoint('鑫'.codePointAt(0))) {
    throw new Error(`PDF 全量字体被裁了：${name}`);
  }
}
console.log(
  `自检通过：界面字形齐全，PDF 全量字体未动；合计省下约 ${(saved / 1024).toFixed(0)}KB`,
);
