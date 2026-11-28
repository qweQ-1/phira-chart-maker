// Phira 谱面数据模型
// 参考: TeamFlos/phira prpr/src/parse/rpe.rs, prpr/src/info.rs
//      TeamFlos/phira-docs chart-standard

import Foundation

// MARK: - Beat (RPE 时间单位)

/// RPE 的拍数表示 `[整数, 分子, 分母]`，值为 `整数 + 分子/分母`
struct Beat: Codable, Hashable {
    var i: Int
    var n: Int
    var d: Int

    init(i: Int, n: Int = 0, d: Int = 1) {
        self.i = i
        self.n = n
        self.d = d == 0 ? 1 : d
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        i = try c.decodeIfPresent(Int.self, forKey: .i) ?? 0
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        d = try c.decodeIfPresent(Int.self, forKey: .d) ?? 1
        if d == 0 { d = 1 }
    }

    /// 拍数值
    var value: Double {
        Double(i) + Double(n) / Double(d)
    }

    /// 由拍数构造（自动约分）
    init(value: Double) {
        if value == value.rounded() && abs(value) < 1e9 {
            self.init(i: Int(value))
            return
        }
        // 用有理数逼近，取 1/1920 精度足够（RPE 内部用 1/1920 拍）
        let denom = 1920
        let scaled = (value * Double(denom)).rounded()
        let intPart = Int(floor(scaled / Double(denom)))
        var rem = Int(scaled) - intPart * denom
        if rem < 0 { rem = 0 }
        var g = gcd(rem, denom)
        if g == 0 { g = denom }
        self.init(i: intPart, n: rem / g, d: denom / g)
    }

    /// 序列化为 JSON 数组 `[i, n, d]`
    func toJSONArray() -> [Int] { [i, n, d] }

    init(jsonArray: [Int]) {
        self.init(i: jsonArray.count > 0 ? jsonArray[0] : 0,
                  n: jsonArray.count > 1 ? jsonArray[1] : 0,
                  d: jsonArray.count > 2 ? jsonArray[2] : 1)
    }
}

func gcd(_ a: Int, _ b: Int) -> Int {
    var x = abs(a), y = abs(b)
    while y != 0 {
        let t = y
        y = x % y
        x = t
    }
    return x == 0 ? 1 : x
}

// MARK: - BPM 事件

struct BPMEvent: Codable, Hashable {
    var startTime: Beat
    var bpm: Double

    init(startTime: Beat, bpm: Double) {
        self.startTime = startTime
        self.bpm = bpm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try c.decodeIfPresent(Beat.self, forKey: .startTime) ?? Beat(i: 0)
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm) ?? 120
    }
}

// MARK: - 音符

enum NoteType: Int, Codable, CaseIterable, Identifiable {
    case tap = 1
    case hold = 2
    case flick = 3
    case drag = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .tap: return "Tap"
        case .hold: return "Hold"
        case .flick: return "Flick"
        case .drag: return "Drag"
        }
    }

    var symbol: String {
        switch self {
        case .tap: return "●"
        case .hold: return "▬"
        case .flick: return "◆"
        case .drag: return "▲"
        }
    }
}

