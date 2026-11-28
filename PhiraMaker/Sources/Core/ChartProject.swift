// 谱面工程：打包为 Phira 可导入的 .zip 谱面包，并支持反向导入。
//
// Phira 谱面包结构（解压后直接是文件，不是文件夹）：
//   info.yml      —— 元信息（权威来源）
//   chart.json    —— RPE 谱面（也可为 .pec）
//   song.mp3      —— 音乐
//   background.png—— 插图
//
// 校验依据：TeamFlos/phira prpr/src/fs.rs (load_info / fix_info)
//           TeamFlos/phira phira/src/scene/song.rs (export / import)

import Foundation

/// 工程中的一个附件（音乐 / 插图 / 解锁视频）
struct ChartAsset: Identifiable, Hashable, Codable {
    enum Kind: String, CaseIterable, Identifiable, Codable {
        case music, illustration, unlockVideo
        var id: String { rawValue }
    }

    var id = UUID()
    var kind: Kind
    /// 文件名（在包内）
    var fileName: String
    var data: Data
    /// 原始文件名（导入时保留）
    var originalName: String = ""
}

struct ChartProject: Codable {
    var info: ChartInfo = ChartInfo()
    var chart: RPEChart
    var format: ChartFormat = .rpe
    var assets: [ChartAsset] = []

    init() {
        var meta = ChartMeta()
        meta.name = "New Chart"
        meta.level = "0"
        chart = RPEChart(meta: meta,
                         bpmList: [BPMEvent(startTime: Beat(i: 0), bpm: 120)],
                         judgeLineList: [JudgeLine(name: "Line 0")])
        info.format = "rpe"
        info.chart = "chart.json"
    }

    var music: ChartAsset? { assets.first { $0.kind == .music } }
    var illustration: ChartAsset? { assets.first { $0.kind == .illustration } }

    /// 谱面文件的内部文件名
    var chartFileName: String {
        switch format {
        case .rpe: return "chart.json"
        case .pec: return "chart.pec"
        case .pgr: return "chart.json"
        }
    }

    // MARK: - 打包导出

    /// 导出为 Phira 谱面包（.zip）
    func exportArchive() throws -> Data {
        var entries: [ZipEntry] = []

        // 1. info.yml
        var info = self.info
        info.chart = chartFileName
        info.format = format == .pgr ? nil : format.rawValue
        entries.append(ZipEntry(name: "info.yml", data: Data(InfoYAML.dump(info).utf8)))

        // 2. 谱面文件
        let chartData: Data
        switch format {
        case .rpe, .pgr:
            chartData = try RPEFormat.encode(chart)
        case .pec:
            chartData = try PECFormat.encode(chart)
        }
        entries.append(ZipEntry(name: chartFileName, data: chartData))

        // 3. 附件
        for asset in assets {
            entries.append(ZipEntry(name: asset.fileName, data: asset.data))
        }

        return try ZipArchive.create(entries: entries)
    }

    // MARK: - 导入解析

    /// 从 .zip 谱面包导入
    static func importArchive(_ data: Data) throws -> ChartProject {
        let items = try ZipArchive.read(data)
        guard !items.isEmpty else { throw ImportError.emptyArchive }

        var byName: [String: Data] = [:]
        for item in items {
            // 兼容少数打包器带一层目录的情况
            var name = item.name
            if name.hasPrefix("./") { name = String(name.dropFirst(2)) }
            byName[name] = item.data
        }

        // 谱面文件：优先用 info.yml 里指定的
        var info = ChartInfo()
        if let infoData = byName["info.yml"] {
            info = InfoYAML.parse(String(data: infoData, encoding: .utf8) ?? "")
        }

        var chartData: Data?
        var chartName = info.chart
        if let d = byName[chartName] {
            chartData = d
        } else {
            // 兜底：找根目录下的 json / pec
            for (name, d) in byName where !name.contains("/") {
                let ext = (name as NSString).pathExtension.lowercased()
                if ext == "json" || ext == "pec" {
                    chartData = d
                    chartName = name
                    break
                }
            }
        }
        guard let chartData = chartData else { throw ImportError.chartNotFound }

        // 判定格式
        var format: ChartFormat = .rpe
        if let f = info.format, let parsed = ChartFormat(rawValue: f) {
            format = parsed
        } else if (chartName as NSString).pathExtension.lowercased() == "pec" {
            format = .pec
        } else if chartData.isJSONArrayLike() {
            format = .pgr
        }

        let rpeChart: RPEChart
        switch format {
        case .rpe:
            rpeChart = try RPEFormat.decode(chartData)
        case .pec:
            rpeChart = try PECFormat.decode(chartData)
        case .pgr:
            rpeChart = try RPEFormat.decode(chartData)
        }

        // 附件
        var assets: [ChartAsset] = []
        let musicName = info.music
        let illuName = info.illustration
        for (name, d) in byName {
            if name == "info.yml" || name == chartName { continue }
            if name.contains("/") { continue }  // 只取根目录文件
            var kind: ChartAsset.Kind? = nil
            if name == musicName { kind = .music }
            else if name == illuName { kind = .illustration }
            else {
                let ext = (name as NSString).pathExtension.lowercased()
                if ["mp3", "ogg", "wav", "flac", "aac"].contains(ext) { kind = .music }
                else if ["png", "jpg", "jpeg", "webp", "avif"].contains(ext) { kind = .illustration }
            }
            if let k = kind {
                assets.append(ChartAsset(kind: k, fileName: name, data: d, originalName: name))
            }
        }
        if let unlockVideo = info.unlockVideo, let d = byName[unlockVideo] {
            assets.append(ChartAsset(kind: .unlockVideo, fileName: unlockVideo, data: d, originalName: unlockVideo))
        }

        var project = ChartProject()
        project.info = info
        project.chart = rpeChart
        project.format = format
        project.assets = assets
        project.info.chart = chartName

        // 元信息兜底：从 RPE META 补（info.yml 优先）
        if project.info.name.isEmpty || project.info.name == "UK" {
            project.info.name = rpeChart.META.name
        }
        if project.info.charter.isEmpty || project.info.charter == "UK" {
            project.info.charter = rpeChart.META.charter
        }
        if project.info.composer.isEmpty || project.info.composer == "UK" {
            project.info.composer = rpeChart.META.composer
        }
        if project.info.illustrator.isEmpty || project.info.illustrator == "UK" {
            project.info.illustrator = rpeChart.META.illustration
        }
        if project.info.level.isEmpty || project.info.level == "UK Lv.10" {
            project.info.level = rpeChart.META.level
        }
        return project
    }
}

enum ImportError: Error, LocalizedError {
    case emptyArchive
    case chartNotFound
    case invalidChart

    var errorDescription: String? {
        switch self {
        case .emptyArchive: return "压缩包是空的"
        case .chartNotFound: return "压缩包里找不到谱面文件"
        case .invalidChart: return "谱面文件无法解析"
        }
    }
}

extension Data {
    /// 粗略判断是否是 JSON 数组（Phigros Official 格式）
    func isJSONArrayLike() -> Bool {
        guard let s = String(data: self, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return s.hasPrefix("[")
    }
}
