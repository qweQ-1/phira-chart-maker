#!/usr/bin/env python3
"""
Python 版的 Swift 导出逻辑镜像 —— 用来验证「格式设计」本身是正确的。
生成的 zip 会交给 verify_package.py 做严格校验（模拟 Phira 的 Rust 解析器）。

这不是最终产物，只是证明格式方案可行。
"""
import json
import struct
import sys
import zlib
import zipfile
from io import BytesIO

# ---------- YAML（镜像 Yaml.swift） ----------


def yaml_quote(s):
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def format_float(v):
    if v == int(v) and abs(v) < 1e9:
        return str(int(v))
    s = f"{v:.6f}"
    while "." in s and s.endswith("0"):
        s = s[:-1]
    if s.endswith("."):
        s = s[:-1]
    return s


def dump_info_yml(info):
    """镜像 InfoYAML.dump"""
    entries = []
    if info.get("id") is not None:
        entries.append(("id", ("raw", str(info["id"]))))
    if info.get("uploader") is not None:
        entries.append(("uploader", ("raw", str(info["uploader"]))))

    entries.append(("name", ("scalar", info["name"])))
    entries.append(("difficulty", ("raw", format_float(info["difficulty"]))))
    entries.append(("level", ("scalar", info["level"])))
    entries.append(("charter", ("scalar", info["charter"])))
    entries.append(("composer", ("scalar", info["composer"])))
    entries.append(("illustrator", ("scalar", info["illustrator"])))

    entries.append(("chart", ("scalar", info["chart"])))
    if info.get("format") is not None:
        entries.append(("format", ("scalar", info["format"])))
    entries.append(("music", ("scalar", info["music"])))
    entries.append(("illustration", ("scalar", info["illustration"])))
    if info.get("unlockVideo") is not None:
        entries.append(("unlockVideo", ("scalar", info["unlockVideo"])))

    entries.append(("previewStart", ("raw", format_float(info["previewStart"]))))
    if info.get("previewEnd") is not None:
        entries.append(("previewEnd", ("raw", format_float(info["previewEnd"]))))
    entries.append(("aspectRatio", ("raw", format_float(info["aspectRatio"]))))
    entries.append(("backgroundDim", ("raw", format_float(info["backgroundDim"]))))
    entries.append(("lineLength", ("raw", format_float(info["lineLength"]))))
    entries.append(("offset", ("raw", format_float(info["offset"]))))
    if info.get("tip") is not None:
        entries.append(("tip", ("scalar", info["tip"])))

    tags = info.get("tags", [])
    if tags:
        entries.append(("tags", ("list", tags)))
    else:
        entries.append(("tags", ("emptylist", None)))

    entries.append(("intro", ("scalar", info["intro"])))
    entries.append(("holdPartialCover", ("raw", "true" if info["holdPartialCover"] else "false")))
    entries.append(("noteUniformScale", ("raw", "true" if info["noteUniformScale"] else "false")))
    entries.append(("forceAspectRatio", ("raw", "true" if info["forceAspectRatio"] else "false")))

    out = []
    for key, (kind, val) in entries:
        if kind == "scalar":
            out.append(f"{key}: {yaml_quote(val)}")
        elif kind == "raw":
            out.append(f"{key}: {val}")
        elif kind == "list":
            out.append(f"{key}:")
            for item in val:
                out.append(f"- {yaml_quote(item)}")
        elif kind == "emptylist":
            out.append(f"{key}: []")
    return "\n".join(out) + "\n"


# ---------- RPE 谱面（镜像 RPEFormat.encode） ----------
def beat_arr(b):
    return [b[0], b[1], b[2]]


