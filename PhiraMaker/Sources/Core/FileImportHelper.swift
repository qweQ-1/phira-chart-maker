// 文件导入工具：兼容自签名 App 的安全作用域限制。
//
// 自签名 App（AltStore / Sideloadly / 轻松签）常见坑：
// 1. security-scoped URL 直接 Data(contentsOf:) 有时读不到 → 先复制到临时目录再读
// 2. UTType 过滤太严会让系统文件选择器里的文件变灰 → 放行 .item
// 3. 从「文件」App 分享进来的文件落到 Inbox 目录 → 需要单独扫描
// 4. iTunes/Finder 文件共享目录（Documents）里的文件 → 需要单独扫描

import Foundation
import UIKit

enum ImportHelper {

    enum ImportFailure: LocalizedError {
        case emptySelection
        case securityScopeDenied
        case readFailed(String)
        case notChartPackage

        var errorDescription: String? {
            switch self {
            case .emptySelection: return "没有选中文件"
            case .securityScopeDenied: return "系统拒绝访问该文件，请重试或改用「文件共享」方式"
            case .readFailed(let detail): return "读取文件失败：\(detail)"
            case .notChartPackage: return "这个文件不是 Phira 谱面包（.zip）或 RPE 谱面（.json）"
            }
        }
    }

    /// 从 URL 安全读取：先取 security scope，再复制到临时目录，最后读。
    /// 自签名 App 直接读原始 URL 经常失败，这一步复制是关键。
    static func readSecurely(from url: URL) throws -> (data: Data, name: String) {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportFailure.securityScopeDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)-\(url.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: temp) }

        do {
            try FileManager.default.copyItem(at: url, to: temp)
        } catch {
            // 复制失败就试着直接读（有些位置不需要复制）
            do {
                let data = try Data(contentsOf: url)
                return (data, url.lastPathComponent)
            } catch {
                throw ImportFailure.readFailed(error.localizedDescription)
            }
        }

        do {
            let data = try Data(contentsOf: temp)
            return (data, url.lastPathComponent)
        } catch {
            throw ImportFailure.readFailed(error.localizedDescription)
        }
    }

    /// 扫描 App 的 Documents 目录（iTunes/Finder 文件共享）
    /// 用户可以在「文件」App → 我的 iPhone → Phira 谱面工坊 里放 zip 进来
    static func documentsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// 列出 Documents 里可导入的文件
    static func importableFilesInDocuments() -> [(url: URL, name: String, size: Int64)] {
        guard let dir = documentsDirectory() else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "zip" || ext == "json" else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
            return (url, url.lastPathComponent, size)
        }
        .sorted { $0.name < $1.name }
    }

    /// 扫描 Inbox 目录（从「文件」App 分享进来的文件会落在这里）
    /// refresh 参数用于强制 SwiftUI 重算（目录内容变化不会被自动观测）
    static func inboxFiles(refresh: UUID = UUID()) -> [(url: URL, name: String)] {
        _ = refresh
        guard let dir = documentsDirectory() else { return [] }
        let inbox = dir.appendingPathComponent("Inbox", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.map { ($0, $0.lastPathComponent) }
    }

    /// 判断文件是否我们支持的谱面格式
    static func isSupported(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "zip" || ext == "json" || ext == "pec"
    }
}