struct Note: Codable, Hashable, Identifiable {
    var id = UUID()
    var type: NoteType = .tap
    var startTime: Beat = Beat(i: 0)
    var endTime: Beat = Beat(i: 0)
    /// 相对判定线中心的 X 坐标，RPE 范围约 -675...675
    var positionX: Double = 0
    var size: Double = 1
    var speed: Double = 1
    var yOffset: Double = 0
    var above: Int = 1
    var alpha: Int = 255
    var isFake: Int = 0
    var visibleTime: Double = 999999
    var tint: [Int]? = nil
    var tintHitEffects: [Int]? = nil
    var judgeArea: Double? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decodeIfPresent(NoteType.self, forKey: .type) ?? .tap
        startTime = try c.decodeIfPresent(Beat.self, forKey: .startTime) ?? Beat(i: 0)
        endTime = try c.decodeIfPresent(Beat.self, forKey: .endTime) ?? startTime
        positionX = try c.decodeIfPresent(Double.self, forKey: .positionX) ?? 0
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 1
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        yOffset = try c.decodeIfPresent(Double.self, forKey: .yOffset) ?? 0
        above = try c.decodeIfPresent(Int.self, forKey: .above) ?? 1
        alpha = try c.decodeIfPresent(Int.self, forKey: .alpha) ?? 255
        isFake = try c.decodeIfPresent(Int.self, forKey: .isFake) ?? 0
        visibleTime = try c.decodeIfPresent(Double.self, forKey: .visibleTime) ?? 999999
        tint = try c.decodeIfPresent([Int].self, forKey: .tint)
        tintHitEffects = try c.decodeIfPresent([Int].self, forKey: .tintHitEffects)
        judgeArea = try c.decodeIfPresent(Double.self, forKey: .judgeArea)
    }

    init(type: NoteType, startTime: Beat, endTime: Beat? = nil, positionX: Double = 0) {
        self.type = type
        self.startTime = startTime
        self.endTime = endTime ?? startTime
        self.positionX = positionX
    }

    /// 音符是否为 Hold
    var isHold: Bool { type == .hold }
}

// MARK: - 判定线事件

/// 缓动类型，1...29 与 RPE 对照表一致
enum EasingType: Int, Codable, CaseIterable, Identifiable {
    case linear = 1
    case outSine = 2
    case inSine = 3
    case outQuad = 4
    case inQuad = 5
    case inOutSine = 6
    case inOutQuad = 7
    case outCubic = 8
    case inCubic = 9
    case outQuart = 10
    case inQuart = 11
    case inOutCubic = 12
    case inOutQuart = 13
    case outQuint = 14
    case inQuint = 15
    case outExpo = 16
    case inExpo = 17
    case outCirc = 18
    case inCirc = 19
    case outBack = 20
    case inBack = 21
    case inOutCirc = 22
    case inOutBack = 23
    case outElastic = 24
    case inElastic = 25
    case outBounce = 26
    case inBounce = 27
    case inOutBounce = 28
    case inOutElastic = 29

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .linear: return "线性"
        case .outSine: return "Out Sine"
        case .inSine: return "In Sine"
        case .outQuad: return "Out Quad"
        case .inQuad: return "In Quad"
        case .inOutSine: return "In Out Sine"
        case .inOutQuad: return "In Out Quad"
        case .outCubic: return "Out Cubic"
        case .inCubic: return "In Cubic"
        case .outQuart: return "Out Quart"
        case .inQuart: return "In Quart"
        case .inOutCubic: return "In Out Cubic"
        case .inOutQuart: return "In Out Quart"
        case .outQuint: return "Out Quint"
        case .inQuint: return "In Quint"
        case .outExpo: return "Out Expo"
        case .inExpo: return "In Expo"
        case .outCirc: return "Out Circ"
        case .inCirc: return "In Circ"
        case .outBack: return "Out Back"
        case .inBack: return "In Back"
        case .inOutCirc: return "In Out Circ"
        case .inOutBack: return "In Out Back"
        case .outElastic: return "Out Elastic"
        case .inElastic: return "In Elastic"
        case .outBounce: return "Out Bounce"
        case .inBounce: return "In Bounce"
        case .inOutBounce: return "In Out Bounce"
        case .inOutElastic: return "In Out Elastic"
        }
    }
}

/// 通用事件（缓动插值）
struct LineEvent: Codable, Hashable {
    var startTime: Beat
    var endTime: Beat
    var start: Double
    var end: Double
    var easingType: Int = 1
    var easingLeft: Double = 0
    var easingRight: Double = 1
    var linkgroup: Int = 0