def encode_rpe(chart):
    meta = chart["META"]
    root = {
        "META": {
            "RPEVersion": meta["RPEVersion"],
            "id": meta["id"],
            "name": meta["name"],
            "level": meta["level"],
            "charter": meta["charter"],
            "composer": meta["composer"],
            "illustration": meta["illustration"],
            "song": meta["song"],
            "background": meta["background"],
            "offset": meta["offset"],
        },
        "BPMList": [{"startTime": beat_arr(b["startTime"]), "bpm": b["bpm"]} for b in chart["BPMList"]],
        "judgeLineList": [],
    }

    for line in chart["judgeLineList"]:
        d = {
            "Name": line["Name"],
            "Texture": line["Texture"],
            "father": line["father"],
            "isCover": line["isCover"],
            "zOrder": line["zOrder"],
            "bpmfactor": line["bpmfactor"],
            "rotateWithFather": line.get("rotateWithFather", True),
            "eventLayers": [],
        }
        for layer in line["eventLayers"]:
            l = {}
            for src, dst in [("speedEvents", "speedEvents"), ("moveXEvents", "moveXEvents"),
                             ("moveYEvents", "moveYEvents"), ("rotateEvents", "rotateEvents"),
                             ("alphaEvents", "alphaEvents")]:
                if layer.get(src):
                    l[dst] = [encode_event(e) for e in layer[src]]
            d["eventLayers"].append(l)

        if line.get("extended"):
            ext = line["extended"]
            e = {}
            if ext.get("colorEvents"):
                e["colorEvents"] = [dict(encode_event(ev), start=ev["start"], end=ev["end"])
                                    for ev in ext["colorEvents"]]
            if ext.get("scaleXEvents"):
                e["scaleXEvents"] = [encode_event(ev) for ev in ext["scaleXEvents"]]
            if ext.get("scaleYEvents"):
                e["scaleYEvents"] = [encode_event(ev) for ev in ext["scaleYEvents"]]
            if ext.get("textEvents"):
                e["textEvents"] = [dict(encode_event(ev), start=ev["start"], end=ev["end"])
                                   for ev in ext["textEvents"]]
            if e:
                d["extended"] = e

        d["notes"] = [encode_note(n) for n in line.get("notes", [])]
        root["judgeLineList"].append(d)

    return json.dumps(root, ensure_ascii=False, indent=2, sort_keys=True).encode()


def encode_event(e):
    return {
        "startTime": beat_arr(e["startTime"]),
        "endTime": beat_arr(e["endTime"]),
        "start": e["start"],
        "end": e["end"],
        "easingType": e.get("easingType", 1),
        "easingLeft": e.get("easingLeft", 0),
        "easingRight": e.get("easingRight", 1),
        "linkgroup": e.get("linkgroup", 0),
    }


def encode_note(n):
    d = {
        "type": n["type"],
        "above": n.get("above", 1),
        "startTime": beat_arr(n["startTime"]),
        "endTime": beat_arr(n.get("endTime", n["startTime"])),
        "positionX": n.get("positionX", 0),
        "size": n.get("size", 1),
        "speed": n.get("speed", 1),
        "yOffset": n.get("yOffset", 0),
        "alpha": n.get("alpha", 255),
        "isFake": n.get("isFake", 0),
        "visibleTime": n.get("visibleTime", 999999),
    }
    if n.get("tint"):
        d["tint"] = n["tint"]
    return d


# ---------- ZIP（镜像 ZipArchive.create，裸 deflate） ----------
def deflate_raw(data):
    c = zlib.compressobj(6, zlib.DEFLATED, -15)
    return c.compress(data) + c.flush()


def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def create_zip(entries):
    """entries: [(name, data)]"""
    out = bytearray()
    central = bytearray()
    offset = 0

    for name, data in entries:
        name_bytes = name.encode("utf-8")
        if not data:
            method = 0
            payload = b""
        else:
            compressed = deflate_raw(data)
            if len(compressed) < len(data):
                method, payload = 8, compressed
            else:
                method, payload = 0, data

        crc = crc32(data)
        local = struct.pack(
            "<IHHHHHIIIHH",
            0x04034B50, 20, 0x0800, method, 0, 0x21,
            crc, len(payload), len(data), len(name_bytes), 0,
        ) + name_bytes + payload
        out += local

        central += struct.pack(
            "<IHHHHHHIIIHHHHHII",
            0x02014B50, 0x031E, 20, 0x0800, method, 0, 0x21,
            crc, len(payload), len(data), len(name_bytes), 0, 0, 0, 0, 0x81A40000, offset,
        ) + name_bytes
        offset += len(local)

    eocd = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries),
                       len(central), offset, 0)
    return bytes(out + central + eocd)


