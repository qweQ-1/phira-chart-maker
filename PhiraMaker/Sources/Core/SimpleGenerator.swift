// 新手模式的纯逻辑：难度预设、四轨映射、示例谱面生成。
// 抽出来是为了能单独跑单元测试。

import Foundation

enum SimpleGenerator {

    /// 四条轨道对应的 RPE X 坐标（单判定线上均匀分布）
    static let trackX: [Double] = [-450, -150, 150, 450]

    /// 轨道显示名
    static let trackNames = ["左", "中左", "中右", "右"]

    /// 难度预设：(简称, difficulty 值, level 文本)
    static let difficulties: [(name: String, value: Float, level: String)] = [
        ("EZ", 3, "EZ Lv.3"),
        ("NM", 8, "NM Lv.8"),
        ("HD", 13, "HD Lv.13"),
        ("EX", 17, "EX Lv.17"),
        ("IN", 21, "IN Lv.21"),
    ]

    static let commonBpms: [Double] = [100, 120, 128, 140, 150, 160, 180, 200]

    /// 生成一个可直接导出、能玩的示例谱面（8 小节，4/4 拍）
    static func demoNotes(bars: Int = 8) -> [Note] {
        var notes: [Note] = []
        for bar in 0..<max(1, bars) {
            let base = Double(bar * 4)
            // 第 1 拍：Tap 左轨
            notes.append(Note(type: .tap, startTime: Beat(value: base),
                              endTime: Beat(value: base), positionX: trackX[0]))
            // 第 2 拍：Tap 右轨
            notes.append(Note(type: .tap, startTime: Beat(value: base + 1),
                              endTime: Beat(value: base + 1), positionX: trackX[3]))
            // 第 3 拍：Hold 中左轨，跨 1 拍
            notes.append(Note(type: .hold, startTime: Beat(value: base + 2),
                              endTime: Beat(value: base + 3), positionX: trackX[1]))
            // 第 4 拍：Flick 中右轨（每两小节换一次 Drag，做点变化）
            notes.append(Note(type: bar % 2 == 0 ? .flick : .drag,
                              startTime: Beat(value: base + 3),
                              endTime: Beat(value: base + 3),
                              positionX: trackX[2]))
        }
        return notes
    }

    /// 把示例谱面写进工程（只动音符和 BPM，不碰用户填的元信息）
    static func applyDemo(to project: inout ChartProject, bars: Int = 8) {
        if project.chart.judgeLineList.isEmpty {
            project.chart.judgeLineList.append(JudgeLine(name: "主判定线"))
        }
        project.chart.judgeLineList[0].notes = demoNotes(bars: bars)
    }

    /// 改 BPM（新手模式只有一个 BPM 段）
    static func setBPM(_ bpm: Double, in project: inout ChartProject) {
        let valid = bpm > 0 ? bpm : 120
        project.chart.BPMList = [BPMEvent(startTime: Beat(i: 0), bpm: valid)]
    }

    /// 应用难度预设，同时同步 info 与 RPE META
    static func applyDifficulty(_ index: Int, to project: inout ChartProject) {
        guard difficulties.indices.contains(index) else { return }
        let preset = difficulties[index]
        project.info.difficulty = preset.value
        project.info.level = preset.level
        project.chart.META.level = preset.level
    }

    /// 从工程里算出音符落在第几拍、第几轨（供网格回显）
    static func slotAndTrack(for note: Note) -> (slot: Int, track: Int)? {
        let slot = Int((note.startTime.value * 2).rounded())
        guard let track = trackX.firstIndex(where: { abs($0 - note.positionX) < 1 }) else {
            return nil
        }
        return (slot, track)
    }
}