    init(startTime: Beat, endTime: Beat, start: Double, end: Double, easingType: Int = 1) {
        self.startTime = startTime
        self.endTime = endTime
        self.start = start
        self.end = end
        self.easingType = easingType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try c.decodeIfPresent(Beat.self, forKey: .startTime) ?? Beat(i: 0)
        endTime = try c.decodeIfPresent(Beat.self, forKey: .endTime) ?? startTime
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Double.self, forKey: .end) ?? 0
        easingType = try c.decodeIfPresent(Int.self, forKey: .easingType) ?? 1
        easingLeft = try c.decodeIfPresent(Double.self, forKey: .easingLeft) ?? 0
        easingRight = try c.decodeIfPresent(Double.self, forKey: .easingRight) ?? 1
        linkgroup = try c.decodeIfPresent(Int.self, forKey: .linkgroup) ?? 0
    }
}

/// 颜色事件
struct ColorEvent: Codable, Hashable {
    var startTime: Beat
    var endTime: Beat
    var start: [Int]
    var end: [Int]
    var easingType: Int = 1
    var easingLeft: Double = 0
    var easingRight: Double = 1
    var linkgroup: Int = 0

    init(startTime: Beat, endTime: Beat, start: [Int], end: [Int]) {
        self.startTime = startTime
        self.endTime = endTime
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try c.decodeIfPresent(Beat.self, forKey: .startTime) ?? Beat(i: 0)
        endTime = try c.decodeIfPresent(Beat.self, forKey: .endTime) ?? startTime
        start = try c.decodeIfPresent([Int].self, forKey: .start) ?? [255, 255, 255]
        end = try c.decodeIfPresent([Int].self, forKey: .end) ?? [255, 255, 255]
        easingType = try c.decodeIfPresent(Int.self, forKey: .easingType) ?? 1
        easingLeft = try c.decodeIfPresent(Double.self, forKey: .easingLeft) ?? 0
        easingRight = try c.decodeIfPresent(Double.self, forKey: .easingRight) ?? 1
        linkgroup = try c.decodeIfPresent(Int.self, forKey: .linkgroup) ?? 0
    }
}

/// 文本事件
struct TextEvent: Codable, Hashable {
    var startTime: Beat
    var endTime: Beat
    var start: String
    var end: String
    var easingType: Int = 1
    var easingLeft: Double = 0
    var easingRight: Double = 1
    var linkgroup: Int = 0

    init(startTime: Beat, endTime: Beat, start: String, end: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try c.decodeIfPresent(Beat.self, forKey: .startTime) ?? Beat(i: 0)
        endTime = try c.decodeIfPresent(Beat.self, forKey: .endTime) ?? startTime
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? ""
        easingType = try c.decodeIfPresent(Int.self, forKey: .easingType) ?? 1
        easingLeft = try c.decodeIfPresent(Double.self, forKey: .easingLeft) ?? 0
        easingRight = try c.decodeIfPresent(Double.self, forKey: .easingRight) ?? 1
        linkgroup = try c.decodeIfPresent(Int.self, forKey: .linkgroup) ?? 0
    }
}

/// 事件层级
struct EventLayer: Codable, Hashable {
    var speedEvents: [LineEvent] = []
    var moveXEvents: [LineEvent] = []
    var moveYEvents: [LineEvent] = []
    var rotateEvents: [LineEvent] = []
    var alphaEvents: [LineEvent] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speedEvents = try c.decodeIfPresent([LineEvent].self, forKey: .speedEvents) ?? []
        moveXEvents = try c.decodeIfPresent([LineEvent].self, forKey: .moveXEvents) ?? []
        moveYEvents = try c.decodeIfPresent([LineEvent].self, forKey: .moveYEvents) ?? []
        rotateEvents = try c.decodeIfPresent([LineEvent].self, forKey: .rotateEvents) ?? []
        alphaEvents = try c.decodeIfPresent([LineEvent].self, forKey: .alphaEvents) ?? []
    }
}

