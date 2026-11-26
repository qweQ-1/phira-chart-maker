// 拍 ↔ 秒换算（RPE 语义）
// 规范: TeamFlos/phira-docs chart-standard/chart-format/rpe/beat.md
// 实现: TeamFlos/phira prpr/src/parse/rpe.rs (BpmList::new)

import Foundation

struct BpmTimeline {
    /// 每个 BPM 段的 (起始拍, 起始秒, bpm)
    private var segments: [(beat: Double, time: Double, bpm: Double)] = []

    init(bpmList: [BPMEvent]) {
        let sorted = bpmList
            .filter { $0.bpm > 0 }
            .sorted { $0.startTime.value < $1.startTime.value }
        let list = sorted.isEmpty ? [BPMEvent(startTime: Beat(i: 0), bpm: 120)] : sorted

        var elapsed = 0.0
        var lastBeat = list[0].startTime.value
        var lastBpm = list[0].bpm
        segments.append((beat: 0, time: 0, bpm: list[0].bpm))

        // 起点之前的段落用第一个 BPM 从 0 拍铺下来
        if lastBeat > 0 {
            elapsed = lastBeat * (60.0 / lastBpm)
            segments = [(beat: 0, time: 0, bpm: lastBpm)]
        }

        for (i, e) in list.enumerated() where i > 0 {
            let deltaBeat = e.startTime.value - lastBeat
            elapsed += deltaBeat * (60.0 / lastBpm)
            segments.append((beat: e.startTime.value, time: elapsed, bpm: e.bpm))
            lastBeat = e.startTime.value
            lastBpm = e.bpm
        }
    }

    /// 拍 → 秒
    func time(atBeat beat: Double) -> Double {
        guard let first = segments.first else { return 0 }
        if beat <= first.beat { return (beat - first.beat) * (60.0 / first.bpm) + first.time }
        var seg = first
        for s in segments where s.beat <= beat { seg = s }
        return seg.time + (beat - seg.beat) * (60.0 / seg.bpm)
    }

    /// 秒 → 拍
    func beat(atTime time: Double) -> Double {
        guard let first = segments.first else { return 0 }
        if time <= first.time { return first.beat + (time - first.time) * (first.bpm / 60.0) }
        var seg = first
        for s in segments where s.time <= time { seg = s }
        return seg.beat + (time - seg.time) * (seg.bpm / 60.0)
    }

    /// 当前拍的 BPM
    func bpm(atBeat beat: Double) -> Double {
        guard let first = segments.first else { return 120 }
        var seg = first
        for s in segments where s.beat <= beat { seg = s }
        return seg.bpm
    }

    /// 当前的拍号所在 BPM 段起点（用于网格对齐）
    func segmentStart(atBeat beat: Double) -> Double {
        guard let first = segments.first else { return 0 }
        var seg = first
        for s in segments where s.beat <= beat { seg = s }
        return seg.beat
    }
}

enum BeatMath {
    /// 把拍数吸附到 1/div 网格
    static func snap(_ beat: Double, division: Int) -> Double {
        guard division > 0 else { return beat }
        let step = 1.0 / Double(division)
        return (beat / step).rounded() * step
    }

    /// 拍数 → 可读的定位字符串（如 12.75）
    static func display(_ beat: Double) -> String {
        var s = String(format: "%.3f", beat)
        while s.contains(".") && s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 秒 → mm:ss.cc
    static func clock(_ seconds: Double) -> String {
        if seconds < 0 { return "-" + clock(-seconds) }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let cs = Int((seconds - floor(seconds)) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }
}
