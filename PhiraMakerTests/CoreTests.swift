import XCTest
@testable import PhiraMaker

final class ZipTests: XCTestCase {

    func testRoundTripSmallFile() throws {
        let entries = [
            ZipEntry(name: "info.yml", data: Data("name: test\n".utf8)),
            ZipEntry(name: "chart.json", data: Data(#"{"a":1}"#.utf8))
        ]
        let archive = try ZipArchive.create(entries: entries)
        let items = try ZipArchive.read(archive)
        XCTAssertEqual(items.count, 2)
        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.data) })
        XCTAssertEqual(map["info.yml"], Data("name: test\n".utf8))
        XCTAssertEqual(map["chart.json"], Data(#"{"a":1}"#.utf8))
    }

    func testRoundTripLargeCompressibleData() throws {
        // 100KB 高度可压缩数据
        let text = String(repeating: "phira chart maker ", count: 6000)
        let data = Data(text.utf8)
        let archive = try ZipArchive.create(entries: [ZipEntry(name: "big.txt", data: data)])
        let items = try ZipArchive.read(archive)
        XCTAssertEqual(items.first?.data, data, "大文件必须能完整往返")
    }

    func testRoundTripRandomData() throws {
        // 随机数据（不可压缩）走 store 分支
        var bytes = [UInt8]()
        var seed: UInt64 = 0x12345
        for _ in 0..<50000 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bytes.append(UInt8((seed >> 33) & 0xFF))
        }
        let data = Data(bytes)
        let archive = try ZipArchive.create(entries: [ZipEntry(name: "rand.bin", data: data)])
        let items = try ZipArchive.read(archive)
        XCTAssertEqual(items.first?.data, data)
    }

    func testUnicodeFileName() throws {
        let entries = [ZipEntry(name: "谱面信息.json", data: Data("{}".utf8))]
        let archive = try ZipArchive.create(entries: entries)
        let items = try ZipArchive.read(archive)
        XCTAssertEqual(items.first?.name, "谱面信息.json")
    }

    func testEmptyFile() throws {
        let entries = [ZipEntry(name: "empty.txt", data: Data())]
        let archive = try ZipArchive.create(entries: entries)
        let items = try ZipArchive.read(archive)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.data.count, 0)
    }

    func testZipSignature() throws {
        let archive = try ZipArchive.create(entries: [ZipEntry(name: "a.txt", data: Data("x".utf8))])
        let header = [UInt8](archive.prefix(4))
        XCTAssertEqual(header, [0x50, 0x4B, 0x03, 0x04], "必须是标准 ZIP local header")
        let footer = [UInt8](archive.suffix(22).prefix(4))
        XCTAssertEqual(footer, [0x50, 0x4B, 0x05, 0x06], "必须有 EOCD")
    }

    /// 解压真实 deflate 数据（由 zlib 生成，wbits=-15）
    func testInflateDeflateStream() {
        // 见 Fixtures.swift 中的 base64
        for (compressedB64, expected) in Fixtures.deflateCases {
            guard let compressed = Data(base64Encoded: compressedB64) else {
                XCTFail("fixture base64 无效"); continue
            }
            let result = Inflate.decompress([UInt8](compressed), expectedSize: expected.count)
            XCTAssertEqual(String(decoding: result, as: UTF8.self), expected,
                           "deflate 解压结果不对")
        }
    }

    /// 解压 stored 块
    func testInflateStoredBlock() {
        // 手工构造：BFINAL=1, BTYPE=00，对齐后 LEN=5, NLEN=~5, 数据 "hello"
        var bytes: [UInt8] = [0x01]
        bytes.append(contentsOf: [0x05, 0x00])           // LEN
        bytes.append(contentsOf: [0xFA, 0xFF])           // NLEN
        bytes.append(contentsOf: Array("hello".utf8))
        let result = Inflate.decompress(bytes, expectedSize: 5)
        XCTAssertEqual(String(decoding: result, as: UTF8.self), "hello")
    }
}

final class YamlTests: XCTestCase {

