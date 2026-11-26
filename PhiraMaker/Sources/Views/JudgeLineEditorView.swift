import SwiftUI

struct JudgeLineEditorView: View {
    @Binding var project: ChartProject
    @Binding var selectedLineIndex: Int
    @State private var editingIndex: Int?

    var body: some View {
        List {
            Section {
                ForEach(Array(project.chart.judgeLineList.enumerated()), id: \.offset) { idx, line in
                    Button {
                        selectedLineIndex = idx
                        editingIndex = idx
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(idx == selectedLineIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                                    .frame(width: 28, height: 28)
                                Text("\(idx)")
                                    .font(.caption.bold().monospaced())
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text("\(line.notes.count) 音符 · Z \(line.zOrder)\(line.father >= 0 ? " · 父线 \(line.father)" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if idx == selectedLineIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    project.chart.judgeLineList.remove(atOffsets: offsets)
                    if selectedLineIndex >= project.chart.judgeLineList.count {
                        selectedLineIndex = max(0, project.chart.judgeLineList.count - 1)
                    }
                }

                Button {
                    let newIndex = project.chart.judgeLineList.count
                    project.chart.judgeLineList.append(JudgeLine(name: "判定线 \(newIndex)"))
                    selectedLineIndex = newIndex
                } label: {
                    Label("添加判定线", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("判定线列表")
            } footer: {
                Text("Phira 谱面的音符都挂在判定线上；判定线越靠前的 Z 值越小（越靠底层）。")
            }

            if project.chart.judgeLineList.indices.contains(selectedLineIndex) {
                Section("当前判定线属性") {
                    TextField("名称", text: $project.chart.judgeLineList[selectedLineIndex].name)

                    HStack {
                        Text("Z 层级")
                        Spacer()
                        Stepper("\(project.chart.judgeLineList[selectedLineIndex].zOrder)",
                                value: $project.chart.judgeLineList[selectedLineIndex].zOrder,
                                in: -100...100)
                    }

                    HStack {
                        Text("父线")
                        Spacer()
                        Picker("", selection: $project.chart.judgeLineList[selectedLineIndex].father) {
                            Text("无").tag(-1)
                            ForEach(0..<project.chart.judgeLineList.count, id: \.self) { i in
                                if i != selectedLineIndex {
                                    Text("判定线 \(i)").tag(i)
                                }
                            }
                        }
                        .labelsHidden()
                    }

                    Toggle("跟随父线旋转", isOn: $project.chart.judgeLineList[selectedLineIndex].rotateWithFather)

                    Toggle("背面音符被遮挡", isOn: Binding(
                        get: { project.chart.judgeLineList[selectedLineIndex].isCover == 1 },
                        set: { project.chart.judgeLineList[selectedLineIndex].isCover = $0 ? 1 : 0 }
                    ))

                    TextField("纹理（默认 line.png）", text: $project.chart.judgeLineList[selectedLineIndex].texture)
                }

                Section("事件层") {
                    ForEach(Array(project.chart.judgeLineList[selectedLineIndex].eventLayers.enumerated()), id: \.offset) { layerIdx, layer in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("层 \(layerIdx + 1)")
                                .font(.subheadline.bold())
                            HStack(spacing: 12) {
                                eventCount("移动X", layer.moveXEvents.count)
                                eventCount("移动Y", layer.moveYEvents.count)
                                eventCount("旋转", layer.rotateEvents.count)
                                eventCount("透明", layer.alphaEvents.count)
                                eventCount("流速", layer.speedEvents.count)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        project.chart.judgeLineList[selectedLineIndex].eventLayers.append(EventLayer())
                    } label: {
                        Label("添加事件层", systemImage: "plus.square.on.square")
                    }
                }

                Section {
                    EventListEditor(title: "移动 X", events: $project.chart.judgeLineList[selectedLineIndex].eventLayers[0].moveXEvents)
                    EventListEditor(title: "移动 Y", events: $project.chart.judgeLineList[selectedLineIndex].eventLayers[0].moveYEvents)
                    EventListEditor(title: "旋转", events: $project.chart.judgeLineList[selectedLineIndex].eventLayers[0].rotateEvents)
                    EventListEditor(title: "不透明度", events: $project.chart.judgeLineList[selectedLineIndex].eventLayers[0].alphaEvents)
                    EventListEditor(title: "流速", events: $project.chart.judgeLineList[selectedLineIndex].eventLayers[0].speedEvents)
                } header: {
                    Text("第 1 层事件")
                } footer: {
                    Text("X 范围 -675…675，Y 范围 -450…450，不透明度 0…255，流速默认 1.0。")
                }
            }
        }
    }

    private func eventCount(_ label: String, _ count: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.caption.bold().monospaced())
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

/// 事件列表编辑器
struct EventListEditor: View {
    let title: String
    @Binding var events: [LineEvent]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(Array(events.enumerated()), id: \.offset) { idx, _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("拍 \(BeatMath.display(events[idx].startTime.value)) → \(BeatMath.display(events[idx].endTime.value))")
                            .font(.caption.monospaced())
                        Spacer()
                        Button(role: .destructive) {
                            events.remove(at: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Text("起")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("起", value: $events[idx].start, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                        Text("止")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("止", value: $events[idx].end, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("缓动")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $events[idx].easingType) {
                            ForEach(EasingType.allCases) { e in
                                Text(e.label).tag(e.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                let last = events.last?.endTime ?? Beat(i: 0)
                events.append(LineEvent(startTime: last, endTime: Beat(value: last.value + 1), start: 0, end: 0))
            } label: {
                Label("添加事件", systemImage: "plus")
                    .font(.caption)
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(events.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
