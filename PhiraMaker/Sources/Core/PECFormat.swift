// PEC (PhiEditer Chart) 谱面格式读写
// 规范: TeamFlos/phira-docs chart-standard/chart-format/pe
// 坐标: 文件中屏幕中心为 (1024,700)，左下角 (0,0)，右上角 (2048,1400)
// 注意: PEC 第一行是 offset（毫秒），实际计算要减去 175

import Foundation

enum PECFormat {

    // MARK: - 坐标转换

    /// 编辑器坐标（左下 -1024,-700）→ 文件坐标
    static func toFile(_ x: Double, _ y: Double) -> (Double, Double) {
        (x + 1024, y + 700)
    }

    /// 文件坐标 → 编辑器坐标
    static func toEditor(_ x: Double, _ y: Double) -> (Double, Double) {
        (x - 1024, y - 700)
    }

    // MARK: - 反序列化

    static func decode(_ data: Data) throws -> RPEChart {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw PECError.decodeFailed
        }
        var lines = text.components(separatedBy: .newlines)
        var offsetMs = 0.0
        var index = 0
        // 第一行是 offset（毫秒），允许前面有空行
        while index < lines.count {
            let t = lines[index].trimmed
            if t.isEmpty { index += 1; continue }
            offsetMs = Double(t) ?? 0
            index += 1
            break
        }

        var bpmEvents: [BPMEvent] = []
        var lines_: [JudgeLine] = []
        var notesByLine: [Int: [Note]] = [:]
        var eventsByLine: [Int: PECLineEvents] = [:]

        // 先占位 30 条判定线（PEC 最多 30 条）
        for i in 0..<30 {
            lines_.append(JudgeLine(name: "Line \(i)"))
            eventsByLine[i] = PECLineEvents()
        }

        var pendingHold: (line: Int, note: Note)?