    func testDumpAndParseRoundTrip() {
        var info = ChartInfo()
        info.name = "Test Song"
        info.difficulty = 15
        info.level = "IN Lv.15"
        info.charter = "谱师"
        info.composer = "曲师"
        info.illustrator = "画师"
        info.chart = "chart.json"
        info.format = "rpe"
        info.music = "song.ogg"
        info.illustration = "background.png"
        info.previewStart = 30
        info.tags = ["tag1", "标签2"]
        info.intro = "简介"

        let text = InfoYAML.dump(info)
        let parsed = InfoYAML.parse(text)

        XCTAssertEqual(parsed.name, "Test Song")
        XCTAssertEqual(parsed.difficulty, 15)
        XCTAssertEqual(parsed.level, "IN Lv.15")
        XCTAssertEqual(parsed.charter, "谱师")
        XCTAssertEqual(parsed.composer, "曲师")
        XCTAssertEqual(parsed.illustrator, "画师")
        XCTAssertEqual(parsed.chart, "chart.json")
        XCTAssertEqual(parsed.format, "rpe")
        XCTAssertEqual(parsed.music, "song.ogg")
        XCTAssertEqual(parsed.illustration, "background.png")
        XCTAssertEqual(parsed.previewStart, 30)
        XCTAssertEqual(parsed.tags, ["tag1", "标签2"])
        XCTAssertEqual(parsed.intro, "简介")
    }

    /// 纯数字名称必须仍是字符串 —— serde_yaml 会把它解析成整数导致类型不匹配
    func testNumericStringStaysQuoted() {
        var info = ChartInfo()
        info.name = "12345"
        info.charter = "0"
        let text = InfoYAML.dump(info)
        XCTAssertTrue(text.contains("name: \"12345\""), "数字字符串必须加引号，实际: \(text)")
        XCTAssertTrue(text.contains("charter: \"0\""))

        let parsed = InfoYAML.parse(text)
        XCTAssertEqual(parsed.name, "12345")
        XCTAssertEqual(parsed.charter, "0")
    }

    func testBoolNotQuoted() {
        var info = ChartInfo()
        info.holdPartialCover = true
        let text = InfoYAML.dump(info)
        XCTAssertTrue(text.contains("holdPartialCover: true"), "布尔值不能加引号，实际: \(text)")
    }

    func testFloatNotQuoted() {
        var info = ChartInfo()
        info.difficulty = 12.5
        let text = InfoYAML.dump(info)
        XCTAssertTrue(text.contains("difficulty: 12.5"))
    }

    func testSpecialCharsInString() {
        var info = ChartInfo()
        info.name = "Song: with \"quotes\" and\nnewline"
        let text = InfoYAML.dump(info)
        let parsed = InfoYAML.parse(text)
        XCTAssertEqual(parsed.name, "Song: with \"quotes\" and\nnewline")
    }

    func testEmptyTags() {
        var info = ChartInfo()
        info.tags = []
        let text = InfoYAML.dump(info)
        XCTAssertTrue(text.contains("tags: []"))
        let parsed = InfoYAML.parse(text)
        XCTAssertEqual(parsed.tags, [])
    }
}

final class BeatTests: XCTestCase {

    func testIntegerBeat() {
        let b = Beat(i: 4)
        XCTAssertEqual(b.value, 4.0)
        XCTAssertEqual(b.toJSONArray(), [4, 0, 1])
    }

    func testFractionBeat() {
        let b = Beat(i: 1, n: 1, d: 2)
        XCTAssertEqual(b.value, 1.5)
    }

    func testFromDouble() {
        let b = Beat(value: 2.5)
        XCTAssertEqual(b.value, 2.5, accuracy: 0.001)
    }

    func testFromDoubleRepeating() {
        let b = Beat(value: 1.0 / 3.0)
        XCTAssertEqual(b.value, 1.0 / 3.0, accuracy: 0.001)
    }

    func testJSONArrayRoundTrip() {
        let arr = [5, 3, 8]
        let b = Beat(jsonArray: arr)
        XCTAssertEqual(b.i, 5)
        XCTAssertEqual(b.n, 3)
        XCTAssertEqual(b.d, 8)
        XCTAssertEqual(b.value, 5.375)
    }

    func testZeroDenominatorGuard() {
        let b = Beat(i: 1, n: 1, d: 0)
        XCTAssertEqual(b.d, 1, "分母为 0 要兜底成 1")
    }
}

final class BpmTimelineTests: XCTestCase {

