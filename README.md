# Phira 谱面工坊 (Phira Maker)

iOS 上的 **Phira** 谱面编辑器。制作谱面 → 导出 `.zip` 谱面包 → 直接在 Phira 里导入游玩。

## 两种模式

| 模式 | 入口 | 适合 |
| --- | --- | --- |
| **新手模式** | 主页左上角「新手」 | 第一次做谱。4 步向导：起名/难度 → 点格子铺音符 → 加音乐插图 → 导出。内置示例谱面，不用理解判定线和缓动 |
| **高级编辑器** | 主页右上角「+」 | 精细控制判定线、父子嵌套、事件层、29 种缓动、音符属性 |

新手模式保存后，可在导出页点「保存并用高级编辑器继续编辑」接着细化。两种模式产出的是同一种 Phira 谱面包。

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

## 导入文件（自签名 App 也能用）

提供三种方式，任选其一：

1. **App 内导入**：主页右上角下载图标 → 系统文件选择器选 `.zip`（已放开全部文件类型，避免变灰选不了）
2. **文件共享（自签名推荐）**：`文件` App → 浏览 → 我的 iPhone → `Phira 谱面工坊` → 把 zip 复制进去 → 回 App 点右上角 `?` → 扫描文件共享目录
3. **从文件 App 分享**：长按 zip → 分享 → Phira 谱面工坊 → 回 App 点右上角 `?` → 扫描

自签名 App 直接读安全作用域 URL 常失败，导入路径统一做了「先复制到临时目录再解析」的兼容处理。

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
