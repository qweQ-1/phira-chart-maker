// 极简 YAML 支持：只需要读写 Phira `info.yml` 这种扁平结构。
// 写出遵循 serde_yaml 的风格；读回能解析 Phira 导出的 info.yml。

import Foundation

enum YamlValue: Equatable {
    /// 字符串标量：输出时始终加引号
    case scalar(String)
    /// 裸标量：数字/布尔等，输出时不加引号
    case raw(String)
    case list([String])
    case null

    var stringValue: String? {
        if case .scalar(let s) = self { return s }
        return nil
    }

    var listValue: [String]? {
        if case .list(let l) = self { return l }
        return nil
    }

    var floatValue: Float? {
        if case .scalar(let s) = self { return Float(s) }
        if case .raw(let s) = self { return Float(s) }
        return nil
    }

    var boolValue: Bool? {
        var s: String? = nil
        if case .scalar(let v) = self { s = v }
        if case .raw(let v) = self { s = v }
        guard let s = s else { return nil }
        switch s.lowercased() {
        case "true", "yes": return true
        case "false", "no": return false
        default: return nil
        }
    }
}

enum Yaml {
    // MARK: - 写

    /// 生成 YAML 文本。键按给定顺序输出。
    /// `.scalar` 总是加双引号（serde_yaml 0.9 对未加引号的数字字符串会解析成数字，
    /// 导致 `name: 123` 被读成整数而类型不匹配），`.raw` 原样输出。
    static func dump(_ entries: [(String, YamlValue)]) -> String {
        var out = ""
        for (key, value) in entries {
            switch value {
            case .scalar(let s):
                out += "\(key): \(quote(s))\n"
            case .raw(let s):
                out += "\(key): \(s)\n"
            case .list(let items):
                if items.isEmpty {
                    out += "\(key): []\n"
                } else {
                    out += "\(key):\n"
                    for item in items {
                        out += "- \(quote(item))\n"
                    }
                }
            case .null:
                out += "\(key):\n"
            }
        }
        return out
    }

    /// 双引号转义
    static func quote(_ s: String) -> String {
        var escaped = ""
        for ch in s {
            switch ch {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default: escaped.append(ch)
            }
        }
        return "\"\(escaped)\""
    }

    // MARK: - 读

    /// 解析扁平的 YAML 文档。返回 key -> YamlValue。
    /// 支持 `key: value`、`key:` 后跟 `- item` 列表、注释、`#` 引号剥离。
    static func parse(_ text: String) -> [String: YamlValue] {
        var result: [String: YamlValue] = [:]
        let lines = text.components(separatedBy: .newlines)
        var idx = 0
        while idx < lines.count {
            let raw = lines[idx]
            let line = stripComment(raw)
            idx += 1
            if line.trimmed.isEmpty { continue }
            if line.trimmed.hasPrefix("-") { continue } // 孤立列表项，由上面的 key 消费
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIdx]).trimmed
            var rest = String(line[line.index(after: colonIdx)...]).trimmed
            if key.isEmpty { continue }

            if rest.isEmpty {
                // 可能是列表，或空值
                var items: [String] = []
                var foundList = false
                while idx < lines.count {
                    let next = stripComment(lines[idx])
                    if next.trimmed.isEmpty { idx += 1; continue }
                    if next.trimmed.hasPrefix("- ") || next.trimmed == "-" {
                        foundList = true
                        var item = next.trimmed
                        if item == "-" { item = "" } else if item.hasPrefix("- ") { item = String(item.dropFirst(2)).trimmed }
                        items.append(unquote(item))
                        idx += 1
                        continue
                    }
                    break
                }
                result[key] = foundList ? .list(items) : .null
            } else {
                result[key] = .scalar(unquote(rest))
            }
        }
        return result
    }

    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var out = ""
        var prev: Character?
        for ch in line {
            if ch == "'" && !inDouble { inSingle.toggle() }
            if ch == "\"" && !inSingle && prev != "\\" { inDouble.toggle() }
            if ch == "#" && !inSingle && !inDouble {
                // 行首或前面是空白的 # 才是注释
                if prev == nil || prev == " " { break }
            }
            out.append(ch)
            prev = ch
        }
        return out
    }

    private static func unquote(_ s: String) -> String {
        var t = s.trimmed
        if t.count >= 2 {
            if t.hasPrefix("\"") && t.hasSuffix("\"") {
                var inner = String(t.dropFirst().dropLast())
                inner = inner.replacingOccurrences(of: "\\n", with: "\n")
                inner = inner.replacingOccurrences(of: "\\\"", with: "\"")
                inner = inner.replacingOccurrences(of: "\\\\", with: "\\")
                return inner
            }
            if t.hasPrefix("'") && t.hasSuffix("'") {
                return String(t.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
        }
        return t
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }
}
