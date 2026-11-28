import SwiftUI
import UniformTypeIdentifiers

struct InfoEditorView: View {
    @Binding var project: ChartProject

    @State private var importingKind: ChartAsset.Kind?
    private let accent = Color.pink

    var body: some View {
        Form {
            Section {
                labeledField("谱面名称", text: $project.info.name)
                labeledField("难度等级", text: $project.info.level)
                HStack {
                    Text("难度值")
                    Spacer()
                    TextField("10", value: $project.info.difficulty, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                labeledField("谱师", text: $project.info.charter)
                labeledField("曲师", text: $project.info.composer)
                labeledField("曲绘", text: $project.info.illustrator)
            } header: {
                Text("基本信息")
            } footer: {
                Text("难度等级会显示在游戏右下角，如「IN Lv.15」；难度值用于排序。")
            }

            Section("格式") {
                Picker("谱面格式", selection: $project.format) {
                    ForEach(ChartFormat.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                Text("RPE 是 Phira 最主要的格式，推荐使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("资源") {
                assetRow(kind: .music, title: "音乐", systemImage: "waveform",
                         ext: ["mp3", "ogg", "wav", "flac", "aac"])
                assetRow(kind: .illustration, title: "插图", systemImage: "photo",
                         ext: ["png", "jpg", "jpeg", "webp"])
            }

            Section("播放设置") {
                HStack {
                    Text("预览开始")
                    Spacer()
                    TextField("0", value: $project.info.previewStart, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("秒").foregroundStyle(.secondary)
                }
                HStack {
                    Text("偏移")
                    Spacer()
                    TextField("0", value: $project.info.offset, format: .number)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("秒").foregroundStyle(.secondary)
                }
                HStack {
                    Text("背景暗化")
                    Slider(value: $project.info.backgroundDim, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", project.info.backgroundDim))
                        .font(.caption.monospaced())
                        .frame(width: 40)
                }
                HStack {
                    Text("判定线长度")
                    Slider(value: $project.info.lineLength, in: 1...20, step: 0.5)
                    Text(String(format: "%.1f", project.info.lineLength))
                        .font(.caption.monospaced())
                        .frame(width: 40)
                }
            }

            Section("其他") {
                TextField("标签（逗号分隔）", text: tagsBinding)
                TextField("简介", text: $project.info.intro, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .fileImporter(isPresented: Binding(
            get: { importingKind != nil },
            set: { if !$0 { importingKind = nil } }
        ), allowedContentTypes: allowedTypes, allowsMultipleSelection: false) { result in
            handleAssetImport(result)
        }
    }

    private var allowedTypes: [UTType] {
        guard let kind = importingKind else { return [.data] }
        switch kind {
        case .music: return [.audio, .mp3, .wav]
        case .illustration: return [.image]
        case .unlockVideo: return [.movie]
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func assetRow(kind: ChartAsset.Kind, title: String, systemImage: String, ext: [String]) -> some View {
        let asset = project.assets.first { $0.kind == kind }
        return HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let asset = asset {
                Text(asset.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(role: .destructive) {
                    project.assets.removeAll { $0.kind == kind }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button("选择文件") {
                    importingKind = kind
                }
                .font(.subheadline)
            }
        }
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { project.info.tags.joined(separator: ", ") },
            set: { newValue in
                project.info.tags = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func handleAssetImport(_ result: Result<[URL], Error>) {
        guard let kind = importingKind else { return }
        defer { importingKind = nil }
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

            // 同步 info.yml 里的文件名
            switch kind {
            case .music: project.info.music = fileName
            case .illustration: project.info.illustration = fileName
            case .unlockVideo: project.info.unlockVideo = fileName
            }
        } catch {
            // 忽略
        }
    }
}