    func testConstantBpm() {
        let timeline = BpmTimeline(bpmList: [BPMEvent(startTime: Beat(i: 0), bpm: 120)])
        // 120 BPM: 1 拍 = 0.5 秒
        XCTAssertEqual(timeline.time(atBeat: 4), 2.0, accuracy: 0.001)
        XCTAssertEqual(timeline.beat(atTime: 2.0), 4.0, accuracy: 0.001)
    }

    func testBpmChange() {
        // 0 拍起 120 BPM，第 4 拍起 240 BPM
        let timeline = BpmTimeline(bpmList: [
            BPMEvent(startTime: Beat(i: 0), bpm: 120),
            BPMEvent(startTime: Beat(i: 4), bpm: 240)
        ])
        // 4 拍 @120 = 2 秒
        XCTAssertEqual(timeline.time(atBeat: 4), 2.0, accuracy: 0.001)
        // 之后 240 BPM: 1 拍 = 0.25 秒，4 拍 = 1 秒
        XCTAssertEqual(timeline.time(atBeat: 8), 3.0, accuracy: 0.001)
        XCTAssertEqual(timeline.beat(atTime: 3.0), 8.0, accuracy: 0.001)
    }

    func testEmptyListFallback() {
        let timeline = BpmTimeline(bpmList: [])
        XCTAssertEqual(timeline.time(atBeat: 4), 2.0, accuracy: 0.001, "空 BPM 列表应默认 120")
    }
}

final class RPEFormatTests: XCTestCase {

    func makeChart() -> RPEChart {
        var meta = ChartMeta()
        meta.name = "测试谱面"
        meta.level = "IN Lv.15"
        meta.charter = "谱师"
        meta.offset = 120

        var line = JudgeLine(name: "Line 0")
        var layer = EventLayer()
        layer.moveXEvents = [LineEvent(startTime: Beat(i: 0), endTime: Beat(i: 4), start: -100, end: 100, easingType: 4)]
        layer.rotateEvents = [LineEvent(startTime: Beat(i: 0), endTime: Beat(i: 8), start: 0, end: 90)]
        line.eventLayers = [layer]
        line.notes = [
            Note(type: .tap, startTime: Beat(i: 1), positionX: -200),
            Note(type: .hold, startTime: Beat(i: 2), endTime: Beat(i: 4), positionX: 0),
            Note(type: .flick, startTime: Beat(i: 5), positionX: 300)
        ]

        return RPEChart(meta: meta,
                        bpmList: [BPMEvent(startTime: Beat(i: 0), bpm: 180)],
                        judgeLineList: [line])
    }

    func testEncodeDecodeRoundTrip() throws {
        let chart = makeChart()
        let data = try RPEFormat.encode(chart)
        let decoded = try RPEFormat.decode(data)

        XCTAssertEqual(decoded.META.name, "测试谱面")
        XCTAssertEqual(decoded.META.level, "IN Lv.15")
        XCTAssertEqual(decoded.META.offset, 120)
        XCTAssertEqual(decoded.BPMList.count, 1)
        XCTAssertEqual(decoded.BPMList[0].bpm, 180)
        XCTAssertEqual(decoded.judgeLineList.count, 1)
        XCTAssertEqual(decoded.judgeLineList[0].notes.count, 3)
        XCTAssertEqual(decoded.judgeLineList[0].notes[0].type, .tap)
        XCTAssertEqual(decoded.judgeLineList[0].notes[1].type, .hold)
        XCTAssertEqual(decoded.judgeLineList[0].notes[1].endTime.value, 4)
        XCTAssertEqual(decoded.judgeLineList[0].notes[2].type, .flick)
    }

    func testEncodedJSONHasRequiredFields() throws {
        let data = try RPEFormat.encode(makeChart())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["META"])
        XCTAssertNotNil(json?["BPMList"])
        XCTAssertNotNil(json?["judgeLineList"])

        let meta = json?["META"] as? [String: Any]
        XCTAssertNotNil(meta?["offset"], "offset 是 RPE 必需字段")
        XCTAssertNotNil(meta?["RPEVersion"])

        let lines = json?["judgeLineList"] as? [[String: Any]]
        let line = lines?.first
        XCTAssertNotNil(line?["Name"])
        XCTAssertNotNil(line?["Texture"])
        XCTAssertNotNil(line?["isCover"])
        XCTAssertNotNil(line?["eventLayers"], "eventLayers 是必需字段")

