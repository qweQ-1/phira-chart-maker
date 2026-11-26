#!/usr/bin/env python3
"""
模拟 Phira (Rust) 的谱面包解析，验证我们导出的格式真的能被游戏读取。

校验依据（逐字段对照）：
  prpr/src/info.rs      ChartInfo 结构（serde camelCase，#[serde(default)]）
  prpr/src/fs.rs        load_info / fix_info（info.yml 优先，找不到就按扩展名猜）
  prpr/src/parse/rpe.rs RPEChart / RPEJudgeLine / RPENote / RPEEvent（必填字段严格）
  phira/src/scene/song.rs  zip 导入导出

Python 的 zipfile + yaml 严格模拟 Rust zip crate + serde_yaml 的行为。
"""
import io
import json
import sys
import zipfile

import yaml

FAIL = []
WARN = []


def fail(msg):
    FAIL.append(msg)


def warn(msg):
    WARN.append(msg)


# ---------- 1. ChartInfo (prpr/src/info.rs) ----------
CHART_INFO_STR_FIELDS = ["name", "level", "charter", "composer", "illustrator",
                         "chart", "music", "illustration", "intro"]
CHART_INFO_F32_FIELDS = ["difficulty", "previewStart", "aspectRatio", "backgroundDim",
                         "lineLength", "offset"]
CHART_INFO_BOOL_FIELDS = ["holdPartialCover", "noteUniformScale", "forceAspectRatio"]
CHART_INFO_OPT_F32 = ["previewEnd"]
CHART_INFO_OPT_STR = ["unlockVideo", "tip"]
CHART_INFO_OPT_BOOL = ["useRpe170Speed", "useAttachUiFix"]
CHART_INFO_OPT_INT = ["id", "uploader"]
CHART_FORMAT_ENUM = {"rpe", "pec", "pgr", "pbc"}


def check_chart_info(doc, label="info.yml"):
    if not isinstance(doc, dict):
        fail(f"{label}: 顶层不是 mapping，而是 {type(doc).__name__}")
        return

    unknown = set(doc) - set(
        CHART_INFO_STR_FIELDS + CHART_INFO_F32_FIELDS + CHART_INFO_BOOL_FIELDS
        + CHART_INFO_OPT_F32 + CHART_INFO_OPT_STR + CHART_INFO_OPT_BOOL + CHART_INFO_OPT_INT
        + ["format", "tags", "created", "updated", "chartUpdated"]
    )
    if unknown:
        warn(f"{label}: 有 Phira 不认识的字段 {sorted(unknown)}（会被忽略）")

    for k in CHART_INFO_STR_FIELDS:
        if k not in doc:
            continue
        if not isinstance(doc[k], str):
            fail(f"{label}: `{k}` 应该是字符串，实际是 {type(doc[k]).__name__} 值={doc[k]!r} "
                 f"→ serde 会报 invalid type")
    for k in CHART_INFO_F32_FIELDS:
        if k not in doc:
            continue
        if not isinstance(doc[k], (int, float)) or isinstance(doc[k], bool):
            fail(f"{label}: `{k}` 应该是浮点数，实际是 {type(doc[k]).__name__} 值={doc[k]!r}")
    for k in CHART_INFO_BOOL_FIELDS:
        if k not in doc:
            continue
        if not isinstance(doc[k], bool):
            fail(f"{label}: `{k}` 应该是布尔值，实际是 {type(doc[k]).__name__} 值={doc[k]!r}")
    for k in CHART_INFO_OPT_F32:
        if doc.get(k) is not None and not isinstance(doc[k], (int, float)):
            fail(f"{label}: `{k}` 应该是数字或 null")
    for k in CHART_INFO_OPT_STR:
        if doc.get(k) is not None and not isinstance(doc[k], str):
            fail(f"{label}: `{k}` 应该是字符串或 null")
    for k in CHART_INFO_OPT_BOOL:
        if doc.get(k) is not None and not isinstance(doc[k], bool):
            fail(f"{label}: `{k}` 应该是布尔或 null")
    for k in CHART_INFO_OPT_INT:
        if doc.get(k) is not None and not isinstance(doc[k], int):
            fail(f"{label}: `{k}` 应该是整数或 null")

    tags = doc.get("tags")
    if tags is not None:
        if not isinstance(tags, list):
            fail(f"{label}: `tags` 应该是数组，实际 {type(tags).__name__}")
        elif not all(isinstance(t, str) for t in tags):
            fail(f"{label}: `tags` 的元素必须都是字符串")

    fmt = doc.get("format")
    if fmt is not None:
        if fmt not in CHART_FORMAT_ENUM:
            fail(f"{label}: `format` 必须是 {sorted(CHART_FORMAT_ENUM)} 之一，实际 {fmt!r}")


