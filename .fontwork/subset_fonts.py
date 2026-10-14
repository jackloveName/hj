"""把 Noto Sans SC 裁剪为「Web 友好」的子集，并生成 Dart 字符白名单。

保留范围：ASCII + GB2312 全部汉字与符号 + 常用中文标点 / 单位 / 序号，
再加项目源码里出现过的所有字符。PDF 生成前用同一份白名单做兜底替换，
避免用户输入生僻字时 dart_pdf 找不到字形而报错。
"""

import os
import re
import sys

from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

EXTRA = (
    "　·—–…“”‘’《》〈〉「」『』（）【】〔〕，。、；：？！"
    "¥￥＄×÷＋－＝％‰°℃㎡㎥①②③④⑤⑥⑦⑧⑨⑩⑪⑫→←↑↓⇄✓✔✗✘★☆●○■□"
    "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
    "0-9a-zA-Z"
)


def gb2312_chars() -> set:
    chars = set()
    for high in range(0xA1, 0xFF):
        for low in range(0xA1, 0xFF):
            try:
                chars.add(bytes([high, low]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    return chars


def source_chars() -> set:
    chars = set()
    for folder in ("lib", "test", "content"):
        base = os.path.join(ROOT, folder)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for name in filenames:
                if not name.endswith(".dart"):
                    continue
                text = open(os.path.join(dirpath, name), encoding="utf-8").read()
                chars.update(text)
    html = os.path.join(ROOT, "ui.html")
    if os.path.exists(html):
        chars.update(open(html, encoding="utf-8").read())
    return {c for c in chars if ord(c) >= 0x20}


def build_charset() -> str:
    chars = set(chr(code) for code in range(0x20, 0x7F))
    chars |= gb2312_chars()
    chars |= set(EXTRA)
    chars |= source_chars()
    return "".join(sorted(chars))


def main() -> None:
    charset = build_charset()
    work = os.path.join(ROOT, ".fontwork")
    text_file = os.path.join(work, "charset.txt")
    with open(text_file, "w", encoding="utf-8") as handle:
        handle.write(charset)

    out_dir = os.path.join(ROOT, "assets", "fonts")
    os.makedirs(out_dir, exist_ok=True)

    jobs = [
        (f"{work}/ttf/NotoSansSC-400.ttf", f"{out_dir}/NotoSansSC-Regular.ttf"),
        (f"{work}/ttf/NotoSansSC-700.ttf", f"{out_dir}/NotoSansSC-Bold.ttf"),
    ]
    for source, target in jobs:
        subset.main([
            source,
            f"--text-file={text_file}",
            f"--output-file={target}",
            "--layout-features=",
            "--no-hinting",
            "--desubroutinize",
            "--drop-tables+=DSIG",
            "--recalc-bounds",
            "--recommended-glyphs",
        ])
        print(f"{os.path.basename(target)}: "
              f"{os.path.getsize(target) / 1024:.0f} KB")

    # 拉丁与等宽字体体积很小，直接复制
    for name in ("Outfit-400", "Outfit-600", "Outfit-700",
                 "JB-Mono-400", "JB-Mono-500"):
        source = os.path.join(work, "ttf", f"{name}.ttf")
        target = os.path.join(out_dir, f"{name}.ttf")
        with open(source, "rb") as src, open(target, "wb") as dst:
            dst.write(src.read())
        print(f"{name}.ttf: {os.path.getsize(target) / 1024:.0f} KB")

    # 生成 Dart 字符白名单（用于 PDF 文本兜底）
    escaped = charset.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
    dart = (
        "// 由 .fontwork/subset_fonts.py 生成，请勿手工编辑。\n"
        "// 本文件列出内置中文字体（Noto Sans SC 子集）实际包含的字符，\n"
        "// 生成 PDF 前用它做兜底替换，避免生僻字导致报告导出失败。\n"
        "const String kFontCharset =\n"
        + _chunk_literal(escaped)
        + ";\n\n"
        "final Set<int> _fontCodePoints = kFontCharset.codeUnits.toSet();\n\n"
        "/// 把字体中不存在的字符替换为 '□'，保证 PDF 一定能生成。\n"
        "String sanitizeForPdf(String input) {\n"
        "  final buffer = StringBuffer();\n"
        "  for (final rune in input.runes) {\n"
        "    if (rune == 0x0A || rune == 0x0D || rune == 0x09) {\n"
        "      buffer.writeCharCode(rune);\n"
        "    } else if (_fontCodePoints.contains(rune)) {\n"
        "      buffer.writeCharCode(rune);\n"
        "    } else {\n"
        "      buffer.write('□');\n"
        "    }\n"
        "  }\n"
        "  return buffer.toString();\n"
        "}\n"
    )
    target = os.path.join(ROOT, "lib", "utils", "font_charset.dart")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(dart)
    print(f"charset chars={len(charset)} -> lib/utils/font_charset.dart")


def _chunk_literal(value: str, width: int = 90) -> str:
    lines = []
    for index in range(0, len(value), width):
        lines.append("    '" + value[index:index + width] + "'")
    return "\n".join(lines)


if __name__ == "__main__":
    main()