        while index < lines.count {
            var raw = lines[index]
            index += 1
            let t = raw.trimmed
            if t.isEmpty || t.hasPrefix("#") { continue }
            let parts = t.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let tag = parts.first else { continue }

            switch tag {
            case "bp":
                // bp 起始拍 BPM
                guard parts.count >= 3, let beat = Double(parts[1]), let bpm = Double(parts[2]) else { continue }
                bpmEvents.append(BPMEvent(startTime: Beat(value: beat), bpm: bpm))

            case "cp":
                // cp 线 拍 X Y
                guard parts.count >= 4,
                      let lineIdx = Int(parts[1]), let beat = Double(parts[2]),
                      let fx = Double(parts[3]), let fy = Double(parts.count > 4 ? parts[4] : "0") else { continue }
                let (ex, ey) = toEditor(fx, fy)
                eventsByLine[lineIdx]?.move.append(PECEvent(kind: .move, line: lineIdx,
                                                            startBeat: beat, endBeat: beat,
                                                            startX: ex, startY: ey, endX: ex, endY: ey,
                                                            easing: 1))

            case "cv":
                // cv 线 拍 速度
                guard parts.count >= 4,
                      let lineIdx = Int(parts[1]), let beat = Double(parts[2]),
                      let v = Double(parts[3]) else { continue }
                eventsByLine[lineIdx]?.speed.append(PECEvent(kind: .speed, line: lineIdx,
                                                            startBeat: beat, endBeat: beat,
                                                            startX: 0, startY: 0, endX: 0, endY: 0,
                                                            value: v, easing: 1))

            case "cd":
                // cd 线 拍 旋转角
                guard parts.count >= 4,
                      let lineIdx = Int(parts[1]), let beat = Double(parts[2]),
                      let v = Double(parts[3]) else { continue }
                eventsByLine[lineIdx]?.rotate.append(PECEvent(kind: .rotate, line: lineIdx,
                                                              startBeat: beat, endBeat: beat,
                                                              startX: 0, startY: 0, endX: 0, endY: 0,
                                                              value: v, easing: 1))

            case "ca":
                // ca 线 拍 不透明度
                guard parts.count >= 4,
                      let lineIdx = Int(parts[1]), let beat = Double(parts[2]),
                      let v = Double(parts[3]) else { continue }
                eventsByLine[lineIdx]?.alpha.append(PECEvent(kind: .alpha, line: lineIdx,
                                                             startBeat: beat, endBeat: beat,
                                                             startX: 0, startY: 0, endX: 0, endY: 0,
                                                             value: v, easing: 1))

            case "cm":
                // cm 线 起始拍 结束拍 终点X 终点Y 缓动
                guard parts.count >= 6,
                      let lineIdx = Int(parts[1]), let sb = Double(parts[2]), let eb = Double(parts[3]),
                      let fx = Double(parts[4]), let fy = Double(parts[5]) else { continue }
                let easing = parts.count > 6 ? (Int(parts[6]) ?? 1) : 1
                let (ex, ey) = toEditor(fx, fy)
                let startX = eventsByLine[lineIdx]?.lastMoveX ?? ex
                let startY = eventsByLine[lineIdx]?.lastMoveY ?? ey
                eventsByLine[lineIdx]?.move.append(PECEvent(kind: .move, line: lineIdx,
                                                            startBeat: sb, endBeat: eb,
                                                            startX: startX, startY: startY,
                                                            endX: ex, endY: ey, easing: easing))

            case "cr":
                // cr 线 起始拍 结束拍 终点旋转角 缓动
                guard parts.count >= 5,
                      let lineIdx = Int(parts[1]), let sb = Double(parts[2]), let eb = Double(parts[3]),
                      let v = Double(parts[4]) else { continue }
                let easing = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1
                eventsByLine[lineIdx]?.rotate.append(PECEvent(kind: .rotate, line: lineIdx,
                                                              startBeat: sb, endBeat: eb,
                                                              startX: 0, startY: 0, endX: 0, endY: 0,
                                                              value: v, easing: easing))

            case "cf":
                // cf 线 起始拍 结束拍 终点不透明度
                guard parts.count >= 5,
                      let lineIdx = Int(parts[1]), let sb = Double(parts[2]), let eb = Double(parts[3]),
                      let v = Double(parts[4]) else { continue }
                eventsByLine[lineIdx]?.alpha.append(PECEvent(kind: .alpha, line: lineIdx,
                                                             startBeat: sb, endBeat: eb,
                                                             startX: 0, startY: 0, endX: 0, endY: 0,
                                                             value: v, easing: 1))

            case "n1", "n2", "n3", "n4":
                // n类型 线 拍 [结束拍] X 是否从下方 是否假note
                guard parts.count >= 4, let lineIdx = Int(parts[1]) else { continue }
                let type = NoteType(rawValue: Int(tag.dropFirst()) ?? 1) ?? .tap
                var beat = 0.0, endBeat = 0.0, fx = 0.0, below = 1, fake = 0
                if type == .hold {
                    guard parts.count >= 5,
                          let b = Double(parts[2]), let eb = Double(parts[3]) else { continue }
                    beat = b; endBeat = eb
                    fx = Double(parts.count > 4 ? parts[4] : "0") ?? 0
                    below = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1
                    fake = parts.count > 6 ? (Int(parts[6]) ?? 0) : 0
                } else {
                    guard let b = Double(parts[2]) else { continue }
                    beat = b; endBeat = b
                    fx = Double(parts.count > 3 ? parts[3] : "0") ?? 0
                    below = parts.count > 4 ? (Int(parts[4]) ?? 1) : 1
                    fake = parts.count > 5 ? (Int(parts[5]) ?? 0) : 0
                }
                let (ex, _) = toEditor(fx, 0)
                var note = Note(type: type,
                                startTime: Beat(value: beat),
                                endTime: Beat(value: endBeat),
                                positionX: ex)
                note.above = below == 2 ? 0 : 1
                note.isFake = fake

                // 后续行：# 速度倍率，& 宽度倍率
                while index < lines.count {
                    let nxt = lines[index].trimmed
                    if nxt.hasPrefix("#") {
                        let valueText = String(nxt.dropFirst()).trimmed
                        if let v = Double(valueText) { note.speed = v }
                        index += 1
                        continue
                    }
                    if nxt.hasPrefix("&") {
                        let valueText = String(nxt.dropFirst()).trimmed
                        if let v = Double(valueText) { note.size = v }
                        index += 1
                        continue
                    }
                    break
                }

                if type == .hold {
                    // PEC 的 Hold 分两行写：n2 行给开始拍和结束拍，需要读取中间的行
                    // 实际 PEC hold 格式：n2 线 开始拍 结束拍 X ...
                    pendingHold = (lineIdx, note)
                }
                notesByLine[lineIdx, default: []].append(note)

            default:
                continue
            }
        }

