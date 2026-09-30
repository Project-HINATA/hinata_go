# 灵动岛 / 实时活动 UI 重构决策文档

> 状态：**历史方案**。展开态与锁屏已由 [V19 时间轴实现](live-activity-timeline.md) 替代；本文保留旧圆环方案的设计背景。
> 日期：2026-09-27
> 范围：`ios/LiveActivityShared/`（三 target 共享），不含后端契约变更
> 视觉规范：`dynamic-island-preview.svg` / `.png`（由 `tool/generate_live_activity_preview.py` 生成）

---

## 0. 背景

用户反馈现有灵动岛「太丑」。本文件先归档现状与问题诊断，再给出重构方案，作为后续改 `StoreVisitActivityView.swift` 的依据。

---

## 1. 现状统计

### 1.1 数据链路（三段式）

| 层 | 类型 | 内容 |
|---|---|---|
| 静态身份 | `StoreVisitAttributes` | `sessionId` / `shopCode` / `shopName` / `origin` |
| 推送快照 | `ContentState` | `phase` / `startedAtUnix` / `endedAtUnix?` / `bill?` |
| 后端聚合 | `Bill` | `amountCents` / `planLabel`（保留但**已不渲染**）/ `asOfUnix` / `remainingToCapCents?` / `billable?` / `nextEvent?` |
| 派生模型 | `StoreVisitDisplayModel` | phase、billingState、isStale、accent、stateSymbolName、各类文案 |

关键约定：`remainingToCapCents` / `billable` / `nextEvent` 都是「**上次推送时刻**」的快照，后端在每个边界（计费点、规则切换、封顶窗口切换、营业状态翻转、锚点翻滚）重推；**Swift 侧不做任何时间轴推算**。

### 1.2 各展示面当前渲染的信息

| 展示面 | 槽位 | 内容 |
|---|---|---|
| compact | leading | 24pt 圆环倒计时（`ProgressView(timerInterval:)`）；无 nextEvent 时退化为状态图标 |
| compact | trailing | 金额，整元免小数（`45`） |
| minimal | — | **仅一个 SF Symbol**（clock / pause.circle / creditcard.circle / checkmark.circle） |
| expanded | leading | 44pt **空芯**圆环，贴靠摄像头左侧 |
| expanded | center | 事件标题（`下次计费`，secondary） |
| expanded | trailing | 竖排 3 行：相对倒计时（accent）/ 金额 / `距封顶还差 xx.xx` |
| expanded | bottom | 店名（primary semibold） ‖ `在场 1小时23分钟`（或 `数据更新于 hh:mm`） |
| 锁屏 | 卡片 | 48pt 环 ‖ 事件栈（标题 + 倒计时） ‖ 金额列（金额 + 距封顶）；页脚同上；外边距 14pt |

### 1.3 状态机

- `phase`：`billing` / `awaitingCheckout` / `settled`
- `billing` 子态：`metering` / `capped`（`remainingToCapCents == 0`）/ `paused`（`billable == false`）
- accent 单色策略：绿 = 计费中、蓝 = 暂停、橙 = 待结账、灰 = 已结算；`keylineTint` 同步
- 倒计时只在 `billing && !isStale` 且事件时间未过期时出现

### 1.4 代码状态

- 仓库真实路径 **`/Volumes/HDD/Projects/hinata_go`**（外接卷，非 `~/Projects`），分支 `main`。
- 三个 Swift 文件共 884 行：`StoreVisitAttributes` 68 / `StoreVisitActivityView` 392 / `StoreVisitLiveActivityManager` 416。
- `LiveActivityShared` 被 **3 个 target 共享**：`Runner`、`HINATALiveActivityExtension`、`PrismClipLiveActivityExtension`。后两个 extension 渲染**同一个 widget**，改 View 会同时影响三者。
- 管理器调用点：`Runner/AppDelegate.swift`、`Runner/PrismURLBridge.swift`、`PrismClip/PrismClipApp.swift`、`PrismClip/MachineLoginViewModel.swift`。
- 未提交改动正在大改 expanded：View 约 ±297 行、`Localizable.xcstrings` 删 4 个 key、`dynamic-island-preview.svg/.png` 重画。
- **设计规范与代码已漂移**：`dynamic-island-preview.svg/.png` 写的是「剩余分钟嵌在环心（Watch 计时器样式）」，但 Swift 里环心是空的（源码注释明写 `The center stays empty`）。两份规范不同步。
- **死代码**：`Localizable.xcstrings` 里的 `入店` 已无任何 Swift 引用（`startedAtText` 被删除），应清理。
- **无视图自动化验证**：`test/native/run-prism-activity-check.sh` 仅用 `swiftc` 编译数据模型（ActivityKit 协议在 macOS 不可用，脚本内 stub），不覆盖任何布局。视觉只能靠 `dynamic-island-shots/` 手动截图。

