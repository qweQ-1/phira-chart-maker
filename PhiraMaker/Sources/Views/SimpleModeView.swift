import SwiftUI
import UniformTypeIdentifiers

/// 新手模式：4 步向导做谱，不用理解判定线/事件层/缓动。
/// 第 1 步 起名和难度 → 第 2 步 点格子铺音符 → 第 3 步 加音乐插图 → 第 4 步 导出。
struct SimpleModeView: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var project = ChartProject()
    @State private var bpmText = "120"
    @State private var noteType: NoteType = .tap
    @State private var importing: ChartAsset.Kind?
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var validationReport: [String] = []
    @State private var showValidation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var saved = false

    private let steps = ["基本信息", "铺音符", "音乐插图", "导出"]
    private let totalSlots = 32 // 32 拍，够新手用

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepBar
                Divider()

                ScrollView {
                    switch step {
                    case 0: stepBasics
                    case 1: stepNotes
                    case 2: stepAssets
                    default: stepExport
                    }
                }

                Divider()
                bottomBar
            }
            .navigationTitle("新手模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("退出") { dismiss() }
                }
            }
            .onAppear(perform: setup)
            .fileImporter(
                isPresented: Binding(
                    get: { importing != nil },
                    set: { if !$0 { importing = nil } }
                ),
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showShare) {
                if let url = exportURL { ShareSheet(items: [url]) }
            }
            .sheet(isPresented: $showValidation) {
                validationSheet
            }
            .alert("提示", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 步骤指示

    private var stepBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { i in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                    Text(steps[i])
                        .font(.caption2)
                        .foregroundStyle(i == step ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - 第 1 步：基本信息

    private var stepBasics: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerCard(
                icon: "music.note",
                title: "给谱面起个名字",
                desc: "随便写，之后都能改"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("谱面名称").font(.subheadline.bold())
                TextField("例如：星夜", text: $project.info.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("难度").font(.subheadline.bold())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                    ForEach(Array(SimpleGenerator.difficulties.enumerated()), id: \.offset) { idx, preset in
                        Button {
                            SimpleGenerator.applyDifficulty(idx, to: &project)
                        } label: {
                            VStack(spacing: 2) {
                                Text(preset.name).font(.headline)
                                Text("Lv.\(Int(preset.value))").font(.system(size: 9))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                project.info.level == preset.level
                                    ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .foregroundStyle(project.info.level == preset.level ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("BPM（速度）").font(.subheadline.bold())
                HStack {
                    TextField("120", text: $bpmText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: bpmText) { _, newValue in
                            if let v = Double(newValue) {
                                SimpleGenerator.setBPM(v, in: &project)
                            }
                        }
                    Text("拍/分钟").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SimpleGenerator.commonBpms, id: \.self) { bpm in
                            Button("\(Int(bpm))") {
                                bpmText = "\(Int(bpm))"
                                SimpleGenerator.setBPM(bpm, in: &project)
                            }
                            .font(.caption.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("谱师").font(.subheadline.bold())
                TextField("你的名字", text: $project.info.charter)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
    }

    // MARK: - 第 2 步：铺音符

    private var stepNotes: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerCard(
                icon: "hand.tap",
                title: "点格子放音符",
                desc: "横着是时间，竖着是位置。再点一次可删除。"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("当前音符").font(.subheadline.bold())
                HStack(spacing: 8) {
                    ForEach(NoteType.allCases) { type in
                        Button {
                            noteType = type
                        } label: {
                            VStack(spacing: 2) {
                                Text(type.symbol).font(.title3)
                                Text(type.label).font(.system(size: 10))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                noteType == type ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .foregroundStyle(noteType == type ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("音符网格").font(.subheadline.bold())
                    Spacer()
                    Button {
                        SimpleGenerator.applyDemo(to: &project)
                    } label: {
                        Label("放入示例", systemImage: "wand.and.stars")
                            .font(.caption)
                    }
                    Button(role: .destructive) {
                        if project.chart.judgeLineList.indices.contains(0) {
                            project.chart.judgeLineList[0].notes.removeAll()
                        }
                    } label: {
                        Text("清空").font(.caption)
                    }
                }

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            ForEach(0..<totalSlots, id: \.self) { slot in
                                Text(slot % 4 == 0 ? "\(slot / 4 + 1)" : "")
                                    .font(.system(size: 9))
                                    .frame(width: 28, alignment: .leading)
                            }
                        }
                        ForEach(0..<SimpleGenerator.trackX.count, id: \.self) { track in
                            HStack(spacing: 2) {
                                ForEach(0..<totalSlots, id: \.self) { slot in
                                    gridCell(track: track, slot: slot)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 260)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Image(systemName: "info.circle")
                Text("已有 \(noteCount) 个音符。Hold 会自动延长 1 拍。")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func gridCell(track: Int, slot: Int) -> some View {
        let existing = note(at: slot, track: track)
        return Button {
            toggleNote(track: track, slot: slot)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellColor(slot: slot, existing: existing))
                    .frame(width: 28, height: 44)
                if let note = existing {
                    Text(note.type.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func cellColor(slot: Int, existing: Note?) -> Color {
        if let note = existing { return colorFor(note.type) }
        return slot % 4 == 0
            ? Color.secondary.opacity(0.28)
            : Color.secondary.opacity(0.12)
    }

    // MARK: - 第 3 步：资源

    private var stepAssets: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerCard(
                icon: "waveform",
                title: "加上音乐和插图",
                desc: "可以跳过，但加上才像一首完整谱面"
            )

            assetCard(
                kind: .music,
                title: "音乐",
                desc: "mp3 / ogg / wav",
                icon: "music.note"
            )
            assetCard(
                kind: .illustration,
                title: "背景插图",
                desc: "png / jpg",
                icon: "photo"
            )

            HStack {
                Image(systemName: "lightbulb")
                Text("没有音乐也能导出，之后可在「信息」页补上。")
                    .font(.caption)
            }
            .foregroundStyle(.orange)
        }
        .padding()
    }

    private func assetCard(kind: ChartAsset.Kind, title: String, desc: String, icon: String) -> some View {
        let asset = project.assets.first { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold())
                    Text(desc).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if asset != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            HStack {
                Button {
                    importing = kind
                } label: {
                    Label(asset == nil ? "选择文件" : "更换", systemImage: "folder")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                if asset != nil {
                    Button(role: .destructive) {
                        project.assets.removeAll { $0.kind == kind }
                    } label: {
                        Text("移除").font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                if let asset = asset {
                    Text(asset.originalName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 第 4 步：导出

    private var stepExport: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerCard(
                icon: "square.and.arrow.up",
                title: "做好了！",
                desc: "导出 .zip 后，在 Phira 的「导入谱面」里选它"
            )

            VStack(alignment: .leading, spacing: 12) {
                summaryRow("名称", project.info.name)
                summaryRow("难度", project.info.level)
                summaryRow("BPM", bpmText)
                summaryRow("音符", "\(noteCount) 个")
                summaryRow("音乐", project.music?.fileName ?? "未添加")
                summaryRow("插图", project.illustration?.fileName ?? "未添加")
            }
            .padding()
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            Button {
                runValidation()
            } label: {
                Label("检查谱面包", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                doExport()
            } label: {
                Label("导出 Phira 谱面包 (.zip)", systemImage: "square.and.arrow.up")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(noteCount == 0)

            if noteCount == 0 {
                Text("至少放一个音符才能导出")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                saveAndOpenAdvanced()
            } label: {
                Label("保存并用高级编辑器继续编辑", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.bold()).lineLimit(1)
        }
    }

    // MARK: - 底部导航

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Label("上一步", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if step < steps.count - 1 {
                Button {
                    if step == 0 && project.info.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        project.info.name = "我的谱面"
                    }
                    withAnimation { step += 1 }
                } label: {
                    HStack {
                        Text("下一步")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - 通用 UI

    private func headerCard(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var validationSheet: some View {
        NavigationStack {
            List(validationReport, id: \.self) { line in
                Text(line).font(.callout.monospaced())
            }
            .navigationTitle("谱面包自检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showValidation = false }
                }
            }
        }
    }

    // MARK: - 逻辑

    private func setup() {
        project = ChartProject()
        project.info.name = "我的谱面"
        SimpleGenerator.setBPM(120, in: &project)
        SimpleGenerator.applyDifficulty(1, to: &project)
        if project.chart.judgeLineList.isEmpty {
            project.chart.judgeLineList.append(JudgeLine(name: "主判定线"))
        }
    }

    private var noteCount: Int {
        project.chart.judgeLineList.first?.notes.count ?? 0
    }

    private func note(at slot: Int, track: Int) -> Note? {
        guard project.chart.judgeLineList.indices.contains(0) else { return nil }
        let x = SimpleGenerator.trackX[track]
        let beat = Double(slot)
        return project.chart.judgeLineList[0].notes.first {
            abs($0.startTime.value - beat) < 0.01 && abs($0.positionX - x) < 1
        }
    }

    private func toggleNote(track: Int, slot: Int) {
        guard project.chart.judgeLineList.indices.contains(0) else { return }
        if let existing = note(at: slot, track: track),
           let idx = project.chart.judgeLineList[0].notes.firstIndex(where: { $0.id == existing.id }) {
            project.chart.judgeLineList[0].notes.remove(at: idx)
            return
        }
        let beat = Double(slot)
        let newNote = Note(
            type: noteType,
            startTime: Beat(value: beat),
            endTime: Beat(value: beat + (noteType == .hold ? 1 : 0)),
            positionX: SimpleGenerator.trackX[track]
        )
        project.chart.judgeLineList[0].notes.append(newNote)
    }

    private func colorFor(_ type: NoteType) -> Color {
        switch type {
        case .tap: return .cyan
        case .hold: return .orange
        case .flick: return .pink
        case .drag: return .green
        }
    }

    private var allowedTypes: [UTType] {
        switch importing {
        case .music: return [.audio, .mp3, .wav]
        case .illustration: return [.image]
        case .unlockVideo: return [.movie]
        case .none: return [.data]
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let kind = importing else { return }
        defer { importing = nil }
        do {
            guard let url = try result.get().first else { return }
            let (data, originalName) = try ImportHelper.readSecurely(from: url)
            let ext = (originalName as NSString).pathExtension.lowercased()
            let fileName: String
            switch kind {
            case .music: fileName = "song.\(ext.isEmpty ? "mp3" : ext)"
            case .illustration: fileName = "background.\(ext.isEmpty ? "png" : ext)"
            case .unlockVideo: fileName = "unlock.\(ext.isEmpty ? "mp4" : ext)"
            }
            project.assets.removeAll { $0.kind == kind }
            project.assets.append(ChartAsset(kind: kind,
                                             fileName: fileName,
                                             data: data,
                                             originalName: originalName))
            switch kind {
            case .music: project.info.music = fileName
            case .illustration: project.info.illustration = fileName
            case .unlockVideo: project.info.unlockVideo = fileName
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func runValidation() {
        do {
            let data = try project.exportArchive()
            validationReport = Validator.validate(archive: data)
        } catch {
            validationReport = ["❌ 打包失败：\(error.localizedDescription)"]
        }
        showValidation = true
    }

    private func doExport() {
        do {
            let data = try project.exportArchive()
            let name = project.info.name.isEmpty ? "chart" : project.info.name
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "_")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).zip")
            try data.write(to: url, options: .atomic)
            exportURL = url
            saveProject()
            showShare = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func saveAndOpenAdvanced() {
        saveProject()
        dismiss()
    }

    private func saveProject() {
        if !saved {
            store.importProject(project)
            saved = true
        } else {
            store.update(project)
        }
    }
}
