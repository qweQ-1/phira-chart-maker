// 谱面包自检：模拟 Phira 的 Rust 端逻辑，检查我们产出的包能不能被游戏读取。
// App 内「导出 → 校验谱面包」按钮用的就是它。

import Foundation

enum Validator {

    static func validate(archive: Data) -> [String] {
        var report: [String] = []

        // 1. ZIP 能被解开
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

        // 2. info.yml 必须存在（Phira 的 fix_info 靠它找谱面/音乐/插图）
        guard let infoData = byName["info.yml"] else {
            report.append("❌ 缺少 info.yml")
            return report
        }
        let infoText = String(data: infoData, encoding: .utf8) ?? ""
        report.append("✅ info.yml 存在（\(infoData.count) 字节）")

        // 3. 解析 info.yml
        let info = InfoYAML.parse(infoText)

        // 4. 谱面文件存在且能解析
        let chartName = info.chart.isEmpty ? "chart.json" : info.chart
        guard let chartData = byName[chartName] else {
            report.append("❌ 找不到谱面文件 \(chartName)")
            return report
        }
        report.append("✅ 按 info.yml 找到谱面文件 \(chartName)")

        do {
            let chart = try RPEFormat.decode(chartData)
            var noteCount = 0
            for line in chart.judgeLineList { noteCount += line.notes.count }
            report.append("✅ 谱面解析成功：\(chart.judgeLineList.count) 条判定线，\(noteCount) 个音符，\(chart.BPMList.count) 个 BPM")
        } catch {
            report.append("❌ 谱面解析失败：\(error)")
        }

        // 5. 必需字段非空
        var missing: [String] = []
        if info.name.isEmpty { missing.append("name") }
        if info.level.isEmpty { missing.append("level") }
        if info.charter.isEmpty { missing.append("charter") }
        if info.music.isEmpty { missing.append("music") }
        if info.illustration.isEmpty { missing.append("illustration") }
        if missing.isEmpty {
            report.append("✅ info.yml 必需字段齐全")
        } else {
            report.append("⚠️ info.yml 以下字段为空：\(missing.joined(separator: ", "))")
        }

        // 6. 引用的附件都存在
        for (key, name) in [("music", info.music), ("illustration", info.illustration)] {
            if name.isEmpty { continue }
            if byName[name] != nil {
                report.append("✅ 附件 \(key) → \(name) 存在")
            } else {
                report.append("⚠️ 附件 \(key) → \(name) 缺失（Phira 会自动寻找替代文件）")
            }
        }

        // 7. 根目录不能有嵌套目录（Phira 只从根目录找 info.yml）
        let nested = items.map { $0.name }.filter { $0.contains("/") }
        if nested.isEmpty {
            report.append("✅ 文件都在根目录（Phira 要求解压后直接是文件）")
        } else {
            report.append("⚠️ 有嵌套路径文件：\(nested.joined(separator: ", "))")
        }

        return report
    }
}