# ---------- 构造测试谱面 ----------
def build_sample():
    def B(i, n=0, d=1):
        return [i, n, d]

    info = {
        "name": "测试曲目 Test",
        "difficulty": 15,
        "level": "IN Lv.15",
        "charter": "测试谱师",
        "composer": "测试曲师",
        "illustrator": "测试画师",
        "chart": "chart.json",
        "format": "rpe",
        "music": "song.ogg",
        "illustration": "background.png",
        "previewStart": 30,
        "aspectRatio": 16 / 9,
        "backgroundDim": 0.6,
        "lineLength": 6,
        "offset": 0.12,
        "tags": ["测试", "demo"],
        "intro": "由 Phira 谱面工坊生成",
        "holdPartialCover": False,
        "noteUniformScale": False,
        "forceAspectRatio": False,
    }

    chart = {
        "META": {
            "RPEVersion": 160,
            "id": "",
            "name": info["name"],
            "level": info["level"],
            "charter": info["charter"],
            "composer": info["composer"],
            "illustration": info["illustrator"],
            "song": "song.ogg",
            "background": "background.png",
            "offset": 120,
        },
        "BPMList": [
            {"startTime": B(0), "bpm": 180},
            {"startTime": B(32), "bpm": 90},
        ],
        "judgeLineList": [
            {
                "Name": "Line 0",
                "Texture": "line.png",
                "father": -1,
                "isCover": 1,
                "zOrder": 0,
                "bpmfactor": 1.0,
                "eventLayers": [
                    {
                        "moveXEvents": [
                            {"startTime": B(0), "endTime": B(4), "start": -200.0, "end": 200.0, "easingType": 4},
                            {"startTime": B(8), "endTime": B(8), "start": 0.0, "end": 0.0, "easingType": 1},
                        ],
                        "moveYEvents": [
                            {"startTime": B(0), "endTime": B(4), "start": 0.0, "end": -100.0, "easingType": 2},
                        ],
                        "rotateEvents": [
                            {"startTime": B(0), "endTime": B(16), "start": 0.0, "end": 360.0, "easingType": 1},
                        ],
                        "alphaEvents": [
                            {"startTime": B(0), "endTime": B(0), "start": 255.0, "end": 255.0, "easingType": 1},
                        ],
                        "speedEvents": [
                            {"startTime": B(0), "endTime": B(32), "start": 1.0, "end": 1.0, "easingType": 1},
                        ],
                    }
                ],
                "extended": {
                    "colorEvents": [
                        {"startTime": B(0), "endTime": B(8), "start": [255, 255, 255],
                         "end": [255, 100, 200], "easingType": 1},
                    ]
                },
                "notes": [
                    {"type": 1, "startTime": B(0), "endTime": B(0), "positionX": -300},
                    {"type": 1, "startTime": B(1), "endTime": B(1), "positionX": 0},
                    {"type": 2, "startTime": B(2), "endTime": B(4), "positionX": 200},
                    {"type": 3, "startTime": B(5), "endTime": B(5), "positionX": -150},
                    {"type": 4, "startTime": B(6, 1, 2), "endTime": B(6, 1, 2), "positionX": 400, "speed": 1.5},
                    {"type": 1, "startTime": B(9), "endTime": B(9), "positionX": 0, "isFake": 1},
                ],
            },
            {
                "Name": "Line 1",
                "Texture": "line.png",
                "father": 0,
                "isCover": 0,
                "zOrder": 1,
                "bpmfactor": 1.0,
                "eventLayers": [{}],
                "notes": [
                    {"type": 1, "startTime": B(12), "endTime": B(12), "positionX": 250, "alpha": 200},
                ],
            },
        ],
    }

    entries = [
        ("info.yml", dump_info_yml(info).encode("utf-8")),
        ("chart.json", encode_rpe(chart)),
        ("song.ogg", b"OggS" + b"\x00" * 2000),
        ("background.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * 500),
    ]
    return create_zip(entries)


if __name__ == "__main__":
    data = build_sample()
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sample_chart.zip"
    with open(out, "wb") as f:
        f.write(data)
    print(f"生成 {out} ({len(data)} 字节)")

    # 自检：Python 标准库能读
    with zipfile.ZipFile(out) as zf:
        bad = zf.testzip()
        if bad:
            print(f"❌ 损坏条目: {bad}")
        else:
            print("✅ Python zipfile 校验通过，条目:", zf.namelist())