# ---------- 2. RPE 谱面 (prpr/src/parse/rpe.rs) ----------
def is_triple(v):
    return isinstance(v, list) and len(v) == 3 and all(isinstance(x, int) for x in v)


def check_rpe(root, label="chart.json"):
    if not isinstance(root, dict):
        fail(f"{label}: 顶层必须是 JSON 对象")
        return

    for k in ["META", "BPMList", "judgeLineList"]:
        if k not in root:
            fail(f"{label}: 缺少必需字段 `{k}`（serde 会报 missing field）")
            return

    meta = root["META"]
    if not isinstance(meta, dict):
        fail(f"{label}: META 必须是对象")
    else:
        if "offset" not in meta:
            fail(f"{label}: META.offset 是必需字段（i32）")
        elif not isinstance(meta["offset"], int):
            fail(f"{label}: META.offset 必须是整数，实际 {type(meta['offset']).__name__}")
        rv = meta.get("RPEVersion")
        if rv is not None and not isinstance(rv, (int, str)):
            fail(f"{label}: META.RPEVersion 类型不对：{type(rv).__name__}")

    bpm_list = root["BPMList"]
    if not isinstance(bpm_list, list):
        fail(f"{label}: BPMList 必须是数组")
    else:
        if not bpm_list:
            fail(f"{label}: BPMList 不能为空（否则 BPM 无定义）")
        for i, bpm in enumerate(bpm_list):
            if not isinstance(bpm, dict):
                fail(f"{label}: BPMList[{i}] 必须是对象")
                continue
            if "bpm" not in bpm:
                fail(f"{label}: BPMList[{i}].bpm 必需")
            elif not isinstance(bpm["bpm"], (int, float)) or isinstance(bpm["bpm"], bool):
                fail(f"{label}: BPMList[{i}].bpm 必须是数字")
            elif bpm["bpm"] <= 0:
                fail(f"{label}: BPMList[{i}].bpm 必须 > 0")
            if "startTime" not in bpm:
                fail(f"{label}: BPMList[{i}].startTime 必需")
            elif not is_triple(bpm["startTime"]):
                fail(f"{label}: BPMList[{i}].startTime 必须是 [int,int,int]，实际 {bpm['startTime']!r}")

    lines = root["judgeLineList"]
    if not isinstance(lines, list):
        fail(f"{label}: judgeLineList 必须是数组")
    else:
        for li, line in enumerate(lines):
            check_judge_line(line, f"{label}: judgeLineList[{li}]")


def check_judge_line(line, label):
    if not isinstance(line, dict):
        fail(f"{label} 必须是对象")
        return

    if "Name" not in line:
        fail(f"{label}: 缺少 Name（String，必需）")
    elif not isinstance(line["Name"], str):
        fail(f"{label}: Name 必须是字符串")
    if "Texture" not in line:
        fail(f"{label}: 缺少 Texture（String，必需）")
    elif not isinstance(line["Texture"], str):
        fail(f"{label}: Texture 必须是字符串")
    if "isCover" not in line:
        fail(f"{label}: 缺少 isCover（u8，必需）")
    elif not isinstance(line["isCover"], int) or isinstance(line["isCover"], bool):
        fail(f"{label}: isCover 必须是整数")

    if "eventLayers" not in line:
        fail(f"{label}: 缺少 eventLayers（必需，可以是 null 元素）")
    else:
        layers = line["eventLayers"]
        if not isinstance(layers, list):
            fail(f"{label}: eventLayers 必须是数组")
        else:
            for ei, layer in enumerate(layers):
                if layer is None:
                    continue
                check_event_layer(layer, f"{label}.eventLayers[{ei}]")

    if "notes" in line and line["notes"] is not None:
        notes = line["notes"]
        if not isinstance(notes, list):
            fail(f"{label}: notes 必须是数组")
        else:
            for ni, note in enumerate(notes):
                check_note(note, f"{label}.notes[{ni}]")

    ext = line.get("extended")
    if ext is not None:
        check_extended(ext, f"{label}.extended")


