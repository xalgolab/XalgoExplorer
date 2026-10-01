# v0.2.0 原生重构计划

日期：2026-10-01

## 目标与工具

使用已安装的 Xcode 27、Swift 6.4、SwiftPM、AppKit 与 SwiftUI。使用 Apple 的 Liquid Glass API：macOS 26 起启用系统玻璃效果；macOS 14/15 使用系统材质。保持 Apple Silicon macOS 应用，不引入网页界面或模拟玻璃。

## 已确认的功能边界

- 保留主工作区与上下两个辅助工作区。导航、查看、排序只作用于所属工作区；新建、剪切、复制、粘贴跟随文件区焦点。
- 标准 AppKit 标题区和红绿灯，保留系统双击标题操作。路径在内容工具条中，与排序/查看同一行。
- 列表使用 NSTableView，图标/预览使用 NSCollectionView。ExplorerModel 保持业务状态源。
- 列宽可调整；支持方向键、Shift/Cmd 多选、圈选、滚动、空白取消选择、文件与空白各自的右键菜单。
- 同卷拖拽默认移动，跨卷默认复制；Ctrl 强制复制、Shift 强制移动。取消和原目录放下不误移动文件。
- 系统剪贴板互通；重命名校验；原目录剪切粘贴不改名；搜索可取消并归还焦点。
- 侧栏默认 Home；固定图标可通过复选菜单隐藏/恢复；用户快捷方式可拖入与移除；挂载卷可推出；网络为空状态。
- 侧栏按内容高度居中，在三工作区下收起，只有局部边缘悬停/拖入触发；保留滑动和始终两个图标的间距。
- 工具提示及既有语言选择继续有效，支持系统浅色/深色与辅助功能设置。

## 实施顺序

1. [x] 检查工具、当前代码和 Apple API；原有 55 项测试全部通过。
2. [x] 重构统一原生玻璃控件、响应式工具条与可调整工作区；清除未使用的旧文件区实现。
3. [x] 优化 AppKit 文件区刷新、选择、拖拽、键盘和菜单；统一焦点路由。
4. [x] 同步版本、补充关键回归测试，编译与测试。
5. [x] 启动新版进行原生界面与交互检查，生成本地候选安装包，记录验证结果及未覆盖项。

## 验证

先通过 SwiftPM 测试，再构建签名 app 和 DMG。真实界面检查单/三工作区、长路径、搜索输入与取消、方向键滚动、右键多选、侧栏悬停和拖拽。测试文件操作只使用临时目录。记录实际完成和未覆盖的测试，不将编译通过等同于交互验证。

### 已验证

- Xcode 27 / Swift 6.4 / Apple Silicon / macOS 27 环境下，96 项 XCTest 全部通过；原有基线为 55 项。
- 原生窗口实测：单/三工作区切换、主工作区独立上级导航、列表/图标切换后的 first responder、长路径工具条布局。
- 原生搜索完整接收输入，Esc 清空搜索并归还文件区焦点。
- 连续 24 次方向键及 8 次 Shift 扩展选择后，列表选中端点仍可见；图标模式连续方向键可滚动。
- 临时文件通过 Cmd+C 复制，在另一工作区的空白右键菜单执行粘贴成功；文件菜单仍保留打开方式、复制 URL、剪切、复制、粘贴、废纸篓、重命名和属性。
- 十语言命令覆盖、文字输入与文件命令隔离、三工作区焦点切换、原目录剪切粘贴、无效重命名、内部拖拽取消、外部剪贴板以及旧 payload 隔离均有回归测试。
- 选择变化不重建文件单元格；仅修改元数据的项目局部更新；列宽同步不重复发布。
- `make app` / `make dmg` 成功；`codesign --verify --deep --strict`、`hdiutil verify` 和 SHA-256 校验通过。
- 交付物：`dist/xAlgo Explorer.app`、`dist/xAlgo_Explorer_v0.2.0-candidate_aarch64.dmg`；本地分支 `codex/native-glass-v0.2.0`。

### 尚需验收

- 自动化原生拖拽会话未完成落点，Esc 后原文件保持不变；不把侧栏拖入创建快捷方式、长距离拖动圈选及真实跨卷拖放记为通过。
- macOS 14/15 的系统材质回退、macOS 26 运行、浅色/高对比度/减少动态效果仍需对应环境实机检查。
- 当前候选包使用本机 ad-hoc 签名，未做 Developer ID 公证，不等同于可公开分发的已公证发行版。
- 按用户后续发布请求，通过 GitHub 预发布交付；发布入口与验证边界见 [v0.2.0 发布说明](releases/v0.2.0-candidate.md)。不将本候选版提升为稳定版。

### Apple 原生 API 参考

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)
