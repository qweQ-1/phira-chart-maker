// 离线验证工具：模拟 Phira 的 Rust 端逻辑，检查我们产出的谱面包。
// 用法（在 iSH 里）：swift run PhiraMakerValidate <archive.zip>
// 也可作为独立脚本运行。

import Foundation

enum Validator {

    static func validate(archive: Data) -> [String] {
        var report: [String] = []

        // 1. ZIP 能被标准库读开
        let items: [ZipArchive.Item]
        do {
            items = try ZipArchive.read(archive)
            report.append("✅ ZIP 解包成功，\(items.count) 个条目")
        } catch {
            report.append("❌ ZIP 解包失败：\(error)")
            return report
        }

        var byName: [String: Data] = [:]
        for item in items { byName[item.name] = item.data }

        // 2. info.yml 存在
        guard let infoData = byName["info.yml"] else {
            report.append("❌ 缺少 info.yml")
            return report
        }
        let infoText = String(data: infoData, encoding: .utf8) ?? ""
        report.append("✅ info.yml 存在（\(infoData.count) 字节）")

        // 3. info.yml 能被 YAML 解析出所有必需字段
        let info = InfoYAML.parse(infoText)
        let required = ["name", "difficulty", "level", "charter", "composer", "illustrator",
                        "chart", "music", "illustration", "previewStart", "aspectRatio",
                        "backgroundDim", "lineLength", "offset", "tags", "intro", "holdPartialCover"]
        var missing: [String] = []
        for key in required where info[key] == nil { missing.append(key) }
        if missing.isEmpty {
            report.append("✅ info.yml 必需字段齐全")
        } else {
            report.append("❌ info.yml 缺少字段：\(missing.joined(separator: ", "))")
        }

        // 4. 谱面文件存在且可解析
        let chartName = info["chart"]?.stringValue ?? "chart.json"
        guard let chartData = byName[chartName] else {
            report.append("❌ 找不到谱面文件 \(chartName)")
            return report
        }
        do {
            let chart = try RPEFormat.decode(chartData)
            var noteCount = 0
            for line in chart.judgeLineList { noteCount += line.notes.count }
            report.append("✅ 谱面解析成功：\(chart.judgeLineList.count) 条判定线，\(noteCount) 个音符，\(chart.BPMList.count) 个 BPM")
        } catch {
            report.append("❌ 谱面解析失败：\(error)")
        }

        // 5. 引用的附件都存在
        for key in ["music", "illustration"] {
            if let name = info[key]?.stringValue, !name.isEmpty {
                if byName[name] != nil {
                    report.append("✅ 附件 \(key) → \(name) 存在")
                } else {
                    report.append("⚠️ 附件 \(key) → \(name) 缺失（Phira 会自动寻找替代文件）")
                }
            }
        }

        return report
    }
}