def check_event_layer(layer, label):
    if not isinstance(layer, dict):
        fail(f"{label} 必须是对象或 null")
        return
    for key in ["speedEvents", "moveXEvents", "moveYEvents", "rotateEvents", "alphaEvents"]:
        evs = layer.get(key)
        if evs is None:
            continue
        if not isinstance(evs, list):
            fail(f"{label}.{key} 必须是数组")
            continue
        for i, e in enumerate(evs):
            check_event(e, f"{label}.{key}[{i}]")


def check_event(e, label):
    if not isinstance(e, dict):
        fail(f"{label} 必须是对象")
        return
    for k in ["start", "end"]:
        if k not in e:
            fail(f"{label}: 缺少 {k}（必需）")
        elif not isinstance(e[k], (int, float)) or isinstance(e[k], bool):
            fail(f"{label}: {k} 必须是数字")
    for k in ["startTime", "endTime"]:
        if k not in e:
            fail(f"{label}: 缺少 {k}（必需）")
        elif not is_triple(e[k]):
            fail(f"{label}: {k} 必须是 [int,int,int]，实际 {e[k]!r}")
    et = e.get("easingType")
    if et is not None and (not isinstance(et, int) or not (1 <= et <= 29)):
        fail(f"{label}: easingType 必须是 1..29 的整数，实际 {et!r}")
    el = e.get("easingLeft")
    if el is not None and not isinstance(el, (int, float)):
        fail(f"{label}: easingLeft 必须是数字")


def check_note(note, label):
    if not isinstance(note, dict):
        fail(f"{label} 必须是对象")
        return
    required = {
        "type": int, "above": int, "startTime": list, "endTime": list,
        "positionX": (int, float), "yOffset": (int, float), "alpha": int,
        "size": (int, float), "speed": (int, float), "isFake": int, "visibleTime": (int, float),
    }
    for k, typ in required.items():
        if k not in note:
            fail(f"{label}: 缺少 `{k}`（Phira 的 RPENote 没有 serde default，会解析失败）")
            continue
        v = note[k]
        if isinstance(v, bool) or not isinstance(v, typ):
            fail(f"{label}: `{k}` 类型不对，期望 {typ}，实际 {type(v).__name__} 值={v!r}")

    t = note.get("type")
    if isinstance(t, int) and t not in (1, 2, 3, 4):
        fail(f"{label}: type 必须是 1/2/3/4，实际 {t}")

    for k in ["startTime", "endTime"]:
        if k in note and not is_triple(note[k]):
            fail(f"{label}: {k} 必须是 [int,int,int]")

    if note.get("type") == 2 and is_triple(note.get("startTime")) and is_triple(note.get("endTime")):
        s = note["startTime"][0] + (note["startTime"][1] / note["startTime"][2] if note["startTime"][2] else 0)
        e = note["endTime"][0] + (note["endTime"][1] / note["endTime"][2] if note["endTime"][2] else 0)
        if e < s:
            fail(f"{label}: Hold 的 endTime({e}) 早于 startTime({s})")

    tint = note.get("tint")
    if tint is not None and not (isinstance(tint, list) and len(tint) == 3
                                 and all(isinstance(x, int) and 0 <= x <= 255 for x in tint)):
        fail(f"{label}: tint 必须是 3 个 0..255 的整数")


def check_extended(ext, label):
    if not isinstance(ext, dict):
        fail(f"{label} 必须是对象")
        return
    for key in ["scaleXEvents", "scaleYEvents"]:
        evs = ext.get(key)
        if evs is None:
            continue
        if not isinstance(evs, list):
            fail(f"{label}.{key} 必须是数组")
            continue
        for i, e in enumerate(evs):
            check_event(e, f"{label}.{key}[{i}]")

    color_events = ext.get("colorEvents")
    if color_events is not None:
        if not isinstance(color_events, list):
            fail(f"{label}.colorEvents 必须是数组")
        else:
            for i, e in enumerate(color_events):
                if not isinstance(e, dict):
                    fail(f"{label}.colorEvents[{i}] 必须是对象")
                    continue
                for k in ["start", "end"]:
                    v = e.get(k)
                    if not (isinstance(v, list) and len(v) == 3):
                        fail(f"{label}.colorEvents[{i}].{k} 必须是 [r,g,b]")