---

## 2. 目标形态（手绘稿解读）

草图 `IMG_20260927_015342.png` 描述的是**扩展式（expanded）**的新布局。三个关键约束：

1. **黑色涂块 = 原深感摄像头的避让区**，位于岛内部顶部中央；内容不画进这个区域。
2. **摄像头正下方 = 事件信息**：事件名称 + 还剩多少分 + 具体几点钟。
3. **左侧圆环**纵向跨「摄像头 + 事件信息」两段，**环的底边与事件信息最后一行的底边对齐**。
4. **右上角 = 计费价格**，价格下方再放其他支持信息。

```
        ┌──── 摄像头避让区 ────┐
 ⭕              事件名称                  计费价格
 │          还剩 6 分 · 13:24            ────────
 ↓           （↕ 环底与末行底部对齐）      ────────
 ────────────                    ──────        ← 页脚（左长 / 右短）
```

草图比例对这一读法完全自洽：环顶 14% ≈ 摄像头顶 13%，环底 65% ≈ 事件信息底 61%。

| 区域 | 草图表现 | 语义 |
|---|---|---|
| 顶部中央 | 黑色实心涂块 | **原深感摄像头避让区**（岛内部，不画内容） |
| 摄像头下方 | 灰线 ×2 | **事件信息**：名称、还剩多少分、具体几点钟 |
| 左侧 | 大绿色圆环 | 状态环，纵向跨摄像头 + 事件信息，**环底与事件末行对齐** |
| 右上角 | `6` + 圆角方块 | **计费价格**（整体读作 60） |
| 价格下方 | 灰线 | 其他支持信息 |
| 底部 | 左长右短两段灰线 | 页脚（店名 + 更新时间） |

**按 371pt 岛宽换算的关键比例**

- 环直径 ≈ 岛高 51%、岛宽 19.5%，纵向居中偏上（占 14%–65% 高度）
- 摄像头避让区宽约 40% 岛宽（实际机型约 125pt），纵向占 13%–35%
- 草图岛高 ≈ **170pt**（当前仅约 136pt）→ 目标是一个**更高**的岛；实现建议收敛到 152pt，落在 HIG 的 84–160pt 区间内
- 页脚与环底之间留有一条明显空白带（约 23% 岛高）

**与现状的核心差异**：三列分工固定下来——**左列状态环 / 中列事件信息（摄像头在上方避让）/ 右列计费价格 + 支持信息**，横跨全岛宽，页脚独立成行。

---

## 3. HIG 对照（Apple Live Activities，2025-12-16 版）

| # | HIG 要求 | 现状 | 判定 |
|---|---|---|---|
| 1 | 在原深感摄像头周围紧凑绕排内容，避免四周留太多空间 | center 只放一个 `下次计费`，上下大片留白 | ✗ |
| 2 | 使用一致的外边距与同心摆放 | leading 8 / trailing 16 / bottom 16，锁屏又是 14，共三套值 | ✗ |
| 3 | 用中等或更粗的大号文本，谨慎用小号文本 | `距封顶还差` 12pt 还挂 `minimumScaleFactor(0.65)`，实际缩到约 9pt | ✗ |
| 4 | 聚焦一眼可读的重要信息 | 岛内同时塞 7 项；`距封顶` 属二级财务细节 | ✗ |
| 5 | 紧凑式前后两元素应传达**单条**信息，颜色字体统一 | compact = 绿环 + 白色金额，两条信息、两套色 | ✗ |
| 6 | 极简式应显示更新信息而非仅呈现标志 | minimal 只有一个图标 | ✗ |
| 7 | 动态更改扩展式/锁屏高度：内容少则降低 | svg 里写「待结账 / 已结算高度收缩」，代码未实现 | ✗ |
| 8 | 扩展式是紧凑式的放大版，维持元素相对摆放位置 | expanded 多出浮在中间的标题，破坏对应关系 | △ |
| 9 | 用动画展现内容替换与布局更改 | 金额跳变为硬切，无 `.contentTransition(.numericText())` | △ |
| 10 | keyline 着色与内容一致 | `.keylineTint(model.accent)` | ✓ |
| 11 | 锁屏使用 14pt 标准外边距 | 水平/垂直均 14 | ✓ |
| 12 | 不自定义岛内背景色 | 未自定义 | ✓ |

