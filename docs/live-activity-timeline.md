# 灵动岛账单时间轴（V19）

Swift 实现位于 `ios/LiveActivityShared/StoreVisitActivityView.swift`，由主 App 和 App Clip 的两个 Live Activity 扩展共用。此轮修改展开态与 compact 进度来源，锁屏保持原有结构。

## 布局

- leading：状态整体在摄像头左侧系统区域内居中，14 pt。封顶明确显示「本时段已封顶」，允许按可用区域缩小至 85%。
- trailing：金额在摄像头右侧系统区域内居中，32 pt，宽度 92 pt，大金额可缩小到 16 pt，避免侵占摄像头区域。
- center：已停留时间，13 pt，不额外添加摄像头下方 padding。
- bottom：入场 / 上一事件 / 服务端下一事件名称，14 pt；三个时间 16 pt。
- 上一事件固定在正中，左半段为压缩历史，右半段为上一事件到下一事件的时间进度。
- 主轨道 7 pt；事件节点 12 pt；蓝色历史使用 6 pt 斜切断口。
- 轨道独占 25 pt 行，居中于上方标签和下方时间之间，延续 V19 的上移结果。
- 底部一行：店名左对齐，允许尾部省略；右侧「距下次事件还有 N 分」，13 pt，优先保留。文字行使用自然高度，避免底部区域压缩字形；时间轴至页脚间隔保持 4 pt。页脚不再单独增加底部或水平 padding。
- 封顶与暂停保留同一时间轴。只按服务端事件名称改变下一事件标签，不根据状态猜测恢复时间。

展开态保留 WidgetKit 默认上下边距，不调用 `DynamicIsland.contentMargins`。时间轴和页脚作为同一个 bottom 区域，两侧统一额外内收 12 pt，页脚不单独加边距。上方状态及金额分别撑满 leading / trailing 区域并居中，两侧均提供 92 pt 的最小宽度，避免没有理想宽度的状态被系统压窄。状态组内部两侧各保留 4 pt 余量，仍以整组为中心，长状态按可用空间缩小；金额自身的 92 pt 容器也居中，避免内部右对齐使字形偏离中点。摄像头避让和两侧区域可用宽度由 WidgetKit 负责，不使用固定机型的摄像头坐标；中间内容不增加摄像头下方 padding。内部时间轴至页脚的 4 pt 间隔保留，compact 与锁屏布局保持原样。并未把 SVG 的固定 371×162 画布直接嵌入灵动岛。

## 数据契约

在 `Bill` 上增加可选 `previousEvent`，复用 `{ atUnix, label? }` 结构。旧 push 和 REST 响应缺少该字段仍可解码。管理器直接解码共享 Bill，不需要另一套转换。

```json
{
  "amountCents": 6000,
  "planLabel": "",
  "asOfUnix": 1770003900,
  "billable": true,
  "previousEvent": { "atUnix": 1770002820 },
  "nextEvent": { "atUnix": 1770004620, "label": "下次计费" }
}
```

同级 `PRiSM/packages/platform/src/live-activity-billing.ts` 已为快照接口和 APNs content-state 增加 **previousEvent**，通过共享计费引擎恢复最近收费、规则或会话节点，覆盖宽限、暂停与单方案/全局封顶；刷新时间不参与事件计算。需要发布后端修改才能在远端环境生效。旧后端或旧载荷缺少该字段时，上一事件时间显示「待更新」，右半轴不绘制比例，compact 显示时钟图标。禁止将 `asOfUnix`、本机刷新时间或未确认的过期 nextEvent 当成上一事件。

只有 `入场 <= 上一事件 <= 当前 < 下一事件` 且数据未 stale 时才显示时间进度。过期数据不继续倒计时；金额只随服务端确认更新，不根据本机计时自行增加。

## 系统计时与设计差异