# ---------- 3. 谱面包整体 ----------
def validate_archive(path):
    print(f"\n=== 校验谱面包: {path} ===")
    try:
        zf = zipfile.ZipFile(path)
    except Exception as e:
        fail(f"不是合法 ZIP: {e}")
        return

    names = zf.namelist()
    print(f"条目 ({len(names)}): {names}")

    roots = [n for n in names if "/" not in n and not n.endswith("/")]
    nested = [n for n in names if "/" in n and not n.endswith("/")]
    if nested:
        warn(f"有嵌套路径文件 {nested[:5]}（Phira 只从根目录找 info.yml，嵌套的会找不到）")

    if "info.yml" not in names:
        fail("缺少 info.yml —— Phira 无法识别这个谱面包")
        return
    print("✅ info.yml 存在")

    raw = zf.read("info.yml")
    try:
        doc = yaml.safe_load(raw.decode("utf-8"))
    except Exception as e:
        fail(f"info.yml 不是合法 YAML: {e}")
        return
    check_chart_info(doc)
    print(f"✅ info.yml 解析成功，{len(doc)} 个字段")

    chart_name = doc.get("chart")
    chart_data = None
    if chart_name and chart_name in names:
        chart_data = zf.read(chart_name)
        print(f"✅ 按 info.yml 找到谱面文件 {chart_name}")
    else:
        for n in roots:
            if n.lower().endswith((".json", ".pec")):
                chart_name = n
                chart_data = zf.read(n)
                print(f"⚠️  info.yml 的 chart 字段无效，按扩展名兜底找到 {n}")
                break

    if chart_data is None:
        fail("找不到谱面文件（.json 或 .pec）")
        return

    fmt = doc.get("format")
    if fmt == "pec" or (chart_name or "").lower().endswith(".pec"):
        text = chart_data.decode("utf-8", errors="replace")
        lines = [l for l in text.splitlines() if l.strip() and not l.strip().startswith("#")]
        if not lines:
            fail("PEC 文件为空")
        else:
            try:
                float(lines[0].strip())
            except ValueError:
                warn(f"PEC 第一行不是 offset 数字: {lines[0]!r}")
            has_bp = any(l.startswith("bp ") for l in lines)
            if not has_bp:
                fail("PEC 缺少 `bp` BPM 行")
            note_lines = [l for l in lines if l.startswith(("n1 ", "n2 ", "n3 ", "n4 "))]
            print(f"✅ PEC 解析：{len(note_lines)} 个音符行，BPM 行 {'有' if has_bp else '无'}")
    else:
        try:
            root = json.loads(chart_data.decode("utf-8"))
        except Exception as e:
            fail(f"谱面不是合法 JSON: {e}")
            return
        check_rpe(root)
        total_notes = sum(len(l.get("notes") or []) for l in root.get("judgeLineList", []))
        print(f"✅ RPE 解析：{len(root.get('judgeLineList', []))} 判定线，{total_notes} 音符")

    for key in ["music", "illustration"]:
        val = doc.get(key)
        if val and val in names:
            size = len(zf.read(val))
            print(f"✅ {key} → {val} ({size} 字节)")
        elif val:
            fail(f"{key} 指向的 `{val}` 不在包里")

    zf.close()


def main():
    if len(sys.argv) < 2:
        print("用法: python3 verify_package.py <archive.zip> [more.zip ...]")
        sys.exit(2)

    for p in sys.argv[1:]:
        validate_archive(p)

    print("\n" + "=" * 60)
    if FAIL:
        print(f"❌ 发现 {len(FAIL)} 个致命问题：")
        for f in FAIL:
            print("  ✗", f)
    if WARN:
        print(f"⚠️  {len(WARN)} 个警告：")
        for w in WARN:
            print("  !", w)
    if not FAIL:
        print("✅ 全部通过 —— 这个包可以被 Phira 正常导入")

    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
