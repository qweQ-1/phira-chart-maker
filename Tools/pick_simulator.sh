#!/usr/bin/env bash
# 挑选 runner 上可用的 iOS 模拟器，输出 -destination 参数。
# 用 UDID 而不是机型名，避免机型/OS 版本写死导致 "Unable to find a device"。
set -euo pipefail

UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
d = json.load(sys.stdin).get("devices", {})
best = None
for runtime, devices in d.items():
    if "iOS" not in runtime:
        continue
    for dev in devices:
        if not dev.get("isAvailable"):
            continue
        name = dev.get("name", "")
        # 优先 iPhone，其次 iPad；机型名里带数字越大的越新
        score = (0 if name.startswith("iPhone") else 1, name)
        if best is None or score < best[0]:
            best = (score, dev.get("udid", ""), name, runtime)
if best:
    print(best[1])
')

if [ -z "$UDID" ]; then
  echo "::error::找不到可用的 iOS 模拟器"
  exit 1
fi

echo "使用模拟器 UDID: $UDID"
echo "destination=id=$UDID"
