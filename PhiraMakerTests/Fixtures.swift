// 测试基准数据（由 Python zlib 生成，wbits=-15 裸 deflate）
// 用来验证 Inflate 实现能正确解压真实 deflate 流

import Foundation

enum Fixtures {
    /// (base64 裸 deflate 数据, 解压后的期望文本)
    static let deflateCases: [(String, String)] = [
        ("y0jNyclXKM8vykkBAA==", "hello world"),
        ("C8jILEpUSM5ILCpRyE3MTi1SMDQyNjEFAA==", "Phira chart maker 12345"),
        ("c3QcHgAA", String(repeating: "A", count: 200)),
        ("q1bKS8xNVbJSKkktLlHSUcpJLUvNAXI9/RR8yvQMTZVqAQ==", "{\"name\":\"test\",\"level\":\"IN Lv.15\"}"),
    ]
}
