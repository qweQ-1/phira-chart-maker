// ZIP 打包 / 解包（零依赖：纯 Swift 实现，不依赖 zlib 或第三方库）
//
// 兼容性依据：
// - Phira 用 Rust 的 `zip 8.3.0` crate 读取，支持 store(0) 和 deflate(8)
// - 写：只用 store(0)。音乐/图片本身就是压缩格式，谱面 JSON 也小，
//   换来的是零依赖、零链接风险。（Phira 自己导出用 deflate，但读取两种都支持）
// - 读：支持 store(0) + deflate(8)，deflate 用本文件内的 inflate（RFC 1951）

import Foundation

enum ZipError: Error, LocalizedError {
    case entryTooLarge
    case invalidArchive
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .entryTooLarge: return "文件过大，无法打包"
        case .invalidArchive: return "压缩包格式无效"
        case .decompressionFailed: return "解压失败"
        }
    }
}

/// ZIP 归档条目
struct ZipEntry {
    var name: String
    var data: Data

    init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

enum ZipArchive {

    // MARK: - 写（全部 store）

    static func create(entries: [ZipEntry]) throws -> Data {
        var output = Data()
        var central = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            guard nameBytes.count <= 0xFFFF else { throw ZipError.invalidArchive }
            guard entry.data.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
                throw ZipError.entryTooLarge
            }

            let method: UInt16 = 0
            let payload = entry.data
            let crc = CRC32.checksum(entry.data)

            // local file header
            var local = Data()
            local.appendLE(UInt32(0x04034B50))
            local.appendLE(UInt16(20))            // version needed
            local.appendLE(UInt16(0x0800))        // flags: UTF-8 文件名
            local.appendLE(method)
            local.appendLE(UInt16(0))             // mod time
            local.appendLE(UInt16(0x21))          // mod date (1996-01-01)
            local.appendLE(crc)
            local.appendLE(UInt32(payload.count))
            local.appendLE(UInt32(entry.data.count))
            local.appendLE(UInt16(nameBytes.count))
            local.appendLE(UInt16(0))             // extra len
            local.append(contentsOf: nameBytes)
            local.append(payload)

            output.append(local)

            // central directory entry
            var cd = Data()
            cd.appendLE(UInt32(0x02014B50))
            cd.appendLE(UInt16(0x031E))            // version made by (unix)
            cd.appendLE(UInt16(20))
            cd.appendLE(UInt16(0x0800))
            cd.appendLE(method)
            cd.appendLE(UInt16(0))
            cd.appendLE(UInt16(0x21))
            cd.appendLE(crc)
            cd.appendLE(UInt32(payload.count))
            cd.appendLE(UInt32(entry.data.count))
            cd.appendLE(UInt16(nameBytes.count))
            cd.appendLE(UInt16(0))                 // extra
            cd.appendLE(UInt16(0))                 // comment
            cd.appendLE(UInt16(0))                 // disk number
            cd.appendLE(UInt16(0))                 // internal attrs
            cd.appendLE(UInt32(0x81A40000))        // external attrs: 0644
            cd.appendLE(offset)
            cd.append(contentsOf: nameBytes)
            central.append(cd)

            offset += UInt32(local.count)
        }

