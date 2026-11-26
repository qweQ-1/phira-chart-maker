# Phira 谱面工坊 (Phira Maker)

iOS 上的 **Phira** 谱面编辑器。制作谱面 → 导出 `.zip` 谱面包 → 直接在 Phira 里导入游玩。

## 功能

- **钢琴卷帘式音符编辑**：点网格落子，长按编辑属性
- **四种音符**：Tap / Hold / Flick / Drag，Hold 可拖长度
- **判定线管理**：多判定线、父子嵌套、事件层、缓动曲线（29 种）
- **BPM 编辑**：支持中途变速，自动换算拍 ↔ 秒
- **谱面信息**：曲名、难度、谱师、曲师、曲绘、标签、简介
- **导入**：Phira 谱面包 `.zip`、裸 `.json` 谱面文件
- **导出**：Phira 谱面包 `.zip`（RPE / PEC 双格式）

## 导出的谱面包结构

Phira 的谱面包是一个 zip，解压后**直接是文件**（不是文件夹）：

```
info.yml         元信息（Phira 以此为准）
chart.json       RPE 谱面（或 chart.pec）
song.ogg         音乐（.mp3/.ogg/.wav/.flac）
background.png   插图
```

导入方式：Phira → 本地 → 导入谱面 → 选这个 `.zip`。

## 格式依据

实现严格对照 Phira 官方源码与文档：

| 内容 | 来源 |
| --- | --- |
| 谱面包结构 / `info.yml` | [phira-docs chart-standard](https://github.com/TeamFlos/phira-docs) |
| `ChartInfo` 字段 | `TeamFlos/phira` → `prpr/src/info.rs` |
| RPE 解析规则 | `TeamFlos/phira` → `prpr/src/parse/rpe.rs` |
| 导入导出逻辑 | `TeamFlos/phira` → `phira/src/scene/song.rs` |

`Tools/verify_package.py` 是一个独立的严格校验器，用 Python 复刻 Phira 的 Rust 解析器逐字段检查谱面包。

## 构建

```bash
xcodegen generate
xcodebuild -project PhiraMaker.xcodeproj -scheme PhiraMaker \
  -destination 'generic/platform=iOS' archive
```

CI（`.github/workflows/build.yml`）会跑单元测试并打包未签名 IPA。

## 许可

仅供学习交流使用。Phira 与其谱面标准版权归 TeamFlos 所有。
