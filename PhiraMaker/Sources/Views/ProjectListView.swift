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
    @State private var showImportHelp = false
    @State private var showInboxList = false
    @State private var refreshInbox = UUID()

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
                            showImportHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        Button {
                            // 自签名 App（尤其 Gbox）里系统文件选择器常无响应，
                            // 默认走 App 内文件浏览器扫 Documents / Inbox
                            showInboxList = true
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
                          // 自签名 App 里过滤太严会导致文件变灰选不了，放行全部文件
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .onOpenURL { url in
                // Gbox / 文件 App 通过「打开方式」传进来的 file:// URL
                guard url.isFileURL else { return }
                importFromInbox(url)
            }
            .sheet(isPresented: $showImportHelp) {
                importHelpSheet
            }
            .sheet(isPresented: $showInboxList) {
                inboxSheet
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
                        showInboxList = true
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
            // 关键：自签名 App 直接读安全作用域 URL 常失败，先复制到临时目录
            let (data, name) = try ImportHelper.readSecurely(from: url)
            try importData(data, named: name)
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }

    private func importData(_ data: Data, named name: String) throws {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "json" || ext == "pec" {
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
    }

    private func importFromInbox(_ url: URL) {
        do {
            let (data, name) = try ImportHelper.readSecurely(from: url)
            try importData(data, named: name)
            showInboxList = false
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }

    // MARK: - 导入帮助

    private var importHelpSheet: some View {
        NavigationStack {
            List {
                Section("方式一：App 内导入") {
                    Text("点主页右上角的下载图标，在系统文件选择器里找到 .zip 谱面包。如果文件是灰的选不了，换方式二。")
                        .font(.subheadline)
                }
                Section("方式二：文件共享（自签名推荐）") {
                    Text("1. 打开「文件」App → 浏览 → 我的 iPhone/iPad\n2. 找到「Phira 谱面工坊」文件夹\n3. 把 .zip 谱面包复制进去\n4. 回到本 App，点下方「扫描文件共享目录」")
                        .font(.subheadline)
                }
                Section("方式三：从「文件」App 分享") {
                    Text("在「文件」App 里长按 .zip → 分享 → 选 Phira 谱面工坊。分享进来的文件会出现在下方列表。")
                        .font(.subheadline)
                }
                Section {
                    Button {
                        showImportHelp = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showInboxList = true
                        }
                    } label: {
                        Label("扫描文件共享 / 分享进来的文件", systemImage: "folder.badge.gearshape")
                    }
                }
            }
            .navigationTitle("怎么导入文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showImportHelp = false }
                }
            }
        }
    }

    private var inboxSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("用系统文件选择器选文件", systemImage: "folder")
                    }
                    Button {
                        refreshInbox = UUID()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("导入方式")
                } footer: {
                    Text("Gbox 等自签环境里系统文件选择器可能没反应。推荐把 .zip 谱面包放进下面这个文件夹，再回来点文件即可导入。")
                }

                Section {
                    if let dir = ImportHelper.documentsDirectory() {
                        HStack {
                            Text(dir.path).font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = dir.path
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
                    Text("在「文件」App → 我的 iPhone → Phira 谱面工坊 里放文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("文件共享目录")
                }

                let docs = ImportHelper.importableFilesInDocuments()
                let inbox = ImportHelper.inboxFiles(refresh: refreshInbox)

                if !inbox.isEmpty {
                    Section("从「文件」App 分享进来的") {
                        ForEach(inbox, id: \.url) { item in
                            Button { importFromInbox(item.url) } label: {
                                Label(item.name, systemImage: "doc.zipper")
                            }
                        }
                    }
                }

                if !docs.isEmpty {
                    Section("文件共享目录里的文件（点一下导入）") {
                        ForEach(docs, id: \.url) { item in
                            Button { importFromInbox(item.url) } label: {
                                HStack {
                                    Label(item.name, systemImage: "doc")
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if inbox.isEmpty {
                    Section {
                        Text("还没找到 .zip / .json 文件。放进去后点上面的「重新扫描」。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("导入文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showInboxList = false }
                }
            }
        }
    }
}
