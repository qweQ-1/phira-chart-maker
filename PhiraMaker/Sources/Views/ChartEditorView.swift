import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChartEditorView: View {
    let index: Int

    @EnvironmentObject var store: ProjectStore
    @State private var project = ChartProject()
    @State private var loaded = false

    @State private var selectedLineIndex = 0
    @State private var selectedNoteID: UUID?
    @State private var tab = 0

    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showExportError = false
    @State private var showShare = false
    @State private var validationReport: [String] = []
    @State private var showValidation = false

    var body: some View {
        TabView(selection: $tab) {
            NoteEditorView(project: $project,
                           selectedLineIndex: $selectedLineIndex,
                           selectedNoteID: $selectedNoteID)
                .tabItem { Label("音符", systemImage: "music.note") }
                .tag(0)

            JudgeLineEditorView(project: $project, selectedLineIndex: $selectedLineIndex)
                .tabItem { Label("判定线", systemImage: "line.diagonal") }
                .tag(1)

            BPMEditorView(project: $project)
                .tabItem { Label("BPM", systemImage: "metronome") }
                .tag(2)

            InfoEditorView(project: $project)
                .tabItem { Label("信息", systemImage: "info.circle") }
                .tag(3)

            exportView
                .tabItem { Label("导出", systemImage: "square.and.arrow.up") }
                .tag(4)
        }
        .navigationTitle(project.info.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadIfNeeded)
        .onDisappear { store.update(project) }
        .onChange(of: project.info.name) { _, _ in store.update(project) }
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("导出失败", isPresented: $showExportError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportError ?? "未知错误")
        }
        .sheet(isPresented: $showValidation) {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.update(project)
                } label: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - 导出页

    private var exportView: some View {
        List {
            Section {
                HStack {
                    Label("判定线", systemImage: "line.diagonal")
                    Spacer()
                    Text("\(project.chart.judgeLineList.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("音符", systemImage: "music.note")
                    Spacer()
                    Text("\(totalNotes)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("BPM 段", systemImage: "metronome")
                    Spacer()
                    Text("\(project.chart.BPMList.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("音乐", systemImage: "waveform")
                    Spacer()
                    Text(project.music?.fileName ?? "未添加")
                        .foregroundStyle(project.music == nil ? .orange : .secondary)
                }
                HStack {
                    Label("插图", systemImage: "photo")
                    Spacer()
                    Text(project.illustration?.fileName ?? "未添加")
                        .foregroundStyle(project.illustration == nil ? .orange : .secondary)
                }
            } header: {
                Text("谱面概况")
            }

            Section {
                Button {
                    runValidation()
                } label: {
                    Label("校验谱面包", systemImage: "checkmark.shield")
                }
                Button {
                    doExport()
                } label: {
                    Label("导出 Phira 谱面包 (.zip)", systemImage: "square.and.arrow.up")
                        .bold()
                }
            } footer: {
                Text("导出的 .zip 可直接在 Phira 里「导入谱面」使用：包内含 info.yml、谱面文件、音乐和插图。")
            }

            Section("说明") {
                Text("• Phira 谱面标准以 info.yml 为准\n• 支持导出 RPE(.json) 与 PEC(.pec) 两种谱面格式\n• 音乐建议用 .ogg（mp3 可能有延迟）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var totalNotes: Int {
        project.chart.judgeLineList.reduce(0) { $0 + $1.notes.count }
    }

    // MARK: - 动作

    private func loadIfNeeded() {
        guard !loaded else { return }
        if store.projects.indices.contains(index) {
            project = store.projects[index]
        }
        loaded = true
    }

    private func runValidation() {
        do {
            let data = try project.exportArchive()
            validationReport = Validator.validate(archive: data)
            // 追加尺寸信息
            validationReport.append("📦 谱面包大小：\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        } catch {
            validationReport = ["❌ 打包失败：\(error.localizedDescription)"]
        }
        showValidation = true
    }

    private func doExport() {
        do {
            let data = try project.exportArchive()
            let name = sanitize(project.info.name.isEmpty ? "chart" : project.info.name)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).zip")
            try data.write(to: url, options: .atomic)
            exportURL = url
            store.update(project)
            showShare = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}

// MARK: - 分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