---

## 4. 重构方案

### 4.1 信息架构：先收敛到三层

| 层级 | 内容 | 字号/字重 |
|---|---|---|
| **L1 一眼级** | 状态、金额、下一次事件的倒计时 | `.title3.semibold` 起，accent 色 |
| **L2 补充级**（2×2 栅格） | 在场时长 / 距封顶 / 入店时间 / 事件名 | `.footnote` |
| **L3 页脚** | 店名、结束时间 | `.footnote`，secondary |

- 从岛内**移出**：`planLabel`（已移）、把 `距封顶还差 xx.xx` 的长句改为**纯数值 + 单位**，避免被压缩
- **禁止** `minimumScaleFactor < 0.8`；宁可截断，不用缩字换信息量

### 4.1b 标准展开尺寸（设计基准）

Apple HIG 的实时活动规范表给出的 iOS 尺寸（单位 pt）：

| 展示形态 | 尺寸 |
|---|---|
| 扩展式 | **371 × 84–160**（iPhone 17 Pro / 16 Pro / 15 Pro / 17 / 16 / 15）<br>**408 × 84–160**（Pro Max / Plus / Air） |
| 紧凑式 leading / trailing | 52.33 × 36.67（393pt 屏）· 62.33 × 36.67（430pt 屏） |
| 极简式 | 36.67–45 × 36.67 |
| 锁屏 | 同宽 × 84–160 |
| 灵动岛圆角半径 | **44pt**（弧度与深感摄像头匹配） |

结论：**展开态的「完整形」就是 371 × 160pt，比例约 2.3 : 1**（对比紧凑态 230 × 36.67 ≈ 6.3 : 1，展开后明显更「方」）。
之前几版为了紧凑把高度压到 124–142pt（比例 2.6–3.0 : 1），偏扁；本版按规范用满 160pt 重排。

### 4.2 布局：三列固定分工

| 区 | 内容 | 说明 |
|---|---|---|
| `leading` | 状态环（直径 **56–68pt**，随岛高缩放） | **环的上边距 = 左边距 = 24pt**；环底对齐事件末行底部；**环心嵌剩余分钟**（无倒计时时显示「待付」「已付」等两字状态词） |
| `center` | 事件信息**两行**，顶部**顶到摄像头下沿**（间距≈0） | 事件名称 17–18pt secondary / 具体时刻 22–24pt **状态色** semibold。**左边界贴住状态环**（x=118 = 环右缘 + 16pt，不再与摄像头左对齐）—— 只约束顶部，不约束左右 |
| `trailing` | 上带竖排，下带并入页脚行 | **上带**：① 「计价」17pt + 金额 **28–34pt**（同基线、右对齐，**金额上边距 = 右边距 = 24pt**）② 距封顶。**下带**：在场 / 入店 与店名同处一行、右对齐成组。后三条以**图形标签**替代汉字 |
| `bottom` | 页脚**一行** | 店名 17pt（锚左下 24pt inset）+ 入店 15pt / 在场 17pt（右对齐成组），三者同基线 |

**汉字 → 图形的替换方案（第 ②③④ 条）**

| 原标签 | 替换 | 理由 |
|---|---|---|
| 距封顶 | **刻度条**（按剩余比例填充） | 抽象概念没有通用图标；用比例条能直接表达「还剩多少」，比任何图标或文字都准确。已达上限时刻度条为空 |
| 在场时间 | **秒表图标** | 数值本身是时长格式（`1小时23分`），图标只做冗余提示 |
| 入店时间 | **`figure.walk.arrival`**（SF Symbols 原生符号：一道墙/门沿 + 向左迈步的人） | 「入店」是个动作，人比箭头直白；数值本身是时刻格式（`11:55`），与在场那条靠格式即可区分 |

Swift 侧对应：在场用 `Image(systemName: "timer")`，入店用 `Image(systemName: "figure.walk.arrival")`，两者都是原生符号、笔画一致；刻度条用 `Capsule` + 比例 `fill` 自绘。三者全部 tint 成 secondary，不抢 accent。