        // end of central directory
        var eocd = Data()
        eocd.appendLE(UInt32(0x06054B50))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt32(central.count))
        eocd.appendLE(offset)
        eocd.appendLE(UInt16(0))

        output.append(central)
        output.append(eocd)
        return output
    }

    // MARK: - 读

    struct Item {
        var name: String
        var data: Data
    }

    static func read(_ data: Data) throws -> [Item] {
        let bytes = [UInt8](data)
        guard let eocdOffset = findEOCD(bytes) else { throw ZipError.invalidArchive }

        func u16(_ off: Int) -> UInt16 {
            guard off + 1 < bytes.count else { return 0 }
            return UInt16(bytes[off]) | (UInt16(bytes[off + 1]) << 8)
        }
        func u32(_ off: Int) -> UInt32 {
            guard off + 3 < bytes.count else { return 0 }
            return UInt32(bytes[off]) | (UInt32(bytes[off + 1]) << 8)
                | (UInt32(bytes[off + 2]) << 16) | (UInt32(bytes[off + 3]) << 24)
        }

        let entryCount = Int(u16(eocdOffset + 10))
        var cdOffset = Int(u32(eocdOffset + 16))
        var items: [Item] = []

        for _ in 0..<entryCount {
            guard cdOffset + 46 <= bytes.count, u32(cdOffset) == 0x02014B50 else { break }
            let method = u16(cdOffset + 10)
            let compressedSize = Int(u32(cdOffset + 20))
            let uncompressedSize = Int(u32(cdOffset + 24))
            let nameLen = Int(u16(cdOffset + 28))
            let extraLen = Int(u16(cdOffset + 30))
            let commentLen = Int(u16(cdOffset + 32))
            let localOffset = Int(u32(cdOffset + 42))

            guard cdOffset + 46 + nameLen <= bytes.count else { break }
            let nameBytes = Array(bytes[(cdOffset + 46)..<(cdOffset + 46 + nameLen)])
            let name = String(decoding: nameBytes, as: UTF8.self)

            var payload = Data()
            if localOffset + 30 <= bytes.count, u32(localOffset) == 0x04034B50 {
                let lNameLen = Int(u16(localOffset + 26))
                let lExtraLen = Int(u16(localOffset + 28))
                let dataStart = localOffset + 30 + lNameLen + lExtraLen
                if compressedSize >= 0, dataStart + compressedSize <= bytes.count {
                    let raw = Array(bytes[dataStart..<(dataStart + compressedSize)])
                    if method == 0 {
                        payload = Data(raw)
                    } else if method == 8 {
                        payload = Inflate.decompress(raw, expectedSize: uncompressedSize)
                    } else {
                        cdOffset += 46 + nameLen + extraLen + commentLen
                        continue
                    }
                }
            }

            if !name.hasSuffix("/") {
                items.append(Item(name: name, data: payload))
            }
            cdOffset += 46 + nameLen + extraLen + commentLen
        }
        return items
    }

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        var i = bytes.count - 22
        let lowerBound = max(0, bytes.count - 22 - 65535)
        while i >= lowerBound {
            if bytes[i] == 0x50 && bytes[i+1] == 0x4B && bytes[i+2] == 0x05 && bytes[i+3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }
}

// MARK: - CRC32

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Data 小工具

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}

// MARK: - 裸 DEFLATE 解压（RFC 1951 子集，支持 stored/fixed/dynamic Huffman）

enum Inflate {
    private struct BitReader {
        let bytes: [UInt8]
        var pos: Int = 0
        var bitBuf: UInt32 = 0
        var bitCount: Int = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func bits(_ n: Int) -> Int? {
            while bitCount < n {
                guard pos < bytes.count else { return nil }
                bitBuf |= UInt32(bytes[pos]) << UInt32(bitCount)
                pos += 1
                bitCount += 8
            }
            let value = Int(bitBuf & ((1 << UInt32(n)) - 1))
            bitBuf >>= UInt32(n)
            bitCount -= n
            return value
        }

        mutating func alignToByte() {
            let drop = bitCount % 8
            bitBuf >>= UInt32(drop)
            bitCount -= drop
        }
    }

    private struct Huffman {
        // 每条码的 (符号, 长度)，按码长分组查找
        var counts: [Int] = Array(repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) {
            for l in lengths where l > 0 && l < 16 {
                counts[l] += 1
            }
            counts[0] = 0
            var offsets = Array(repeating: 0, count: 16)
            for i in 1..<16 {
                offsets[i] = offsets[i - 1] + counts[i - 1]
            }
            symbols = Array(repeating: 0, count: offsets[15] + counts[15])
            for (symbol, l) in lengths.enumerated() where l > 0 {
                symbols[offsets[l]] = symbol
                offsets[l] += 1
            }
        }

        func decode(_ reader: inout BitReader) -> Int? {
            var code = 0
            var first = 0
            var index = 0
            for len in 1..<16 {
                guard let bit = reader.bits(1) else { return nil }
                code |= bit
                let count = counts[len]
                if code - first < count {
                    let i = index + (code - first)
                    guard i >= 0 && i < symbols.count else { return nil }
                    return symbols[i]
                }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            return nil
        }
    }

