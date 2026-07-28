# PerfMonitor

PerfMonitor 是一个运行在 macOS 菜单栏的性能监控工具，提供 CPU、内存、网络上下行、磁盘 I/O、FPS 的实时监控，并支持悬浮 HUD、历史趋势窗口、配置导入导出与打包分发。

## 功能概览

- 菜单栏实时状态（动态 CPU 图标 + 文本）
- 下拉面板：实时指标 + 趋势图 + 设置
- 悬浮 HUD：置顶小窗，适合常驻观察
- 历史窗口：支持 1h / 24h 范围与多指标切换
- 配置导出/导入（JSON）
- 开机启动（Launch at Login）
- 告警阈值与通知（本地通知）

---

## 架构设计

### 1) 分层结构

1. **App 入口层**
   - `PerfMonitorApp.swift`
   - 职责：创建 `MetricsViewModel`，绑定菜单栏、Overlay、History 窗口协调器。

2. **状态与业务层**
   - `MetricsViewModel.swift`
   - 职责：
     - 管理实时快照与历史数据
     - 管理用户设置（`UserDefaults` 持久化）
     - 负责阈值告警、通知、导入导出配置
     - 对 UI 暴露统一状态与格式化访问接口

3. **系统采集层**
   - `SystemMetricsProvider.swift`
   - 职责：采集系统指标：
     - CPU（Mach host statistics）
     - 内存（vm_statistics64）
     - 网络（`getifaddrs`）
     - 磁盘 I/O（IOKit）
     - 显示刷新率（FPS）

4. **UI 展示层**
   - `MenuContentView.swift`：菜单主面板（Monitor / Settings）
   - `OverlayView.swift`：悬浮 HUD 视图
   - `HistoryWindowView.swift`：历史趋势图（Charts）
   - `MiniTrendChart.swift`：轻量趋势图组件
   - `MenuBarCPUIcon.swift`：菜单栏动态 CPU 图标

5. **窗口协调层**
   - `OverlayWindowManager.swift` + `OverlayCoordinator`
   - `HistoryWindowManager.swift` + `HistoryCoordinator`
   - 职责：管理 AppKit Window/Panel 生命周期与主题同步。

6. **配置与主题模型**
   - `AppSettings.swift`：配置导入导出模型（Codable）
   - `AppTheme.swift`：主题枚举（System / Light / Dark）
   - `MetricFormatting.swift`：字节速度/FPS 格式化工具

### 2) 数据流

- 定时器触发：`MetricsViewModel` 按刷新频率拉取 `SystemMetricsProvider.readSnapshot()`
- 快照更新：写入当前 `snapshot` + 短期 `history` + 长期 `longHistory`
- UI 订阅：SwiftUI 通过 `@ObservedObject / @StateObject` 响应式刷新
- 告警链路：`evaluateAlerts()` 判断阈值，触发本地通知（带冷却）

### 3) 关键设计点

- 菜单窗口与滚动区分离，避免 `MenuBarExtra(.window)` 高度计算问题
- Overlay/History 采用 AppKit Window 托管，稳定控制窗口行为
- 配置 JSON 解码兼容旧版本字段，便于迭代升级

---

## 目录结构（核心）

```text
PerfMonitor/
├── Package.swift
├── .env
├── scripts/
│   └── release.sh
├── Sources/PerfMonitor/
│   ├── PerfMonitorApp.swift
│   ├── MetricsViewModel.swift
│   ├── SystemMetricsProvider.swift
│   ├── MenuContentView.swift
│   ├── OverlayView.swift
│   ├── OverlayWindowManager.swift
│   ├── HistoryWindowView.swift
│   ├── HistoryWindowManager.swift
│   ├── MenuBarCPUIcon.swift
│   ├── MiniTrendChart.swift
│   ├── MetricFormatting.swift
│   ├── AppSettings.swift
│   └── AppTheme.swift
└── dist/
```

---

## 本地开发

```bash
cd /Users/bytedance/code/demo/PerfMonitor
swift build
swift run
```

---

## 打包与发布流程

项目已内置自动化脚本：`scripts/release.sh`

### 1) 准备 `.env`

`.env` 已创建在项目根目录，填写你的证书、profile 和 Sparkle 配置：

```bash
VERSION="0.1.2"
BUNDLE_ID="com.yourcompany.perfmonitor"
APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
ICON_ICNS_PATH="assets/AppIcon.icns"
NOTARY_PROFILE="AC_PROFILE"
NOTARIZE="1"

# Sparkle 自动更新（首次运行 scripts/setup-sparkle.sh 生成后填入）
SPARKLE_PUBLIC_KEY="..."
SPARKLE_TOOLS_DIR="/Users/you/.sparkle-tools/bin"
GITHUB_USER="your_github_username"
GITHUB_REPO="PerfMonitor"
```

### 2) 执行打包

脚本会**自动读取 `.env`**，直接运行即可，无需手动 `source` 或传参：

```bash
./scripts/release.sh
```

脚本会依次完成：编译 → 创建 .app → 嵌入 Sparkle.framework → 签名 → 打 .pkg → 公证 → 生成 appcast.xml。

#### 临时覆盖某个参数（可选）

如需临时指定不同的版本号或证书，可用命令行参数覆盖 `.env` 里的值：

```bash
./scripts/release.sh --version 1.2.0 --notarize
```

完整参数列表：

```
--version <ver>              App 版本号
--bundle-id <id>             Bundle Identifier
--icon-icns <path>           .icns 图标路径
--app-sign <identity>        Developer ID Application 证书
--installer-sign <identity>  Developer ID Installer 证书
--notary-profile <profile>   notarytool keychain profile 名称
--notarize                   提交公证并 staple
```

### 3) 图标说明

- 默认读取 `assets/AppIcon.icns`。
- 可通过 `.env` 中的 `ICON_ICNS_PATH` 或 `--icon-icns` 指定其它路径。

### 4) 产物位置

- App Bundle: `dist/PerfMonitor.app`
- Installer: `dist/PerfMonitor-<VERSION>.pkg`
- Appcast:   `dist/appcast.xml`（配置 Sparkle 后自动生成）

### 5) 验证安装包

```bash
spctl -a -vv -t install "dist/PerfMonitor-${VERSION}.pkg"
```

---

## 证书与公证前置条件

你需要准备：

- Apple Developer Program 账号
- `Developer ID Application` 证书
- `Developer ID Installer` 证书
- `notarytool` keychain profile（用于公证）

查看本机证书：

```bash
security find-identity -v -p codesigning
security find-identity -v -p basic
```

---

## 注意事项

- `.env` 已加入 `.gitignore`，不要提交证书信息或 Sparkle 私钥。
- 如果只做本机测试，可不配置签名参数，脚本会退回 ad-hoc 签名。
- 对外分发建议始终走“签名 + 公证 + staple”。
- 旧版 README 里的 `set -a; source .env; set +a` 步骤**不再需要**，脚本会自动处理。