- iOS 18+：使用系统内置 `SystemFormatStyle.DateOffset` / `Timer` 与 `TimeDataSource`。停留时间显示小时和分钟；倒计时显示单一单位，最后一分钟显示秒，到点停在零，收到 stale 状态后显示「等待更新」。不能把自定义 `DiscreteFormatStyle` 发送到系统渲染进程：模拟器实测会导致整张 Live Activity 的文字变成占位块，普通 SwiftUI 预览无法发现这一问题。
- iOS 17：保留系统 `Text(timerInterval:)` / `.timer` 的计时格式，显示秒，不用静态分钟文本冒充实时计时。
- 右半轨道和 compact 圆环使用系统 `ProgressView(timerInterval:, countsDown: false)`，表示当前事件区间已经过的比例。
- Apple 的时间型 ProgressView 不支持自定义样式，`fractionCompleted` 为 nil。因此删除了原来把 nil 当成满环的自定义样式。白色游标由两个方向相反、使用同一时间区间的系统进度遮罩相交生成，不读取本地静态进度。遮罩先在黑色底上合成，再提高对比度并转为 alpha，去掉系统默认轨道；合成顺序反过来会在两端留下白色残影。
- 系统线性进度的厚度通过缩放匹配设计，应在支持的 iOS 版本上检查最终像素效果。

## 验证与预览

`StoreVisitActivityView.swift` 内有 expanded 与 compact 的 Xcode `#Preview`，展开预览包含计费、封顶、暂停及旧载荷缺失上一事件四种状态。

- `sh test/native/run-prism-activity-check.sh`：旧数据解码、新字段往返、非法/未知区间、刷新不改变事件起点、系统倒计时到点不反向增长。
- `sh test/native/run-prism-activity-manager-check.sh`：恢复活动、最终账单、退出登录的原有行为。
- 两个扩展均应执行 simulator Debug build。
- 真机仍需检查摄像头边缘、长店名/大金额、大字体以及跨事件时的实际推送表现。

参考：[Apple Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)、[时间型 ProgressView 不支持自定义样式](https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:))、[TimeDataSource](https://developer.apple.com/documentation/swiftui/timedatasource)。

## 真实模拟器截图

`test/native/island-preview` 是独立测试宿主，直接编译上述生产共享文件，使用独立 bundle ID 和虚构账单；不请求真实账单，也不改动用户 App 数据。需要 Xcode、XcodeGen 和带灵动岛的已启动 iPhone 模拟器。

```sh
SIMULATOR_UDID=<已启动模拟器的 UUID> sh test/native/run-island-simulator-preview.sh
```

XCUITest 创建真实 ActivityKit 活动，返回主屏幕、长按灵动岛，验证「上一事件」可被系统访问，再截图计费、封顶、暂停、长店名的 expanded，收起后等待金额出现再截 compact，避免系统初次渲染尚未完成时截到空岛。计费状态额外间隔 15 秒截图，用于检查游标与进度同步。脚本将 xcresult、截图和日志输出到临时目录；可通过 `ISLAND_PREVIEW_OUTPUT=/绝对路径` 保留到指定目录，`ISLAND_PREVIEW_TEST=IslandPreviewTests/Screenshots/testCapped` 可以只重截单一状态。测试复用宿主进程，避免模拟器终止 App 时的偶发超时。截屏含模拟器系统外壳，与先前 macOS ImageRenderer 离屏示意图不同。

原生区域分配会压缩没有明确理想尺寸的内容：金额固定理想高度后放入 20 pt 的顶部布局行，允许字形向下延伸；中间停留文字宽 220 pt 并居中；底部倒计时宽 174 pt 并右对齐。这样保留原有四区布局，同时避免金额缩成 16 pt、停留文字截断和店名被挤掉。摄像头可用区域仍由系统决定，不能承诺跨机型物理间距恒为 0 px。

2026-09-30 两侧居中与内收验证：iOS 26.5 / iPhone 17 Pro 独立测试模拟器，计费、封顶、暂停和长店名四个 XCUITest 全部通过。目视检查四张展开态：上方状态和金额保持居中；封顶与暂停文字完整，圆点完整；底部店名和倒计时不再被圆角裁切，长店名正常省略。原生 compact 圆环保留。两张后台截图间隔 16.2 秒，白色游标向右移动 17.86 个原生像素（3x）。共享 Swift 编译、Dart format 和 Flutter analyze 通过。公开预览采用本轮 9 张原始截图，真实设备及其他机型仍需校准。此前 App Clip 扩展 simulator Debug build 及原生 Codable/计时检查均通过。
