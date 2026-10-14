"""WOFF -> TTF 转换（无第三方依赖）。

Flutter 只能加载 sfnt 字体（ttf/otf），而 Google Fonts 对旧 UA 返回 woff。
这里按 WOFF 规范解压各表并重建 sfnt 容器，同时重算 head.checkSumAdjustment。
"""

import os
import struct
import sys
import zlib


def _checksum(data: bytes) -> int:
    if len(data) % 4:
        data = data + b"\0" * (4 - len(data) % 4)
    total = 0
    for i in range(0, len(data), 4):
        total = (total + struct.unpack(">I", data[i:i + 4])[0]) & 0xFFFFFFFF
    return total


def woff_to_ttf(src: str, dst: str) -> None:
    data = open(src, "rb").read()
    if len(data) < 44:
        raise ValueError("file too small")
    fields = struct.unpack(">IIIHHIHHIIIII", data[:44])
    signature, flavor, _length, num_tables = fields[0], fields[1], fields[2], fields[3]
    if signature != 0x774F4646:
        raise ValueError("not a woff file")

    tables = []
    pos = 44
    for _ in range(num_tables):
        tag, offset, comp_len, orig_len, _checksum_value = struct.unpack(
            ">IIIII", data[pos:pos + 20]
        )
        pos += 20
        raw = data[offset:offset + comp_len]
        if comp_len != orig_len:
            raw = zlib.decompress(raw)
        if len(raw) != orig_len:
            raise ValueError("table size mismatch")
        tables.append([tag, raw])

    tables.sort(key=lambda item: item[0])
    count = len(tables)

    search_range = 1
    entry_selector = 0
    while search_range * 2 <= count:
        search_range *= 2
        entry_selector += 1
    search_range *= 16
    range_shift = count * 16 - search_range

    out = bytearray()
    out += struct.pack(">IHHHH", flavor, count, search_range, entry_selector, range_shift)

    offset = 12 + 16 * count
    records = bytearray()
    body = bytearray()
    head_offset = None
    for tag, raw in tables:
        pad = (-len(raw)) % 4
        if tag == 0x68656164:  # 'head'
            raw = bytearray(raw)
            head_offset = offset
            raw[8:12] = b"\0\0\0\0"  # checkSumAdjustment 先清零
            raw = bytes(raw)
        records += struct.pack(">IIII", tag, _checksum(raw), offset, len(raw))
        body += raw + b"\0" * pad
        offset += len(raw) + pad

    out += records
    out += body

    if head_offset is not None:
        adjustment = (0xB1B0AFBA - _checksum(bytes(out))) & 0xFFFFFFFF
        struct.pack_into(">I", out, head_offset + 8, adjustment)

    open(dst, "wb").write(bytes(out))


if __name__ == "__main__":
    for name in os.listdir(sys.argv[1]):
        if name.endswith(".woff"):
            source = os.path.join(sys.argv[1], name)
            target = os.path.join(sys.argv[2], name.replace(".woff", ".ttf"))
            woff_to_ttf(source, target)
            print(f"{name} -> {os.path.basename(target)} "
                  f"({os.path.getsize(target) / 1024:.0f} KB)")