        let notes = line?["notes"] as? [[String: Any]]
        let note = notes?.first
        XCTAssertNotNil(note?["type"])
        XCTAssertNotNil(note?["above"])
        XCTAssertNotNil(note?["startTime"])
        XCTAssertNotNil(note?["endTime"])
        XCTAssertNotNil(note?["positionX"])
        XCTAssertNotNil(note?["yOffset"])
        XCTAssertNotNil(note?["alpha"])
        XCTAssertNotNil(note?["size"])
        XCTAssertNotNil(note?["speed"])
        XCTAssertNotNil(note?["isFake"])
        XCTAssertNotNil(note?["visibleTime"])
    }

    func testNoteDefaultsMatchPhira() throws {
        // Phira 的 RPENote 所有字段都是必需（无 serde default）
        let chart = makeChart()
        let data = try RPEFormat.encode(chart)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let notes = (json?["judgeLineList"] as? [[String: Any]])?.first?["notes"] as? [[String: Any]]
        guard let note = notes?.first else { return XCTFail("没有音符") }

        XCTAssertEqual(note["above"] as? Int, 1)
        XCTAssertEqual(note["alpha"] as? Int, 255)
        XCTAssertEqual(note["isFake"] as? Int, 0)
        XCTAssertEqual(note["size"] as? Double, 1.0)
        XCTAssertEqual(note["speed"] as? Double, 1.0)
        XCTAssertEqual(note["yOffset"] as? Double, 0.0)
        XCTAssertEqual(note["visibleTime"] as? Double, 999999)
    }

    func testDecodeRPEWithMissingOptionalFields() throws {
        // 真实 RPE 文件里 eventLayers 可能是 null、notes 可能没有
        let json = """
        {
          "META": {"offset": 0, "RPEVersion": 160, "name": "Min", "level": "0", "charter": "x"},
          "BPMList": [{"startTime": [0, 0, 1], "bpm": 120}],
          "judgeLineList": [{
            "Name": "l", "Texture": "line.png", "isCover": 1,
            "eventLayers": [null],
            "notes": []
          }]
        }
        """
        let chart = try RPEFormat.decode(Data(json.utf8))
        XCTAssertEqual(chart.judgeLineList.count, 1)
        XCTAssertEqual(chart.judgeLineList[0].notes.count, 0)
    }

    func testDecodeNullEventLayers() throws {
        let json = """
        {
          "META": {"offset": 0},
          "BPMList": [{"startTime": [0,0,1], "bpm": 150}],
          "judgeLineList": [{"Name": "a", "Texture": "line.png", "isCover": 1, "eventLayers": null}]
        }
        """
        let chart = try RPEFormat.decode(Data(json.utf8))
        XCTAssertEqual(chart.judgeLineList.count, 1)
        XCTAssertEqual(chart.BPMList.first?.bpm, 150)
    }
}

final class PECFormatTests: XCTestCase {

    func testDecodePEC() throws {
        let pec = """
        0
        bp 0.000 180.000
        cp 0 0.000 1024.000 700.000
        n1 0 1.000 1124.000 1 0
        # 1.00
        & 1.00
        n2 0 2.000 4.000 1024.000 1 0
        """
        let chart = try PECFormat.decode(Data(pec.utf8))
        XCTAssertEqual(chart.BPMList.first?.bpm, 180)
        let notes = chart.judgeLineList.flatMap { $0.notes }
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].type, .tap)
        XCTAssertEqual(notes[0].positionX, 100, accuracy: 1)
        XCTAssertEqual(notes[1].type, .hold)
        XCTAssertEqual(notes[1].startTime.value, 2)
        XCTAssertEqual(notes[1].endTime.value, 4)
    }

    func testEncodePEC() throws {
        var meta = ChartMeta()
        meta.offset = 0
        var line = JudgeLine(name: "L0")
        line.notes = [Note(type: .tap, startTime: Beat(i: 1), positionX: 0)]
        let chart = RPEChart(meta: meta,
                             bpmList: [BPMEvent(startTime: Beat(i: 0), bpm: 150)],
                             judgeLineList: [line])
        let data = try PECFormat.encode(chart)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("bp 0 150"), "实际: \(text)")
        XCTAssertTrue(text.contains("n1 0 1 "), "实际: \(text)")
    }

    func testPECOffsetCompensation() throws {
        // PEC 第一行 offset 要减 175
        let pec = "500\nbp 0.000 120.000\n"
        let chart = try PECFormat.decode(Data(pec.utf8))
        XCTAssertEqual(chart.META.offset, 325)
    }
}