        if bpmEvents.isEmpty {
            bpmEvents = [BPMEvent(startTime: Beat(i: 0), bpm: 120)]
        }
        bpmEvents.sort { $0.startTime.value < $1.startTime.value }

        // 把 PEC 事件转成 RPE 事件层
        for (lineIdx, evs) in eventsByLine {
            guard lineIdx >= 0 && lineIdx < lines_.count else { continue }
            var layer = EventLayer()
            for e in evs.move {
                let sb = Beat(value: e.startBeat), eb = Beat(value: e.endBeat)
                if e.startBeat == e.endBeat {
                    // 瞬时事件 → 长度为 0 的常量段
                    layer.moveXEvents.append(LineEvent(startTime: sb, endTime: eb, start: e.startX, end: e.startX))
                    layer.moveYEvents.append(LineEvent(startTime: sb, endTime: eb, start: e.startY, end: e.startY))
                } else {
                    layer.moveXEvents.append(LineEvent(startTime: sb, endTime: eb, start: e.startX, end: e.endX, easingType: e.easing))
                    layer.moveYEvents.append(LineEvent(startTime: sb, endTime: eb, start: e.startY, end: e.endY, easingType: e.easing))
                }
            }
            for e in evs.speed {
                let sb = Beat(value: e.startBeat), eb = Beat(value: e.endBeat)
                layer.speedEvents.append(LineEvent(startTime: sb, endTime: eb, start: e.value, end: e.value))
            }
            for e in evs.rotate {
                let sb = Beat(value: e.startBeat), eb = Beat(value: e.endBeat)
                if e.startBeat == e.endBeat {
                    layer.rotateEvents.append(LineEvent(startTime: sb, endTime: eb, start: e.value, end: e.value))
                } else {
                    layer.rotateEvents.append(LineEvent(startTime: sb, endTime: eb, start: 0, end: e.value, easingType: e.easing))
                }
            }
            for e in evs.alpha {
                let sb = Beat(value: e.startBeat), eb = Beat(value: e.endBeat)
                if e.startBeat == e.endBeat {
                    layer.alphaEvents.append(LineEvent(startTime: sb, endTime: eb, start: e.value, end: e.value))
                } else {
                    layer.alphaEvents.append(LineEvent(startTime: sb, endTime: eb, start: 255, end: e.value))
                }
            }
            lines_[lineIdx].eventLayers = [layer]
        }

        for (lineIdx, notes) in notesByLine {
            guard lineIdx >= 0 && lineIdx < lines_.count else { continue }
            lines_[lineIdx].notes = notes
        }

        var meta = ChartMeta()
        meta.RPEVersion = 160
        meta.offset = Int((offsetMs - 175).rounded())

