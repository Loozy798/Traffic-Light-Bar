# Resource Monitor Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修正系统采样并交付简洁、可信的状态栏概览和详细资源仪表盘。

**Architecture:** Foundation 数据模型和纯计算负责指标语义。独立串行采样器负责系统 API，MainActor stores 发布快照；SwiftUI 负责可组合卡片和趋势，AppKit 只处理状态栏及窗口。

**Tech Stack:** Swift, SwiftUI, Charts, AppKit, Darwin, IOKit, ServiceManagement.

**Spec:** docs/superpowers/specs/2026-11-10-resource-monitor-design.md

## Global Constraints
- macOS 15.6；零第三方依赖；按用户后续授权关闭本 app 的 App Sandbox。
- 中文界面，语义色，百分比与字节单位准确；不可用数据不显示成正常。
- 用户选择直接完成，本会话顺序实施；不提交和推送，不改用户的 xcuserstate。

## Review Focus
- 切网 / 计数回退不出现网络峰值。
- 睡眠 / 暂停 / 恢复不发布过期快照。
- 首次采样和权限失败明确显示等待 / 不可用。
- 带空格进程名称、超过 100% 的单进程 CPU 和内存排序正确。
- 窄窗口、全部显示项关闭、电池不存在时布局完整。

### Task 1: 可信数据模型与采样
**Files:** SystemStats.swift, MetricsMath.swift, SystemSampler.swift, SystemMonitor.swift, Tests/MonitorTests.swift, script/test.sh.
**Interfaces:** SystemStats 快照；CPUTicks.usage(since:) -> Double?；NetworkTracker.sample(counters:uptime:) -> NetworkRate；SystemMonitor.stats / history / pause / resume / setInterval。
- [x] 创建并运行回归用例：首次 CPU 等待、ticks 差值为 75%、nice 计数、计数重置、网络接口替换 / 回退 / 长间隔。
- [x] 实现纯计算与串行系统采样，正确读取电池、内存、容量和温控。
- [x] 运行 script/test.sh，通过所有纯计算与模型测试。

### Task 2: 进程采样、偏好和平台动作
**Files:** EnergyMonitor.swift, ProcessSnapshot.swift, AppPreferences.swift, LoginItemManager.swift, AppActions.swift.
**Interfaces:** ProcessSnapshot.parse(_:) -> [AppEnergyInfo]；EnergyMonitor.topConsumers / errorMessage / setActive；AppPreferences 维持已有显示项并增加 refreshInterval / statusDisplay。
- [x] 先验证进程名称空格、RSS 单位、PID、格式错误、CPU 大于 100% 的回归用例。
- [x] 实现安全管道读取、明确错误、稳定身份、CPU / 内存排序，以及登录启动错误反馈。
- [x] script/test.sh 通过。

### Task 3: 简洁概览、趋势与设置
**Files:** ContentView.swift, DashboardView.swift, OverviewView.swift, ProcessesView.swift, PreferencesView.swift, MonitorComponents.swift, AppDelegate.swift.
**Interfaces:** 视图只消费快照；相同 ResourceLevel 驱动状态栏 / 弹窗 / 仪表盘；独立 Settings scene。
- [x] 实现适配深浅色的概览卡片、五分钟趋势和滚动布局。
- [x] 实现搜索 / 排序 / 空态，状态栏显示选项和系统登录项入口。
- [x] 修复窗口复用、popover 委托清理和睡眠 / 恢复。
- [x] Xcode Debug / Release 构建，实际 UI 检查窄窗口、切页、设置和弹窗。

### Task 4: 交付验证
**Files:** script/build_and_run.sh, README.md, .gitignore.
- [x] 提供 kill / build / run 单入口和 --verify / --debug / --logs / --telemetry。
- [x] 运行完整回归、Debug / Release 构建及 UI 冒烟；检查 diff。
- [x] 更新 README，说明采样语义、系统限制和真实验证结果。

验证边界：未执行真实登录重启、强制深色和最小窗口缩放的实机测试；详见 implementation/progress.md。