final class ChartPackageTests: XCTestCase {

    func testExportImportRoundTrip() throws {
        var project = ChartProject()
        project.info.name = "测试曲目"
        project.info.level = "IN Lv.15"
        project.info.charter = "测试谱师"
        project.info.composer = "测试曲师"
        project.info.music = "song.ogg"
        project.info.illustration = "background.png"
        project.format = .rpe

        var line = JudgeLine(name: "Line 0")
        line.notes = [
            Note(type: .tap, startTime: Beat(i: 1), positionX: -100),
            Note(type: .hold, startTime: Beat(i: 2), endTime: Beat(i: 4), positionX: 50),
            Note(type: .drag, startTime: Beat(i: 6), positionX: 200)
        ]
        project.chart.judgeLineList = [line]
        project.assets = [
            ChartAsset(kind: .music, fileName: "song.ogg", data: Data("fake ogg".utf8)),
            ChartAsset(kind: .illustration, fileName: "background.png", data: Data("fake png".utf8))
        ]

        let archive = try project.exportArchive()
        XCTAssertGreaterThan(archive.count, 0)

        let restored = try ChartProject.importArchive(archive)
        XCTAssertEqual(restored.info.name, "测试曲目")
        XCTAssertEqual(restored.info.level, "IN Lv.15")
        XCTAssertEqual(restored.info.charter, "测试谱师")
        XCTAssertEqual(restored.format, .rpe)
        XCTAssertEqual(restored.chart.judgeLineList.count, 1)
        XCTAssertEqual(restored.chart.judgeLineList[0].notes.count, 3)
        XCTAssertEqual(restored.chart.judgeLineList[0].notes[1].type, .hold)
        XCTAssertEqual(restored.assets.count, 2)
        XCTAssertNotNil(restored.music)
        XCTAssertNotNil(restored.illustration)
    }

    func testExportedArchiveContainsRequiredFiles() throws {
        var project = ChartProject()
        project.info.name = "Pkg"
        let archive = try project.exportArchive()
        let items = try ZipArchive.read(archive)
        let names = Set(items.map { $0.name })

        XCTAssertTrue(names.contains("info.yml"), "必须有 info.yml")
        XCTAssertTrue(names.contains("chart.json"), "必须有谱面文件")
    }

    func testInfoYmlContentIsParseable() throws {
        var project = ChartProject()
        project.info.name = "内容检查"
        project.info.charter = "abc"
        let archive = try project.exportArchive()
        let items = try ZipArchive.read(archive)
        guard let infoItem = items.first(where: { $0.name == "info.yml" }) else {
            return XCTFail("没有 info.yml")
        }
        let text = String(data: infoItem.data, encoding: .utf8) ?? ""
        let parsed = InfoYAML.parse(text)
        XCTAssertEqual(parsed.name, "内容检查")
        XCTAssertEqual(parsed.charter, "abc")
        XCTAssertEqual(parsed.chart, "chart.json")
        XCTAssertEqual(parsed.format, "rpe")
    }

    func testPECExport() throws {
        var project = ChartProject()
        project.format = .pec
        project.chart.judgeLineList[0].notes = [Note(type: .tap, startTime: Beat(i: 2))]
        let archive = try project.exportArchive()
        let items = try ZipArchive.read(archive)
        let names = Set(items.map { $0.name })
        XCTAssertTrue(names.contains("chart.pec"), "PEC 导出应生成 chart.pec，实际: \(names)")
        let infoText = String(data: items.first(where: { $0.name == "info.yml" })!.data, encoding: .utf8)!
        XCTAssertTrue(infoText.contains("chart: \"chart.pec\""))
    }
}

final class ValidatorTests: XCTestCase {

    func testValidPackagePassesValidation() throws {
        var project = ChartProject()
        project.info.name = "OK 谱面"
        let archive = try project.exportArchive()
        let report = Validator.validate(archive: archive)
        let joined = report.joined(separator: "\n")
        XCTAssertFalse(joined.contains("❌"), "自检不应有错误:\n\(joined)")
    }
}
