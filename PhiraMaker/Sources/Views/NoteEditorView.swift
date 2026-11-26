import SwiftUI

/// 钢琴卷帘式音符编辑器
/// 横轴 = 音符 X 位置（-675…675 映射到屏幕宽度）
/// 纵轴 = 时间（拍），向下滚动
struct NoteEditorView: View {
    @Binding var project: ChartProject
    @Binding var selectedLineIndex: Int
    @Binding var selectedNoteID: UUID?

    @State private var division: Int = 4
    @State private var pixelsPerBeat: CGFloat = 64
    @State private var noteTypeToAdd: NoteType = .tap
    @State private var showInspector = false

    private var bpmTimeline: BpmTimeline { BpmTimeline(bpmList: project.chart.BPMList) }
    private var line: JudgeLine? {
        guard project.chart.judgeLineList.indices.contains(selectedLineIndex) else { return nil }
        return project.chart.judgeLineList[selectedLineIndex]
    }
    private var notes: [Note] {
        line?.notes.sorted { $0.startTime.value < $1.startTime.value } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if line == nil {
                ContentUnavailableView("没有判定线", systemImage: "line.diagonal",
                                       description: Text("先在「判定线」页添加一条"))
            } else {
                gridArea
            }
            Divider()
            inspector
        }
        .sheet(isPresented: $showInspector) {
            if let id = selectedNoteID, let note = bindingForNote(id) {
                NoteDetailEditor(note: note, division: division, bpmTimeline: bpmTimeline)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 顶部工具条

    private var header: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(project.chart.judgeLineList.enumerated()), id: \.offset) { idx, l in
                        Button {
                            selectedLineIndex = idx
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.diagonal")
                                    .font(.caption2)
                                Text(l.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(idx == selectedLineIndex ? Color.accentColor : Color.secondary.opacity(0.2),
                                        in: Capsule())
                            .foregroundStyle(idx == selectedLineIndex ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 12) {
                // 音符类型
                Picker("类型", selection: $noteTypeToAdd) {
                    ForEach(NoteType.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Spacer(minLength: 0)

                // 吸附精度
                Menu {
                    ForEach([1, 2, 4, 8, 12, 16], id: \.self) { d in
                        Button("1/\(d) 拍") { division = d }
                    }
                } label: {
                    Text("1/\(division)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    // MARK: - 网格

    private var gridArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let contentBeats = max(16.0, (notes.last.map { $0.startTime.value + 16 } ?? 32))
            let contentHeight = CGFloat(contentBeats) * pixelsPerBeat

            ScrollView([.vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        drawGrid(context: context, size: size,
                                 width: width, contentBeats: contentBeats)
                    }
                    .frame(width: width, height: contentHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleTap(at: value.location, width: width)
                            }
                    )

                    // 音符层
                    ForEach(notes) { note in
                        noteView(note, width: width)
                    }
                }
                .frame(width: width, height: contentHeight, alignment: .topLeading)
            }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize,
                          width: CGFloat, contentBeats: Double) {
        let totalBeats = Int(contentBeats)

        // 拍线
        for beat in 0...totalBeats {
            let y = CGFloat(beat) * pixelsPerBeat
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            let isBar = beat % 4 == 0
            context.stroke(path,
                           with: .color(isBar ? .white.opacity(0.25) : .white.opacity(0.08)),
                           lineWidth: isBar ? 1.2 : 0.6)
        }

        // X 中心线
        var centerPath = Path()
        centerPath.move(to: CGPoint(x: size.width / 2, y: 0))
        centerPath.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        context.stroke(centerPath, with: .color(.white.opacity(0.12)), lineWidth: 0.8)
    }

    private func noteView(_ note: Note, width: CGFloat) -> some View {
        let x = xPosition(note.positionX, width: width)
        let y = CGFloat(note.startTime.value) * pixelsPerBeat
        let isSelected = note.id == selectedNoteID
        let color = colorFor(note.type)
        let holdHeight: CGFloat = note.isHold
            ? max(8, CGFloat(note.endTime.value - note.startTime.value) * pixelsPerBeat)
            : 0

        return ZStack(alignment: .topLeading) {
            if note.isHold {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.45))
                    .frame(width: 22, height: holdHeight)
                    .position(x: x, y: y + holdHeight / 2)
            }
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay {
                    if isSelected {
                        Circle().stroke(Color.white, lineWidth: 2.5)
                    }
                }
                .overlay {
                    Text(note.type.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .position(x: x, y: y)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedNoteID = note.id
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            selectedNoteID = note.id
            showInspector = true
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteNote(note.id)
            } label: {
                Label("删除音符", systemImage: "trash")
            }
        }
    }

    // MARK: - 底部检查器

    private var inspector: some View {
        HStack(spacing: 16) {
            if let id = selectedNoteID, let note = noteByID(id) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(note.type.label) · 拍 \(BeatMath.display(note.startTime.value))")
                        .font(.subheadline.bold())
                    Text("X \(Int(note.positionX)) · 时间 \(BeatMath.clock(bpmTimeline.time(atBeat: note.startTime.value)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showInspector = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    deleteNote(id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            } else {
                Label("点网格加音符，长按音符编辑", systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - 交互

    private func handleTap(at point: CGPoint, width: CGFloat) {
        // 命中已有音符则选中
        for note in notes {
            let nx = xPosition(note.positionX, width: width)
            let ny = CGFloat(note.startTime.value) * pixelsPerBeat
            if hypot(point.x - nx, point.y - ny) < 22 {
                selectedNoteID = note.id
                return
            }
        }
        // 否则新建
        let beat = BeatMath.snap(Double(point.y / pixelsPerBeat), division: division)
        let xValue = Double((point.x - width / 2) / (width / 2)) * 675.0
        var newNote = Note(type: noteTypeToAdd,
                           startTime: Beat(value: beat),
                           endTime: Beat(value: beat + (noteTypeToAdd == .hold ? 1 : 0)),
                           positionX: max(-675, min(675, xValue)))
        guard project.chart.judgeLineList.indices.contains(selectedLineIndex) else { return }
        let newID = newNote.id
        project.chart.judgeLineList[selectedLineIndex].notes.append(newNote)
        selectedNoteID = newID
    }

    private func xPosition(_ value: Double, width: CGFloat) -> CGFloat {
        let normalized = (value + 675) / 1350.0
        return CGFloat(normalized) * width
    }

    private func colorFor(_ type: NoteType) -> Color {
        switch type {
        case .tap: return .cyan
        case .hold: return .orange
        case .flick: return .pink
        case .drag: return .green
        }
    }

    private func noteByID(_ id: UUID) -> Note? {
        guard project.chart.judgeLineList.indices.contains(selectedLineIndex) else { return nil }
        return project.chart.judgeLineList[selectedLineIndex].notes.first { $0.id == id }
    }

    private func deleteNote(_ id: UUID) {
        guard project.chart.judgeLineList.indices.contains(selectedLineIndex) else { return }
        project.chart.judgeLineList[selectedLineIndex].notes.removeAll { $0.id == id }
        if selectedNoteID == id { selectedNoteID = nil }
    }

    private func bindingForNote(_ id: UUID) -> Binding<Note>? {
        guard project.chart.judgeLineList.indices.contains(selectedLineIndex),
              let idx = project.chart.judgeLineList[selectedLineIndex].notes.firstIndex(where: { $0.id == id })
        else { return nil }
        return $project.chart.judgeLineList[selectedLineIndex].notes[idx]
    }
}

// MARK: - 音符详情编辑

struct NoteDetailEditor: View {
    @Binding var note: Note
    let division: Int
    let bpmTimeline: BpmTimeline
    @Environment(\.dismiss) private var dismiss

    @State private var beatText: String = ""
    @State private var endBeatText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("音符类型", selection: $note.type) {
                        ForEach(NoteType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("时间") {
                    HStack {
                        Text("开始拍")
                        Spacer()
                        TextField("拍", text: $beatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .onSubmit { applyBeat() }
                    }
                    if note.type == .hold {
                        HStack {
                            Text("结束拍")
                            Spacer()
                            TextField("拍", text: $endBeatText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                                .onSubmit { applyEndBeat() }
                        }
                    }
                    HStack {
                        Text("时间")
                        Spacer()
                        Text(BeatMath.clock(bpmTimeline.time(atBeat: note.startTime.value)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Section("位置与外观") {
                    HStack {
                        Text("X 位置")
                        Slider(value: $note.positionX, in: -675...675, step: 1)
                    }
                    Text("\(Int(note.positionX))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("大小")
                        Slider(value: $note.size, in: 0.1...3, step: 0.1)
                        Text(String(format: "%.1f", note.size))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("速度")
                        Slider(value: $note.speed, in: 0.1...3, step: 0.1)
                        Text(String(format: "%.1f", note.speed))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("不透明度")
                        Slider(value: Binding(
                            get: { Double(note.alpha) },
                            set: { note.alpha = Int($0) }
                        ), in: 0...255, step: 1)
                        Text("\(note.alpha)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section("判定线") {
                    if note.isHold {
                        Toggle("Hold 半透明遮罩在尾部", isOn: .constant(false))
                            .disabled(true)
                    }
                    Text("音符挂在判定线上，位置 X 相对于判定线中心")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑音符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                beatText = BeatMath.display(note.startTime.value)
                endBeatText = BeatMath.display(note.endTime.value)
            }
        }
    }

    private func applyBeat() {
        if let v = Double(beatText) {
            note.startTime = Beat(value: v)
            if note.endTime.value < note.startTime.value {
                note.endTime = note.startTime
            }
            endBeatText = BeatMath.display(note.endTime.value)
        } else {
            beatText = BeatMath.display(note.startTime.value)
        }
    }

    private func applyEndBeat() {
        if let v = Double(endBeatText), v >= note.startTime.value {
            note.endTime = Beat(value: v)
        } else {
            endBeatText = BeatMath.display(note.endTime.value)
        }
    }
}