> 选型过程：先试过自绘「人 + 门框」，但手绘的笔画粗细/人体比例压不住原生符号，视觉上明显更糙。故改为直接采用 `figure.walk.arrival`——它本身就是「一道墙 + 向左迈步的人」，语义上就是「抵达/进门」。
> 备选（均已实物比对过）：`figure.walk.departure`（同形但人向外走，适合「离店」）、`door.left.hand.open`（只有门、没人）、`arrow.right.to.line`（箭头入线，最抽象）。

设计意图（HIG「在原深感摄像头周围紧凑绕排内容……有助于削弱摄像头的存在感」）：

- **事件信息顶部紧贴摄像头下沿**，间距约 2pt（≈0），让摄像头被内容包住，而不是留出一圈黑边；
  横向不再要求与摄像头左对齐，改为**贴住状态环**（环右缘 102 → 文字左边界 118，间距 16pt）
- **剩余分钟嵌进环心**（19pt accent + 11pt 单位），把事件信息从三行收到两行，环也随之从 78pt 缩到 **56pt**；
  这是回到 2026-09-25 那版预览稿的设计，不再算「规范漂移」
- **金额做成竖向大组件**放在摄像头右侧的空置带上，**上边距与右边距同为 24pt**（与环的「上边距 = 左边距」对称）
- 「计价」放在金额**左侧并与金额同基线**，字号从 12pt 提到 **17pt**
- **在场 / 入店 / 距封顶 三个汉字改为图形**，位置不变、字宽省下来
- **入店时间与在场时间相邻成组**（顺序为 入店 → 在场），14pt / 12pt 两级字号表达优先级
- **店名放大到 14pt** 并锚定左下 24pt inset
- **上下两带**：上带（hug 摄像头）＝状态环 + 事件信息 + 金额/距封顶，**三列底边严格齐平**（环底 102 = 事件信息末行底 = 距封顶行底）；
  下带＝店名 + 在场 + 入店 收成**一行**，横跨全宽。两带之间留 30pt 断口，把「正在发生」和「本次到店」在视觉上分开
- **按 phase 收缩高度**：`billing`（计费中 / 已封顶 / 暂停中）**160pt（用满规范上限）** → `awaitingCheckout` 148pt → `settled` 136pt
- **不要求**环顶与摄像头顶对齐
- **紧凑式**：环心与胶囊端帽的圆心重合
- 锁屏沿用**同一套 24pt 栅格**

> 取舍说明：环缩到 56pt、事件信息收到两行后，左侧重量被削了两次而右列仍是 4 行，重心一度整体压向右边。
> 先改成上下两带仍留了左下空洞；最终把下带收到一行，空洞消失、岛高再降 10pt。
> **代价**：在场 / 入店 由竖向排列改为并排一行（原先的竖向成组要求作废）。

### 4.3 颜色：按信息分组上色

HIG 对实时活动的两条颜色要求：「使用颜色表达 App 的特征和识别度……醒目的颜色有助于**强调实时活动本身中元素之间的关系**」。
App 本身用 Material You（`dynamic_color`），没有固定品牌色，因此这里用**语义分组**来用色，而不是随便多彩。

| 颜色 | 覆盖元素 | 表达什么 |
|---|---|---|
| **状态色**（随状态变）<br>计费中绿 `#30D158` / 暂停中蓝 `#0A84FF` / 待结账橙 `#FF9F0A` / 已结算灰 `#8E8E93` | 状态环、环心剩余分钟、**事件时刻**、keyline | 「现在处于什么状态、正在等什么」—— 把倒计时环和它指向的那个时刻绑成一色 |
| **额度琥珀** `#FFB020`（固定） | 距封顶刻度条 + 距封顶数值 | 「额度还剩多少」——与状态解耦，避免和状态色互相干扰；已达上限时刻度条清空 |
| **中性** primary / secondary | 计价标签、计费金额、在场、入店、店名 | 其余一律不上色 |

- 事件时刻只在**计费类状态**（计费中 / 已封顶 / 暂停中）上状态色 —— 那里它确实是倒计时环指向的目标；待结账 / 已结算没有倒计时，就不上色
- 计费金额保持**中性白**：它是全岛最大的数字，再染色会和状态色抢注意力（HIG 也提醒不要让元素过度吸引对灵动岛的关注）
- compact 的 trailing 金额与状态同色，满足 HIG 对紧凑式「两极读成一条信息、颜色一致」的要求
**字号方案（rev 13 随岛高上调一档）**