        return RPEChart(meta: meta, bpmList: bpmEvents, judgeLineList: lines_)
    }

    // MARK: - 序列化

    static func encode(_ chart: RPEChart) throws -> Data {
        var out = ""
        // PEC offset 是毫秒，且实际要加回 175
        out += "\(Int((Double(chart.META.offset) + 175).rounded()))\n"

        for bpm in chart.BPMList {
            out += "bp \(fmt(bpm.startTime.value)) \(fmt(bpm.bpm))\n"
        }

        for (idx, line) in chart.judgeLineList.enumerated() {
            guard let layer = line.eventLayers.first else { continue }
            var lastMoveX = 0.0, lastMoveY = 0.0

            for e in layer.moveXEvents {
                // 找到同起止时间的 Y 事件配对
                let pair = layer.moveYEvents.first { $0.startTime == e.startTime && $0.endTime == e.endTime }
                let ey = pair?.start ?? lastMoveY
                let eyEnd = pair?.end ?? ey
                let (fx, fy) = toFile(e.start, ey)
                let (fxe, fye) = toFile(e.end, eyEnd)
                if e.startTime.value == e.endTime.value {
                    out += "cp \(idx) \(fmt(e.startTime.value)) \(fmt(fx)) \(fmt(fy))\n"
                    lastMoveX = e.start; lastMoveY = ey
                } else {
                    out += "cm \(idx) \(fmt(e.startTime.value)) \(fmt(e.endTime.value)) \(fmt(fxe)) \(fmt(fye)) \(e.easingType)\n"
                    lastMoveX = e.end; lastMoveY = eyEnd
                }
            }
            for e in layer.rotateEvents {
                if e.startTime.value == e.endTime.value {
                    out += "cd \(idx) \(fmt(e.startTime.value)) \(fmt(e.start))\n"
                } else {
                    out += "cr \(idx) \(fmt(e.startTime.value)) \(fmt(e.endTime.value)) \(fmt(e.end)) \(e.easingType)\n"
                }
            }
            for e in layer.alphaEvents {
                if e.startTime.value == e.endTime.value {
                    out += "ca \(idx) \(fmt(e.startTime.value)) \(fmt(e.start))\n"
                } else {
                    out += "cf \(idx) \(fmt(e.startTime.value)) \(fmt(e.endTime.value)) \(fmt(e.end))\n"
                }
            }
            for e in layer.speedEvents {
                out += "cv \(idx) \(fmt(e.startTime.value)) \(fmt(e.start))\n"
            }

            for note in line.notes {
                let below = note.above == 1 ? 1 : 2
                if note.type == .hold {
                    let (fx, _) = toFile(note.positionX, 0)
                    out += "n2 \(idx) \(fmt(note.startTime.value)) \(fmt(note.endTime.value)) \(fmt(fx)) \(below) \(note.isFake)\n"
                } else {
                    let (fx, _) = toFile(note.positionX, 0)
                    out += "n\(note.type.rawValue) \(idx) \(fmt(note.startTime.value)) \(fmt(fx)) \(below) \(note.isFake)\n"
                }
                out += "# \(fmt(note.speed))\n"
                out += "& \(fmt(note.size))\n"
            }
        }

        guard let data = out.data(using: .utf8) else { throw PECError.encodeFailed }
        return data
    }

    /// 数字格式化：最多 3 位小数，去掉尾随 0
    static func fmt(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.contains(".") && s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if s == "-0" { s = "0" }
        return s
    }
}

// MARK: - 内部辅助

enum PECError: Error {
    case decodeFailed
    case encodeFailed
}

private enum PECEventKind {
    case move, speed, rotate, alpha
}

private struct PECEvent {
    var kind: PECEventKind
    var line: Int
    var startBeat: Double
    var endBeat: Double
    var startX: Double = 0
    var startY: Double = 0
    var endX: Double = 0
    var endY: Double = 0
    var value: Double = 0
    var easing: Int = 1
}

private struct PECLineEvents {
    var move: [PECEvent] = []
    var speed: [PECEvent] = []
    var rotate: [PECEvent] = []
    var alpha: [PECEvent] = []
    var lastMoveX: Double = 0
    var lastMoveY: Double = 0
}
