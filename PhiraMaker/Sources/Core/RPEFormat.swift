// RPE (Rhythm Player Editor) 谱面格式读写
// 规范: TeamFlos/phira-docs chart-standard/chart-format/rpe
// 校验: TeamFlos/phira prpr/src/parse/rpe.rs

import Foundation

enum RPEFormat {

    // MARK: - 序列化

    static func encode(_ chart: RPEChart) throws -> Data {
        var root: [String: Any] = [:]

        // META
        var meta: [String: Any] = [:]
        meta["RPEVersion"] = chart.META.RPEVersion
        meta["id"] = chart.META.id
        meta["name"] = chart.META.name
        meta["level"] = chart.META.level
        meta["charter"] = chart.META.charter
        meta["composer"] = chart.META.composer
        meta["illustration"] = chart.META.illustration
        meta["song"] = chart.META.song
        meta["background"] = chart.META.background
        meta["offset"] = chart.META.offset
        root["META"] = meta

        // BPMList
        root["BPMList"] = chart.BPMList.map { bpm in
            ["startTime": bpm.startTime.toJSONArray(), "bpm": bpm.bpm] as [String: Any]
        }

        // judgeLineList
        root["judgeLineList"] = chart.judgeLineList.map { line in
            var dict: [String: Any] = [:]
            dict["Name"] = line.name
            dict["Texture"] = line.texture
            dict["father"] = line.father
            dict["isCover"] = line.isCover
            dict["zOrder"] = line.zOrder
            dict["bpmfactor"] = line.bpmfactor
            dict["rotateWithFather"] = line.rotateWithFather
            dict["eventLayers"] = line.eventLayers.map { layer in
                var l: [String: Any] = [:]
                // 没有事件就不写该字段（Phira 约定：无事件则无字段，而非空数组）
                if !layer.speedEvents.isEmpty { l["speedEvents"] = layer.speedEvents.map(encodeLineEvent) }
                if !layer.moveXEvents.isEmpty { l["moveXEvents"] = layer.moveXEvents.map(encodeLineEvent) }
                if !layer.moveYEvents.isEmpty { l["moveYEvents"] = layer.moveYEvents.map(encodeLineEvent) }
                if !layer.rotateEvents.isEmpty { l["rotateEvents"] = layer.rotateEvents.map(encodeLineEvent) }
                if !layer.alphaEvents.isEmpty { l["alphaEvents"] = layer.alphaEvents.map(encodeLineEvent) }
                return l
            }
            if let ext = line.extended, hasExtendedContent(ext) {
                var e: [String: Any] = [:]
                if !ext.colorEvents.isEmpty { e["colorEvents"] = ext.colorEvents.map(encodeColorEvent) }
                if !ext.scaleXEvents.isEmpty { e["scaleXEvents"] = ext.scaleXEvents.map(encodeLineEvent) }
                if !ext.scaleYEvents.isEmpty { e["scaleYEvents"] = ext.scaleYEvents.map(encodeLineEvent) }
                if !ext.textEvents.isEmpty { e["textEvents"] = ext.textEvents.map(encodeTextEvent) }
                dict["extended"] = e
            }
            dict["notes"] = line.notes.map(encodeNote)
            return dict
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data
    }

    private static func hasExtendedContent(_ ext: ExtendedEvents) -> Bool {
        !ext.colorEvents.isEmpty || !ext.scaleXEvents.isEmpty || !ext.scaleYEvents.isEmpty || !ext.textEvents.isEmpty
    }

    private static func encodeLineEvent(_ e: LineEvent) -> [String: Any] {
        var d: [String: Any] = [:]
        d["startTime"] = e.startTime.toJSONArray()
        d["endTime"] = e.endTime.toJSONArray()
        d["start"] = e.start
        d["end"] = e.end
        d["easingType"] = e.easingType
        d["easingLeft"] = e.easingLeft
        d["easingRight"] = e.easingRight
        d["linkgroup"] = e.linkgroup
        return d
    }

    private static func encodeColorEvent(_ e: ColorEvent) -> [String: Any] {
        var d: [String: Any] = [:]
        d["startTime"] = e.startTime.toJSONArray()
        d["endTime"] = e.endTime.toJSONArray()
        d["start"] = e.start
        d["end"] = e.end
        d["easingType"] = e.easingType
        d["easingLeft"] = e.easingLeft
        d["easingRight"] = e.easingRight
        d["linkgroup"] = e.linkgroup
        return d
    }

    private static func encodeTextEvent(_ e: TextEvent) -> [String: Any] {
        var d: [String: Any] = [:]
        d["startTime"] = e.startTime.toJSONArray()
        d["endTime"] = e.endTime.toJSONArray()
        d["start"] = e.start
        d["end"] = e.end
        d["easingType"] = e.easingType
        d["easingLeft"] = e.easingLeft
        d["easingRight"] = e.easingRight
        d["linkgroup"] = e.linkgroup
        return d
    }

    private static func encodeNote(_ n: Note) -> [String: Any] {
        var d: [String: Any] = [:]
        d["type"] = n.type.rawValue
        d["above"] = n.above
        d["startTime"] = n.startTime.toJSONArray()
        d["endTime"] = n.endTime.toJSONArray()
        d["positionX"] = n.positionX
        d["size"] = n.size
        d["speed"] = n.speed
        d["yOffset"] = n.yOffset
        d["alpha"] = n.alpha
        d["isFake"] = n.isFake
        d["visibleTime"] = n.visibleTime
        if let tint = n.tint { d["tint"] = tint }
        if let t = n.tintHitEffects { d["tintHitEffects"] = t }
        if let ja = n.judgeArea { d["judgeArea"] = ja }
        return d
    }

    // MARK: - 反序列化

    static func decode(_ data: Data) throws -> RPEChart {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // META
        var meta = ChartMeta()
        if let m = root["META"] as? [String: Any] {
            if let v = m["RPEVersion"] as? Int { meta.RPEVersion = v }
            else if let s = m["RPEVersion"] as? String { meta.RPEVersion = Int(s) ?? 160 }
            if let v = m["id"] as? String { meta.id = v }
            if let v = m["name"] as? String { meta.name = v }
            if let v = m["level"] as? String { meta.level = v }
            if let v = m["charter"] as? String { meta.charter = v }
            if let v = m["composer"] as? String { meta.composer = v }
            if let v = m["illustration"] as? String { meta.illustration = v }
            if let v = m["song"] as? String { meta.song = v }
            if let v = m["background"] as? String { meta.background = v }
            if let v = m["offset"] as? Int { meta.offset = v }
            else if let v = m["offset"] as? Double { meta.offset = Int(v) }
        }

        // BPMList
        var bpmList: [BPMEvent] = []
        if let arr = root["BPMList"] as? [[String: Any]] {
            for item in arr {
                let bpm = (item["bpm"] as? Double) ?? (item["bpm"] as? Int).map(Double.init) ?? 120
                let start = decodeBeat(item["startTime"])
                bpmList.append(BPMEvent(startTime: start, bpm: bpm))
            }
        }
        if bpmList.isEmpty {
            bpmList = [BPMEvent(startTime: Beat(i: 0), bpm: 120)]
        }
        bpmList.sort { $0.startTime.value < $1.startTime.value }

        // judgeLineList
        var lines: [JudgeLine] = []
        if let arr = root["judgeLineList"] as? [[String: Any]] {
            for item in arr {
                lines.append(decodeJudgeLine(item))
            }
        }

        return RPEChart(meta: meta, bpmList: bpmList, judgeLineList: lines)
    }

    private static func decodeBeat(_ any: Any?) -> Beat {
        if let arr = any as? [Int] { return Beat(jsonArray: arr) }
        if let arr = any as? [Any] {
            let ints = arr.compactMap { $0 as? Int }
            return Beat(jsonArray: ints)
        }
        return Beat(i: 0)
    }

    private static func decodeJudgeLine(_ item: [String: Any]) -> JudgeLine {
        var line = JudgeLine()
        if let v = item["Name"] as? String { line.name = v }
        if let v = item["Texture"] as? String { line.texture = v }
        if let v = item["father"] as? Int { line.father = v }
        if let v = item["isCover"] as? Int { line.isCover = v }
        if let v = item["zOrder"] as? Int { line.zOrder = v }
        if let v = item["bpmfactor"] as? Double { line.bpmfactor = v }
        if let v = item["rotateWithFather"] as? Bool { line.rotateWithFather = v }

        // eventLayers
        var layers: [EventLayer] = []
        if let arr = item["eventLayers"] as? [Any] {
            for layerAny in arr {
                guard let l = layerAny as? [String: Any] else {
                    layers.append(EventLayer())
                    continue
                }
                var layer = EventLayer()
                layer.speedEvents = decodeLineEvents(l["speedEvents"])
                layer.moveXEvents = decodeLineEvents(l["moveXEvents"])
                layer.moveYEvents = decodeLineEvents(l["moveYEvents"])
                layer.rotateEvents = decodeLineEvents(l["rotateEvents"])
                layer.alphaEvents = decodeLineEvents(l["alphaEvents"])
                layers.append(layer)
            }
        }
        line.eventLayers = layers.isEmpty ? [EventLayer()] : layers

        // extended
        if let e = item["extended"] as? [String: Any] {
            var ext = ExtendedEvents()
            ext.colorEvents = decodeColorEvents(e["colorEvents"])
            ext.scaleXEvents = decodeLineEvents(e["scaleXEvents"])
            ext.scaleYEvents = decodeLineEvents(e["scaleYEvents"])
            ext.textEvents = decodeTextEvents(e["textEvents"])
            if hasExtendedContent(ext) { line.extended = ext }
        }

        // notes
        var notes: [Note] = []
        if let arr = item["notes"] as? [[String: Any]] {
            for n in arr { notes.append(decodeNote(n)) }
        }
        line.notes = notes
        return line
    }

    private static func decodeLineEvents(_ any: Any?) -> [LineEvent] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let start = d["start"] as? Double, let end = d["end"] as? Double else { return nil }
            var e = LineEvent(startTime: decodeBeat(d["startTime"]),
                              endTime: decodeBeat(d["endTime"]),
                              start: start,
                              end: end)
            if let v = d["easingType"] as? Int { e.easingType = v }
            if let v = d["easingLeft"] as? Double { e.easingLeft = v }
            if let v = d["easingRight"] as? Double { e.easingRight = v }
            if let v = d["linkgroup"] as? Int { e.linkgroup = v }
            return e
        }
    }

    private static func decodeColorEvents(_ any: Any?) -> [ColorEvent] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let start = d["start"] as? [Int], let end = d["end"] as? [Int] else { return nil }
            var e = ColorEvent(startTime: decodeBeat(d["startTime"]),
                               endTime: decodeBeat(d["endTime"]),
                               start: start,
                               end: end)
            if let v = d["easingType"] as? Int { e.easingType = v }
            if let v = d["easingLeft"] as? Double { e.easingLeft = v }
            if let v = d["easingRight"] as? Double { e.easingRight = v }
            return e
        }
    }

    private static func decodeTextEvents(_ any: Any?) -> [TextEvent] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let start = d["start"] as? String, let end = d["end"] as? String else { return nil }
            var e = TextEvent(startTime: decodeBeat(d["startTime"]),
                              endTime: decodeBeat(d["endTime"]),
                              start: start,
                              end: end)
            if let v = d["easingType"] as? Int { e.easingType = v }
            if let v = d["easingLeft"] as? Double { e.easingLeft = v }
            if let v = d["easingRight"] as? Double { e.easingRight = v }
            return e
        }
    }

    private static func decodeNote(_ d: [String: Any]) -> Note {
        var n = Note()
        if let v = d["type"] as? Int, let t = NoteType(rawValue: v) { n.type = t }
        n.startTime = decodeBeat(d["startTime"])
        n.endTime = decodeBeat(d["endTime"])
        if let v = d["positionX"] as? Double { n.positionX = v }
        if let v = d["size"] as? Double { n.size = v }
        if let v = d["speed"] as? Double { n.speed = v }
        if let v = d["yOffset"] as? Double { n.yOffset = v }
        if let v = d["above"] as? Int { n.above = v }
        if let v = d["alpha"] as? Int { n.alpha = v }
        if let v = d["isFake"] as? Int { n.isFake = v }
        if let v = d["visibleTime"] as? Double { n.visibleTime = v }
        if let v = d["tint"] as? [Int] { n.tint = v }
        if let v = d["tintHitEffects"] as? [Int] { n.tintHitEffects = v }
        if let v = d["judgeArea"] as? Double { n.judgeArea = v }
        return n
    }
}

// 兼容旧调用：旋转事件用普通事件编码
extension EventLayer {
}
