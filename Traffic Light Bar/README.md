# Traffic Light Bar
🚦 macOS 状态栏轻量化系统负载监控工具，用红绿灯直观显示系统压力状态，无需打开额外窗口即可快速了解系统运行情况。

## ✨ 核心功能
### 状态栏红绿灯状态指示
- 🟢 **绿灯亮**：系统综合负载 < 30%（空闲状态）
- 🟡 **黄灯亮**：系统综合负载 30% ~ 70%（中等压力）
- 🔴 **红灯亮**：系统综合负载 > 70%（高负载）
- 自动适配系统亮/暗模式，图标不跟随状态栏颜色反转

### 综合负载计算规则
加权计算更贴合实际使用感受：
- CPU 使用率：40% 权重
- 内存使用率：35% 权重
- 磁盘使用率：25% 权重
- 默认每秒刷新一次状态，实时响应系统变化

### 交互功能
- **左键点击图标**：弹出系统状态详情面板，显示：
  - CPU、内存、磁盘的具体使用率/使用量
  - 实时网络上传/下载速度、本地IP地址
  - 笔记本设备显示电池电量、充电状态、剩余使用时间
- **右键点击图标**：打开功能菜单
  - 显示/隐藏详情面板
  - 一键开启/关闭开机自启
  - 快速退出应用

### 轻量化设计
- 应用自身内存占用 < 50MB
- CPU 占用 < 0.5%，几乎不消耗系统资源
- 无 Dock 图标、无主窗口常驻，仅状态栏显示
- 无任何第三方依赖，纯原生框架实现

## 🛠 技术栈
- 开发语言：Swift 5.9+
- UI 框架：SwiftUI（原生 macOS 状态栏组件）
- 系统 API：使用 `ProcessInfo`、`sysctl`、`IOKit` 原生接口采集系统性能数据
- 状态管理：Combine 实现数据响应式更新
- 持久化：`UserDefaults` 存储配置，LaunchAgents 实现开机自启
- 最低支持：macOS 13.0 (Ventura) 及以上版本

## 🚀 安装使用
### 方式1：直接编译运行（推荐）
1. 用 Xcode 打开 `Traffic Light Bar.xcodeproj`
2. 选择项目 Target → `General` → 设置最低部署版本为 macOS 13.0+
3. 按 `Cmd + R` 直接运行，即可在状态栏看到红绿灯图标

### 方式2：打包成独立应用
1. Xcode 菜单 → `Product` → `Archive`
2. 选择 `Distribute App` → `Copy App` 导出到本地
3. 把导出的 `Traffic Light Bar.app` 拖到「应用程序」文件夹即可使用

### 隐藏 Dock 图标设置（必选）
为了获得纯状态栏体验，建议开启代理应用模式：
1. 点击项目根目录 → 选择 Targets → `Traffic Light Bar`
2. 切换到 `Info` 标签 → 点击 `+` 添加新键
3. 键名选择 `Application is agent (UIElement)`，值设置为 `YES`
4. 重新编译运行后，应用就不会出现在 Dock 栏了

## 📁 项目结构
```
Traffic Light Bar/
├── Traffic_Light_BarApp.swift    # 应用入口，AppDelegate 绑定
├── AppDelegate.swift             # 生命周期管理、状态栏配置、事件处理
├── TrafficLightIconView.swift    # 红绿灯图标组件、NSImage 扩展
├── SystemMonitor.swift           # 系统性能数据采集（CPU/内存/磁盘/网络/电池）
├── SystemStats.swift             # 数据模型定义
├── ContentView.swift             # 详情面板 UI 实现
└── Assets.xcassets               # 资源文件
```

## ⚙️ 配置说明
### 开机自启
右键点击状态栏图标 → 选择「开机自启」即可，无需手动配置，应用会自动处理 LaunchAgents 配置文件。

### 自定义负载阈值
如果需要修改红绿灯的触发百分比，修改 `AppDelegate.swift` 里 `updateTrafficLightIcon` 方法中的 switch 分支即可：
```swift
switch combinedLoad {
case ..<30: level = .low       // 绿灯阈值，默认30%
case 30..<70: level = .medium  // 黄灯阈值，默认30%~70%
default: level = .high         // 红灯阈值，默认70%+
}
```

## ❓ 常见问题
### Q：运行后看不到状态栏图标？
A：检查状态栏是否有足够空间，或者图标被折叠到了状态栏溢出菜单里（点击状态栏最右侧的箭头即可看到）。

### Q：为什么需要权限？
A：应用仅使用系统公共API采集性能数据，不需要特殊权限，第一次运行如果提示权限请求直接允许即可。

### Q：应用占用资源高吗？
A：非常低，默认每秒刷新一次的情况下，CPU占用不到0.5%，内存占用小于50MB，几乎不影响系统性能。

### Q：如何退出应用？
A：右键点击状态栏红绿灯图标 → 选择「退出」即可。

## 📄 许可证
MIT License，可自由修改分发。

## 🤝 贡献
欢迎提交 Issue 和 PR 优化功能，如有问题可随时反馈。
