#!/usr/bin/env bash
# 挑选 runner 上可用、且与当前 Xcode SDK 匹配的 iOS 模拟器。
# 输出两行：
#   id=<UDID>
#   destination=id=<UDID>
#
# 踩过的坑：
#  - 写死机型名（如 iPhone 16）→ runner 上没有该机型就报 "Unable to find a device"
#  - 写死 OS 版本 → 与 Xcode SDK 不匹配时 actool 报
#    "No simulator runtime version ... available to use with iphonesimulator SDK version"
# 所以这里一律用 UDID，并且从 runtime 列表里挑与 SDK 主版本一致的那个。
set -euo pipefail

OUT=$(xcrun simctl list devices available --json | python3 -c '
import json, sys, subprocess, re

# 当前 Xcode 的 SDK 主版本（形如 18.0）
try:
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
        text=True).strip()
except Exception:
    sdk = ""
sdk_major = sdk.split(".")[0] if sdk else ""

d = json.load(sys.stdin).get("devices", {})

def runtime_major(runtime):
    # 形如 "com.apple.CoreSimulator.SimRuntime.iOS-18-1" → "18"
    m = re.search(r"iOS-(\d+)", runtime)
    return m.group(1) if m else ""

best = None
for runtime, devices in d.items():
    if "iOS" not in runtime:
        continue
    rmaj = runtime_major(runtime)
    # 优先选与 SDK 主版本一致的 runtime
    if sdk_major and rmaj and rmaj != sdk_major:
        continue
    for dev in devices:
        if not dev.get("isAvailable"):
            continue
        name = dev.get("name", "")
        score = (0 if name.startswith("iPhone") else 1, name)
        if best is None or score < best[0]:
            best = (score, dev.get("udid", ""), name, runtime)

# 兜底：没匹配到就用任意可用的 iPhone
if best is None:
    for runtime, devices in d.items():
        if "iOS" not in runtime:
            continue
        for dev in devices:
            if not dev.get("isAvailable"):
                continue
            name = dev.get("name", "")
            score = (0 if name.startswith("iPhone") else 1, name)
            if best is None or score < best[0]:
                best = (score, dev.get("udid", ""), name, runtime)

if best:
    print("id=" + best[1])
    print("destination=id=" + best[1])
    print("device=" + best[2])
    print("runtime=" + best[3])
')

echo "$OUT"

if ! grep -q '^id=' <<< "$OUT"; then
  echo "::error::找不到可用的 iOS 模拟器"
  exit 1
fi
