// 工程仓库：管理本地谱面工程，持久化到 Application Support
import Foundation
import SwiftUI

final class ProjectStore: ObservableObject {
    @Published var projects: [ChartProject] = []
    @Published var currentIndex: Int?

    private let storageURL: URL
    private let fileManager = FileManager.default

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("PhiraMaker", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("projects.json")
        load()
    }

    var current: ChartProject? {
        guard let i = currentIndex, projects.indices.contains(i) else { return nil }
        return projects[i]
    }

    // MARK: - 增删

    func addNew() {
        var project = ChartProject()
        project.info.name = "新谱面 \(projects.count + 1)"
        projects.append(project)
        currentIndex = projects.count - 1
        save()
    }

    func importProject(_ project: ChartProject) {
        projects.append(project)
        currentIndex = projects.count - 1
        save()
    }

    func delete(at offsets: IndexSet) {
        projects.remove(atOffsets: offsets)
        if let i = currentIndex, i >= projects.count { currentIndex = projects.count - 1 }
        save()
    }

    func update(_ project: ChartProject) {
        guard let i = currentIndex, projects.indices.contains(i) else { return }
        projects[i] = project
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([StoredProject].self, from: data)
            projects = decoded.map { $0.toProject() }
        } catch {
            projects = []
        }
    }

    func save() {
        let stored = projects.map { StoredProject($0) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

/// 持久化用的包装（附件转 base64）
struct StoredProject: Codable {
    var info: ChartInfo
    var chart: RPEChart
    var format: String
    var assets: [StoredAsset]

    init(_ p: ChartProject) {
        info = p.info
        chart = p.chart
        format = p.format.rawValue
        assets = p.assets.map { StoredAsset($0) }
    }

    func toProject() -> ChartProject {
        var p = ChartProject()
        p.info = info
        p.chart = chart
        p.format = ChartFormat(rawValue: format) ?? .rpe
        p.assets = assets.map { $0.toAsset() }
        return p
    }
}

struct StoredAsset: Codable {
    var kind: String
    var fileName: String
    var originalName: String
    var base64: String

    init(_ a: ChartAsset) {
        kind = a.kind.rawValue
        fileName = a.fileName
        originalName = a.originalName
        base64 = a.data.base64EncodedString()
    }

    func toAsset() -> ChartAsset {
        ChartAsset(kind: ChartAsset.Kind(rawValue: kind) ?? .music,
                   fileName: fileName,
                   data: Data(base64Encoded: base64) ?? Data(),
                   originalName: originalName)
    }
}