    private static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ]
    private static let lengthExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ]
    private static let distBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
        8193, 12289, 16385, 24577
    ]
    private static let distExtra: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ]

    static func decompress(_ input: [UInt8], expectedSize: Int) -> Data {
        var reader = BitReader(input)
        var out: [UInt8] = []
        if expectedSize > 0 { out.reserveCapacity(min(expectedSize, 64 * 1024 * 1024)) }

        while true {
            guard let isFinal = reader.bits(1) else { break }
            guard let blockType = reader.bits(2) else { break }

            if blockType == 0 {
                // stored
                reader.alignToByte()
                guard let lenLow = reader.bits(8), let lenHigh = reader.bits(8) else { break }
                let len = lenLow | (lenHigh << 8)
                let _ = reader.bits(8)
                let _ = reader.bits(8)
                for _ in 0..<len {
                    guard let b = reader.bits(8) else { return Data(out) }
                    out.append(UInt8(b))
                }
            } else if blockType == 1 || blockType == 2 {
                let litTree: Huffman
                let distTree: Huffman

                if blockType == 1 {
                    var litLengths = [Int](repeating: 0, count: 288)
                    for i in 0..<144 { litLengths[i] = 8 }
                    for i in 144..<256 { litLengths[i] = 9 }
                    for i in 256..<280 { litLengths[i] = 7 }
                    for i in 280..<288 { litLengths[i] = 8 }
                    litTree = Huffman(lengths: litLengths)
                    distTree = Huffman(lengths: [Int](repeating: 5, count: 32))
                } else {
                    guard let hlit = reader.bits(5),
                          let hdist = reader.bits(5),
                          let hclen = reader.bits(4) else { break }

                    let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                    var clLengths = [Int](repeating: 0, count: 19)
                    for i in 0..<(hclen + 4) {
                        guard let v = reader.bits(3) else { return Data(out) }
                        clLengths[order[i]] = v
                    }
                    let clTree = Huffman(lengths: clLengths)

                    var lengths: [Int] = []
                    let total = hlit + 257 + hdist + 1
                    while lengths.count < total {
                        guard let sym = clTree.decode(&reader) else { return Data(out) }
                        if sym < 16 {
                            lengths.append(sym)
                        } else if sym == 16 {
                            guard let extra = reader.bits(2) else { return Data(out) }
                            let prev = lengths.last ?? 0
                            for _ in 0..<(3 + extra) { lengths.append(prev) }
                        } else if sym == 17 {
                            guard let extra = reader.bits(3) else { return Data(out) }
                            for _ in 0..<(3 + extra) { lengths.append(0) }
                        } else {
                            guard let extra = reader.bits(7) else { return Data(out) }
                            for _ in 0..<(11 + extra) { lengths.append(0) }
                        }
                    }

                    let litCount = hlit + 257
                    let litLengths = Array(lengths[0..<min(litCount, lengths.count)])
                    let distLengths = lengths.count > litCount
                        ? Array(lengths[litCount..<min(litCount + hdist + 1, lengths.count)])
                        : []
                    litTree = Huffman(lengths: litLengths)
                    distTree = Huffman(lengths: distLengths.isEmpty ? [Int](repeating: 5, count: 32) : distLengths)
                }

                // 解符号
                while true {
                    guard let sym = litTree.decode(&reader) else { return Data(out) }
                    if sym < 256 {
                        out.append(UInt8(sym))
                    } else if sym == 256 {
                        break
                    } else {
                        let li = sym - 257
                        guard li >= 0 && li < lengthBase.count else { return Data(out) }
                        guard let extra = reader.bits(lengthExtra[li]) else { return Data(out) }
                        let length = lengthBase[li] + extra

                        guard let dsym = distTree.decode(&reader) else { return Data(out) }
                        guard dsym >= 0 && dsym < distBase.count else { return Data(out) }
                        guard let dextra = reader.bits(distExtra[dsym]) else { return Data(out) }
                        let dist = distBase[dsym] + dextra
                        guard dist > 0, dist <= out.count else { return Data(out) }

                        let start = out.count - dist
                        for i in 0..<length {
                            out.append(out[start + i])
                        }
                    }
                }
            } else {
                return Data(out)
            }

            if isFinal == 1 { break }
        }
        return Data(out)
    }
}
