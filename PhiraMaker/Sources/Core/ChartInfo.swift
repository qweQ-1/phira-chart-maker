// Phira 谱面信息 (info.yml) 读写
// 规范: TeamFlos/phira-docs chart-standard/chartinfo.md
// 结构定义: TeamFlos/phira prpr/src/info.rs (ChartInfo)

import Foundation

/// 对应 Phira 的 `ChartInfo`（serde camelCase）
struct ChartInfo: Codable, Equatable {
    var id: Int? = nil
    var uploader: Int? = nil

    var name: String = "UK"
    var difficulty: Float = 10
    var level: String = "UK Lv.10"
    var charter: String = "UK"
    var composer: String = "UK"
    var illustrator: String = "UK"

    var chart: String = "chart.json"
    var format: String? = nil
    var music: String = "song.mp3"
    var illustration: String = "background.png"
    var unlockVideo: String? = nil

    var previewStart: Float = 0
    var previewEnd: Float? = nil
    var aspectRatio: Float = 16.0 / 9.0
    var backgroundDim: Float = 0.6
    var lineLength: Float = 6
    var offset: Float = 0
    var tip: String? = nil
    var tags: [String] = []

    var intro: String = ""
    var holdPartialCover: Bool = false
    var noteUniformScale: Bool = false
    var forceAspectRatio: Bool = false
    var useRpe170Speed: Bool? = nil
    var useAttachUiFix: Bool? = nil

    var created: String? = nil
    var updated: String? = nil
    var chartUpdated: String? = nil

    init() {}
}

enum InfoYAML {

    /// 生成 info.yml 文本。
    /// `format` 对应 Phira 的 ChartFormat 枚举（lowercase）：rpe / pec / pgr / pbc
    static func dump(_ info: ChartInfo) -> String {
        var entries: [(String, YamlValue)] = []

        if let id = info.id { entries.append(("id", .raw("\(id)"))) }
        if let uploader = info.uploader { entries.append(("uploader", .raw("\(uploader)"))) }

        entries.append(("name", .scalar(info.name)))
        entries.append(("difficulty", .raw(formatFloat(info.difficulty))))
        entries.append(("level", .scalar(info.level)))
        entries.append(("charter", .scalar(info.charter)))
        entries.append(("composer", .scalar(info.composer)))
        entries.append(("illustrator", .scalar(info.illustrator)))

        entries.append(("chart", .scalar(info.chart)))
        if let format = info.format { entries.append(("format", .scalar(format))) }
        entries.append(("music", .scalar(info.music)))
        entries.append(("illustration", .scalar(info.illustration)))
        if let unlockVideo = info.unlockVideo { entries.append(("unlockVideo", .scalar(unlockVideo))) }

        entries.append(("previewStart", .raw(formatFloat(info.previewStart))))
        if let previewEnd = info.previewEnd { entries.append(("previewEnd", .raw(formatFloat(previewEnd)))) }
        entries.append(("aspectRatio", .raw(formatFloat(info.aspectRatio))))
        entries.append(("backgroundDim", .raw(formatFloat(info.backgroundDim))))
        entries.append(("lineLength", .raw(formatFloat(info.lineLength))))
        entries.append(("offset", .raw(formatFloat(info.offset))))
        if let tip = info.tip { entries.append(("tip", .scalar(tip))) }
        entries.append(("tags", .list(info.tags)))

        entries.append(("intro", .scalar(info.intro)))
        entries.append(("holdPartialCover", .raw(info.holdPartialCover ? "true" : "false")))
        entries.append(("noteUniformScale", .raw(info.noteUniformScale ? "true" : "false")))
        entries.append(("forceAspectRatio", .raw(info.forceAspectRatio ? "true" : "false")))
        if let v = info.useRpe170Speed { entries.append(("useRpe170Speed", .raw(v ? "true" : "false"))) }
        if let v = info.useAttachUiFix { entries.append(("useAttachUiFix", .raw(v ? "true" : "false"))) }

        if let created = info.created { entries.append(("created", .scalar(created))) }
        if let updated = info.updated { entries.append(("updated", .scalar(updated))) }
        if let chartUpdated = info.chartUpdated { entries.append(("chartUpdated", .scalar(chartUpdated))) }

        return Yaml.dump(entries)
    }

    /// 解析 info.yml（兼容 Phira 导出的 info.yml / info.txt）
    static func parse(_ text: String) -> ChartInfo {
        var info = ChartInfo()
        let dict = Yaml.parse(text)

        if let s = dict["id"]?.stringValue, let v = Int(s) { info.id = v }
        if let s = dict["uploader"]?.stringValue, let v = Int(s) { info.uploader = v }

        if let v = dict["name"]?.stringValue { info.name = v }
        if let v = dict["difficulty"]?.floatValue { info.difficulty = v }
        if let v = dict["level"]?.stringValue { info.level = v }
        if let v = dict["charter"]?.stringValue { info.charter = v }
        if let v = dict["composer"]?.stringValue { info.composer = v }
        if let v = dict["illustrator"]?.stringValue { info.illustrator = v }

        if let v = dict["chart"]?.stringValue { info.chart = v }
        if let v = dict["format"]?.stringValue { info.format = v }
        if let v = dict["music"]?.stringValue { info.music = v }
        if let v = dict["illustration"]?.stringValue { info.illustration = v }
        if let v = dict["unlockVideo"]?.stringValue { info.unlockVideo = v }

        if let v = dict["previewStart"]?.floatValue { info.previewStart = v }
        if let v = dict["previewEnd"]?.floatValue { info.previewEnd = v }
        if let v = dict["aspectRatio"]?.floatValue { info.aspectRatio = v }
        if let v = dict["backgroundDim"]?.floatValue { info.backgroundDim = v }
        if let v = dict["lineLength"]?.floatValue { info.lineLength = v }
        if let v = dict["offset"]?.floatValue { info.offset = v }
        if let v = dict["tip"]?.stringValue { info.tip = v }
        if let v = dict["tags"]?.listValue { info.tags = v }

        if let v = dict["intro"]?.stringValue { info.intro = v }
        if let v = dict["holdPartialCover"]?.boolValue { info.holdPartialCover = v }
        if let v = dict["noteUniformScale"]?.boolValue { info.noteUniformScale = v }
        if let v = dict["forceAspectRatio"]?.boolValue { info.forceAspectRatio = v }
        if let v = dict["useRpe170Speed"]?.boolValue { info.useRpe170Speed = v }
        if let v = dict["useAttachUiFix"]?.boolValue { info.useAttachUiFix = v }

        if let v = dict["created"]?.stringValue { info.created = v }
        if let v = dict["updated"]?.stringValue { info.updated = v }
        if let v = dict["chartUpdated"]?.stringValue { info.chartUpdated = v }

        return info
    }

    /// 浮点格式化：整数不写小数点，其余最多 6 位有效小数
    static func formatFloat(_ v: Float) -> String {
        if v == v.rounded() && abs(v) < 1e9 {
            return String(Int(v))
        }
        var s = String(format: "%.6f", v)
        while s.contains(".") && (s.hasSuffix("0")) { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
