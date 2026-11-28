import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var showingError = false
    @State private var showSimpleMode = false
    @AppStorage("phira.showedModeTip") private var showedModeTip = false
    @State private var showModeTip = false

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(store.projects.enumerated()), id: \.offset) { index, project in
                            NavigationLink {
                                ChartEditorView(index: index)
                            } label: {
                                row(project)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Phira 谱面工坊")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSimpleMode = true
                    } label: {
                        Label("新手", systemImage: "wand.and.stars")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            showingImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Button {
                            store.addNew()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSimpleMode) {
                SimpleModeView()
                    .environmentObject(store)
            }
            .onAppear {
                if !showedModeTip {
                    showModeTip = true
                    showedModeTip = true
                }
            }
            .alert("两种模式", isPresented: $showModeTip) {
                Button("知道了") {}
            } message: {
                Text("第一次用？点左上角「新手」，4 步就能做出能导入 Phira 的谱面包。熟悉后可回主页用「+」进高级编辑器。")
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.zip, .json, .item],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("导入失败", isPresented: $showingError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "未知错误")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("还没有谱面")
                .font(.title2.bold())
            Text("第一次做谱？用「新手模式」4 步搞定。\n熟悉后可用高级编辑器做更精细的谱面。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    showSimpleMode = true
                } label: {
                    Label("新手模式（推荐）", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 12) {
                    Button {
                        store.addNew()
                    } label: {
                        Label("高级新建", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 32)
        }
        .padding()
    }

    private func row(_ project: ChartProject) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.pink.opacity(0.7), .purple.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "music.note.list")
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.info.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(project.info.level)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                    Text(project.info.charter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(totalNotes(project)) notes · \(project.format.label)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func totalNotes(_ project: ChartProject) -> Int {
        project.chart.judgeLineList.reduce(0) { $0 + $1.notes.count }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)

            if url.pathExtension.lowercased() == "json" {
                // 单独导入 RPE 谱面文件
                let chart = try RPEFormat.decode(data)
                var project = ChartProject()
                project.chart = chart
                project.info.name = chart.META.name
                project.info.level = chart.META.level
                project.info.charter = chart.META.charter
                project.info.composer = chart.META.composer
                project.info.illustrator = chart.META.illustration
                project.info.offset = Float(chart.META.offset) / 1000.0
                store.importProject(project)
            } else {
                let project = try ChartProject.importArchive(data)
                store.importProject(project)
            }
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }
}