| 元素 | rev 13 | 上一版 |
|---|---|---|
| 计费金额 | **34–40pt** | 30–36 |
| 事件时刻 | **22–24pt** | 20–22 |
| 环心剩余分钟 | **22pt** + 13pt 单位 | 20 + 12 |
| 计价标签 | **17–20pt** | 16–18 |
| 事件名称 | **17–18pt** | 15–16 |
| 在场 / 店名 | **17pt** | 15 |
| 距封顶 / 入店 | **15–17pt** | 13–15 |

- 岛从 132pt 长到 160pt（+21%）后，原本按小岛配的字号显得空，因此整体上调一档；环直径随之变为 77 / 69 / 61pt（各态）
- 字重只用两档：L1 用 22–40pt（semibold 及以上），L2/L3 用 15–18pt；**禁止** `minimumScaleFactor < 0.8`

### 4.4 动效

- 金额与倒计时加 `.contentTransition(.numericText())`
- 事件切换、状态切换用 `.animation(.snappy)`，保留既有元素位置而非移除重建
- 环继续用 `ProgressView(timerInterval:)` 自刷新，不依赖推送

### 4.5 代码组织

- 抽出 `StoreVisitLayout` 常量（栅格 / 字号 / 直径 / 各 phase 高度），三 target 共用
- View 按 zone 拆分：`LeadingRing` / `HeroLine` / `InfoGrid` / `FooterRow`（替换现在职责混杂的 `StoreVisitAmountColumn` / `StoreVisitEventStack` / `StoreVisitShopRow`）
- 清理死 key `入店`

### 4.6 落地顺序

1. 定稿信息架构与视觉稿 →
2. 重画 `dynamic-island-preview.svg` / `.png`（compact / minimal / expanded / 锁屏 全状态矩阵）→
3. 改 `StoreVisitActivityView.swift` →
4. 截图 `dynamic-island-shots/` 与预览稿逐帧对照 →
5. 同步 `Localizable.xcstrings`

---

## 5. 已确认事项

1. ✅ 手绘稿中 `6` + 圆角方块**整体读作 60**，即右上角的计费价格数值。
2. ✅ 摄像头下方的加粗区域**不是文本槽位**，而是摄像头本身；主文本槽位由信息层级推导（见 4.1/4.2）。
3. ✅ 下一步：先重画 `dynamic-island-preview.svg` / `.png` 定死视觉，再动 Swift 代码。

## 6. 预览稿产出

`dynamic-island-preview.svg` / `.png` 已按本文方案重画，覆盖 11 个展示面：

| 区块 | 内容 |
|---|---|
| 扩展式 | 计费中（160pt）/ 已封顶（160pt）/ 暂停中（160pt）/ 待结账（148pt）/ 已结算（136pt） |
| 紧凑式 | 计费中 / 待结账 / 暂停中 / 已结算（环心与端帽圆心重合） |
| 极简式 | 计费中 60 / 待结账 45（用金额替代静态图标） |
| 锁屏 | 计费中（同一套 24pt 栅格） |

预览稿右上角带 `rev` 标记，用来确认看到的是最新一版渲染。当前为 `rev 17`。

预览稿由 `tool/generate_live_activity_preview.py` 生成（`python3 tool/generate_live_activity_preview.py`），改设计只需改脚本里的常量与 `STATES`，不要再手改 SVG。

---

## 附：文件清单

| 文件 | 作用 |
|---|---|
| `ios/LiveActivityShared/StoreVisitAttributes.swift` | 数据契约 |
| `ios/LiveActivityShared/StoreVisitActivityView.swift` | DisplayModel + 三形态 + 锁屏卡片 |
| `ios/LiveActivityShared/StoreVisitLiveActivityManager.swift` | 生命周期 / 推送 token / 恢复对账 |
| `ios/LiveActivityShared/Localizable.xcstrings` | 岛内文案（含死 key `入店`） |
| `dynamic-island-preview.svg` / `.png` | 设计规范稿（由下面的脚本生成） |
| `tool/generate_live_activity_preview.py` | 预览稿生成器（单一事实来源） |
| `dynamic-island-shots/` | 真机截图（`NN-形态-状态.png` + `crop-*.png`） |
| `test/native/run-prism-activity-check.sh` | 仅编译数据模型，不覆盖视图 |


---

## 7. 实现说明（Swift 侧）

