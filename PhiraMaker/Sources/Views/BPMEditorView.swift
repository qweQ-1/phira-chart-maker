import SwiftUI

struct BPMEditorView: View {
    @Binding var project: ChartProject
    @State private var newBeat: String = ""
    @State private var newBpm: String = ""

    private var timeline: BpmTimeline { BpmTimeline(bpmList: project.chart.BPMList) }

    var body: some View {
        List {
            Section {
                ForEach(Array(project.chart.BPMList.enumerated()), id: \.offset) { idx, bpm in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BPM \(fmt(bpm.bpm))")
                                .font(.body.bold())
                            Text("起始拍 \(BeatMath.display(bpm.startTime.value)) · 时间 \(BeatMath.clock(timeline.time(atBeat: bpm.startTime.value)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if idx > 0 {
                            Button(role: .destructive) {
                                project.chart.BPMList.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("BPM 列表")
            } footer: {
                Text("第一个 BPM 必须从 0 拍开始。中途变速就添加新的段。")
            }

            Section("添加 BPM 段") {
                HStack {
                    Text("起始拍")
                    TextField("如 16", text: $newBeat)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("BPM")
                    TextField("如 180", text: $newBpm)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Button {
                    addBpm()
                } label: {
                    Label("添加", systemImage: "plus.circle.fill")
                }
                .disabled(Double(newBeat) == nil || Double(newBpm) == nil)
            }

            Section("BPM 变化点预览") {
                ForEach(Array(project.chart.BPMList.enumerated()), id: \.offset) { idx, bpm in
                    HStack {
                        Text("段 \(idx + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("拍 \(BeatMath.display(bpm.startTime.value)) → \(BeatMath.clock(timeline.time(atBeat: bpm.startTime.value)))")
                            .font(.caption.monospaced())
                    }
                }
            }
        }
    }

    private func addBpm() {
        guard let beat = Double(newBeat), let bpm = Double(newBpm), bpm > 0 else { return }
        project.chart.BPMList.append(BPMEvent(startTime: Beat(value: beat), bpm: bpm))
        project.chart.BPMList.sort { $0.startTime.value < $1.startTime.value }
        newBeat = ""
        newBpm = ""
    }

    private func fmt(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.contains(".") && s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