/// 扩展（故事板）事件
struct ExtendedEvents: Codable, Hashable {
    var colorEvents: [ColorEvent] = []
    var scaleXEvents: [LineEvent] = []
    var scaleYEvents: [LineEvent] = []
    var textEvents: [TextEvent] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colorEvents = try c.decodeIfPresent([ColorEvent].self, forKey: .colorEvents) ?? []
        scaleXEvents = try c.decodeIfPresent([LineEvent].self, forKey: .scaleXEvents) ?? []
        scaleYEvents = try c.decodeIfPresent([LineEvent].self, forKey: .scaleYEvents) ?? []
        textEvents = try c.decodeIfPresent([TextEvent].self, forKey: .textEvents) ?? []
    }
}

// MARK: - 判定线

struct JudgeLine: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String = "Untitled"
    var texture: String = "line.png"
    var father: Int = -1
    var isCover: Int = 1
    var zOrder: Int = 0
    var bpmfactor: Double = 1.0
    var rotateWithFather: Bool = true
    var eventLayers: [EventLayer] = [EventLayer()]
    var extended: ExtendedEvents? = nil
    var notes: [Note] = []

    init(name: String = "Untitled") {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        texture = try c.decodeIfPresent(String.self, forKey: .texture) ?? "line.png"
        father = try c.decodeIfPresent(Int.self, forKey: .father) ?? -1
        isCover = try c.decodeIfPresent(Int.self, forKey: .isCover) ?? 1
        zOrder = try c.decodeIfPresent(Int.self, forKey: .zOrder) ?? 0
        bpmfactor = try c.decodeIfPresent(Double.self, forKey: .bpmfactor) ?? 1.0
        rotateWithFather = try c.decodeIfPresent(Bool.self, forKey: .rotateWithFather) ?? true
        eventLayers = try c.decodeIfPresent([EventLayer].self, forKey: .eventLayers) ?? [EventLayer()]
        extended = try c.decodeIfPresent(ExtendedEvents.self, forKey: .extended)
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
    }
}

// MARK: - 元信息

struct ChartMeta: Codable, Hashable {
    var RPEVersion: Int = 160
    var id: String = ""
    var name: String = "Untitled"
    var level: String = "0"
    var charter: String = "Unknown"
    var composer: String = "Unknown"
    var illustration: String = ""
    var song: String = ""
    var background: String = ""
    var offset: Int = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        RPEVersion = try c.decodeIfPresent(Int.self, forKey: .RPEVersion) ?? 160
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? "0"
        charter = try c.decodeIfPresent(String.self, forKey: .charter) ?? "Unknown"
        composer = try c.decodeIfPresent(String.self, forKey: .composer) ?? "Unknown"
        illustration = try c.decodeIfPresent(String.self, forKey: .illustration) ?? ""
        song = try c.decodeIfPresent(String.self, forKey: .song) ?? ""
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? ""
        offset = try c.decodeIfPresent(Int.self, forKey: .offset) ?? 0
    }
}

enum ChartFormat: String, Codable, CaseIterable, Identifiable {
    case rpe
    case pec
    case pgr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rpe: return "RPE (JSON)"
        case .pec: return "PEC (文本)"
        case .pgr: return "Phigros Official"
        }
    }
}

// MARK: - RPE 谱面文件

struct RPEChart: Codable {
    var META: ChartMeta
    var BPMList: [BPMEvent]
    var judgeLineList: [JudgeLine]

    init(meta: ChartMeta, bpmList: [BPMEvent], judgeLineList: [JudgeLine]) {
        self.META = meta
        self.BPMList = bpmList
        self.judgeLineList = judgeLineList
    }

    /// 解码时容忍缺字段（旧存档 / 外部导入）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        META = try c.decodeIfPresent(ChartMeta.self, forKey: .META) ?? ChartMeta()
        BPMList = try c.decodeIfPresent([BPMEvent].self, forKey: .BPMList)
            ?? [BPMEvent(startTime: Beat(i: 0), bpm: 120)]
        judgeLineList = try c.decodeIfPresent([JudgeLine].self, forKey: .judgeLineList) ?? []
    }
}