落地文件：`ios/LiveActivityShared/StoreVisitActivityView.swift`（三个 target 共享）。所有几何与字号常量集中在该文件顶部的 `IslandLayout` 枚举里，**设备截图对不上时改这里，不要在视图里撒字面量**。

四个扩展区与设计的对应：

| 设计带 | SwiftUI 区 |
|---|---|
| 上带·左（状态环 + 环心剩余分钟） | `DynamicIslandExpandedRegion(.leading)` |
| 上带·中（事件名称 + 时刻） | `DynamicIslandExpandedRegion(.center)` |
| 上带·右（计价 + 金额 / 额度行） | `DynamicIslandExpandedRegion(.trailing)` |
| 下带（店名 + 入店 + 在场 一行） | `DynamicIslandExpandedRegion(.bottom)` |

上带三列齐平靠 `frame(height: model.upperBandHeight, alignment:)` 实现——band 高度就等于环直径，leading 顶对齐、trailing 底对齐，两端自然落在同一条线上。

### 真机首轮反馈后的修正

第一次真机截图暴露了四个问题，其中三个是布局机制层面的：

1. **分区自带内边距。** 实测把环推到了距岛边约 44pt（设计是 24pt）——SwiftUI 已经先给每个扩展区加了约 20pt，我自己的 `padding` 是叠加的。
   → 拆成 `margin`（设计值 24）与 `systemRegionInset`（实测 20），实际 `padding = margin - systemRegionInset`。以后只调 `margin` 就能移动内容。
2. **分区内容默认垂直居中。** 事件信息因此悬在带中央、环孤零零拖在它下面约 40pt —— 这个悬挂的落差（而非环的真实直径）才是「环显得太大」的主因。
   → 给 `.center` 内容加 `.frame(maxHeight: .infinity, alignment: .top)`，让事件信息贴住摄像头下沿，末行自然与环底齐平。
3. **环径回调** 77 → **68pt**（各态 68 / 62 / 56）。因为事件信息实测比草稿矮，原来的 77 是按偏高的估量定的。
4. 另有三个实现细节：环心不能用 `Text(date, style: .relative)`（渲染成「24分钟 0秒」放不下）；扩展区里不能给某个区 `maxWidth: .infinity`（会把相邻区饿死，金额被压成省略号）；padding 累加不能超 160pt 硬上限。

### 第三次修正：内容被压到摄像头下方

截图显示岛顶部约 **37pt 完全空着**（摄像头是黑色、和岛融为一体看不见），环 / 事件 / 金额全都被推到摄像头下方才开始 —— 系统给扩展区预留了「摄像头高度」的上边距，**`.leading` / `.trailing` 并不在摄像头两侧**。

- 环和金额横向与摄像头不重叠，可以提回摄像头旁边：`padding(.top, margin - cameraBand)`（负值，实测把环顶抬到距岛顶 24pt）。
- **中间的事件信息不能提** —— 它正对摄像头（x 118 起，摄像头 123 起），必须留在下方。

`cameraBand = 37` 是唯一需要真机复核的新常量。

### 与视觉稿的两处必要偏差

1. **环心是 mm:ss 计时，不是「22pt 数字 + 13pt 单位」的「6分」。**
   Live Activity 里只有 `Text(_:style:)` / `ProgressView(timerInterval:)` 能自走时、不需要后端推送，多字号拼一个会跳动的倒计时做不到；而 `style: .relative` 实际渲染成「24分钟 0秒」，比环内径宽得多（真机上被截断过）。因此改用 `Text(timerInterval:countsDown:)`，渲染为 `24:37` 这种计时器形式：18pt 单字号（比「6分」那版低一档，因为 mm:ss 更长），环内留有余量。无倒计时的状态（封顶 / 待付 / 已付）仍是静态两字词，排版不受此限。
2. **`.bottom` 与上带之间的间距（`IslandLayout.bandGap`）以及环的上内边距，是按系统默认分区间距估的。**
   真机上第一次截图后校对这两个值即可，其余尺寸都来自本规范。

### 校验方式

- `xcrun -sdk iphonesimulator swiftc -parse-as-library -c` 编译扩展 target 的完整源码集（`StoreVisitAttributes` + `StoreVisitActivityView` + `LiveActivityBundle`）：**两个扩展 target 均零错误零警告通过**。
- `test/native/run-prism-activity-check.sh`、`run-prism-activity-manager-check.sh`：数据模型与生命周期检查通过。
- 视图布局无自动化校验，仍以 `dynamic-island-shots/` 真机截图对照本规范为准。
