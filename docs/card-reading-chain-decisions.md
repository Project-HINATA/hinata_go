# Hinata 读卡链路讨论结论

日期：2026-08-07

## 文档状态

本文记录对 `hinata_go`、`hinata-rs`、`hinata-aimeio-rs` 和
`hinata-neo` 进行行为审计期间已经确认的结论。

本文记录行为约束及本轮同步实现的最终边界。四个工作区的修改仍未提交，后续变更应以
本文语义和对应回归测试为准。

## 通用约束

- 永久轮询循环应与 `hinata_go` 的轮询顺序和生命周期保持一致，但目标项目没有的功能除外。
- 不得把某项目没有的读取功能及其重试逻辑同步过去。例如 AimeIO 不读取 T-Union
  余额和消费记录，因此不能加入余额读取重试。
- 射频干扰、传输错误、超时、短包和畸形响应都属于瞬态失败，不能作为真实卡片结果展示。
- 只有在读卡器取得足够完整且有效的数据后，才能明确判定卡片不受业务支持。
- 同步轮询链路时，不得顺带增加无关的恢复、MIFARE、设备选择或固件更新行为。

## hinata_go：已确认的读取结果语义

### 结果状态

读取链路使用显式结果状态，不再通过 `null`、异常、`targetPresent` 或伪造的卡片子类型
混合表达状态：

- `recognized`：业务卡基础数据完整且有效。
- `confirmedUnsupported`：Type A 目标和所需数据均已完整读取，但可明确判定不属于受支持业务卡。
- `incomplete`：基础读取所需操作因超时、传输、射频、短包、畸形数据等原因未完成。
- `noTarget`：一次完整轮询没有发现目标。

`incomplete` 在本轮按没有有效卡片处理：不进入 UI，永久循环下一轮从头完整读取。

### 不兼容卡片的两轮确认

USB 永久轮询只有在同一 UID、SAK、ATQA 连续两轮得到完整的
`confirmedUnsupported` 结果后，才展示不可在游戏内使用的 Type A 卡。

以下任一情况都会清除待确认结果：

- 没有目标；
- 读取未完成；
- UID、SAK 或 ATQA 改变；
- 成功识别出业务卡。

这套按完整轮询计数的确认替代原有 `InvalidMifare` 的时间窗口确认。

### 手机 NFC

手机 NFC 没有 USB 永久轮询：

- 基础读取未完成时，本次不展示卡片，只弹出一次 Toast 要求用户重新读卡；
- 单次读取已完整且可以明确判定不兼容时，可立即展示该卡片。

### ISO14443A 分流

继续使用现有 SAK 分流：

- `SAK & 0x08 != 0`：MIFARE Classic 路径；
- `SAK & 0x20 != 0`：ISO-DEP / T-Union 路径；
- 两者均不满足：完整取得 UID、SAK、ATQA 后即可确认当前业务读取器不支持该卡，
  不为了证明它不受支持而盲读 Ultralight 或普通 Type A 的任意内存页。

对于 ISO-DEP 目标，结构完整且明确拒绝 T-Union AID 的 APDU 响应属于确定结果。
超时、短包、畸形响应或传输失败只能判定为 `incomplete`。

### MIFARE Classic 分流

密钥选择和读取是否完成必须分别判断：

1. 首先使用已知 Key B 认证。
2. 只有 PN532 明确返回认证失败状态时，才重新激活卡片并尝试 Key A。
3. Key B 认证成功后，后续 block 读取或解析失败不得改用 Key A。
4. Key B 和 Key A 都明确返回认证失败状态时，本轮可判定为
   `confirmedUnsupported`。
5. 认证超时、传输失败、空响应、畸形响应或 block 读取失败属于 `incomplete`，
   交给下一轮重新读取。
6. 所需 block 均完整读取，但内容不符合业务数据校验时，可判定为
   `confirmedUnsupported`。

因此 NFC 传输层必须保留“PN532 明确认证失败”与“超时/读取/传输失败”的区别。

### T-Union 基础和扩展读取

保持现有可见流程：

- SELECT AID、基础卡片信息和余额组成可以立即展示的基础结果；
- 交易记录属于扩展信息；
- 基础信息或余额未读取完整时，属于基础读取未完成；
- 交易记录读取失败时保留已经展示的基础卡，后续循环继续读取扩展信息。

无需把余额模型改成 nullable，也不改变当前展示时机。实现可以优化，但不能改变上述行为。

### 不可游戏卡片的 UI 模型

删除 `InvalidMifareCard`、`InvalidMifareReason` 和序列化的 `type: "unknown"`。
旧 `unknown` JSON 无需迁移。

不兼容卡片继续使用其真实 `Iso14443` 类型并保留 UID、SAK、ATQA。
由 `ScannedCard` 表达当前结果是否可用于游戏。UI 必须：

- 显示真实类型名称，例如 MIFARE Classic 1K、MIFARE Plus、MIFARE Ultralight
  或 Generic ISO14443 Card；
- 显示现有的“无法在游戏中使用”警告；
- 不允许保存；
- 不写入扫描记录；
- 不发送给游戏。

### 卡片在场状态

删除新加入的 `UsbPollResult.targetPresent` 行为。射频场中存在物理目标不等于当前存在
有效卡片结果，不能阻止三次缺失计数。

`incomplete` 和 `noTarget` 在该轮都不产生可见结果。保留现有连续三轮缺失后移除卡片的阈值。

## hinata_go：HID 范围

`hinata_go` 当前仍只支持一台活动读卡器：

- 保留原有单设备热插拔行为；
- 本次不增加设备选择 UI；
- 本次不支持同时轮询多台读卡器；
- 本次不重构多台同型号设备下的固件更新；
- 回退当前未经确认的 `connectionId`、`opened` 身份改动及其测试。

WebHID 可以暴露并打开多台已经授权的设备，但安全支持该功能需要单独设计设备选择、
设备身份、活动读卡器切换，以及固件更新进入 bootloader 后重新枚举的绑定方式。

## hinata-aimeio-rs

### 轮询循环

- 恢复原有 16 ms 轮询 timer 和 `MissedTickBehavior::Skip`；当前测试表明该间隔不影响使用。
- 保留原有 `tokio::select!` 中的 LED 处理。
- 保留连续三次完整轮询缺失后移除缓存卡片。
- 保留 AimeIO 已有的多设备支持。AimeIO 没有设备选择 UI 和固件更新流程，
  因此不代表 `hinata_go` 也要在本次支持多设备。

### T-Union 范围

只有 ISO-DEP 候选卡（`SAK & 0x20 != 0`）才尝试 T-Union 探测。
AimeIO 不读取 T-Union 余额或消费信息，不能加入余额读取重试逻辑。

### MIFARE 行为

- Key A 路径继续使用游戏兼容所需的 Banapass block 2 占位符，不读取真实 block 2。
- Key B 认证失败时可以回退 Key A。
- Key B 认证成功后，读取或解析失败不得回退 Key A。
- MIFARE 未完整读取时，本轮返回无卡，让永久循环下一轮重试；不得向 AimeIO 或游戏暴露残缺卡片。
- 恢复外层将未完整 MIFARE 读取转换为 `Ok(None)` 的行为，避免错误分支不更新缺失计数并保留旧卡。

## hinata-rs

`InRelease` 和 `InDeselect` 是用于强制目标恢复初始状态的清理操作：

- 忽略这些清理命令返回的非零 PN532 目标状态；
- 请求或传输失败仍向上传播；
- 空响应仍视为协议错误。

## hinata-neo

### 永久轮询与快照

- CardManager 按 FeliCa、三档 Type A 功率、必要时 FeliCa 回退的顺序永久轮询。
- PN532 实际 target 和对 Sega 可见的卡片快照分开管理。
- 成功取得 target 后保留 350 ms；每次成功获取的首次 DETECT 可以把该期限重置为
  当前时间加 350 ms，之后的重复 DETECT 不继续叠加。
- 期限到达后后台开始下一轮完整扫描。扫描期间 DETECT 立即返回旧快照，不等待当前轮结束，
  因而持续只发 DETECT 的客户端不会在两轮之间看到无卡空档。
- 同卡重新获取时原子刷新快照且 generation 不变；换卡或完整无卡结果才修改 generation。
- 完整扫描确认无卡后清除快照；扫描命令超时只重启后台轮询，不立即把旧快照当作无卡。

### Sega 命令协调

- 普通 DETECT 立即返回。只有启用 Fastread 且当前无快照时，才最多等待 1800 ms。
- 实际 PN532 操作若撞上后台重扫，会等待 target 就绪；只有重获同一 generation 才执行。
  如果期间换卡、移卡或等待超时，则返回卡错误，绝不把旧请求发给新 target。
- 实际操作期间 CardManager 不让目标到期；操作完成后重新给予 350 ms 保持期。
- PN532 明确返回 `0x01`、`0x27`、`0x29`、`0x2A`、`0x2B` 或 `0x2C` 时立即清除快照。
  其他卡片状态只返回卡错误，不额外执行推测性的 Deselect，也不依赖 CARD_HALT 释放生命周期。
- 普通 Sega 卡操作及 PN532 ACK/响应等待上限为 500 ms；CardManager 自身命令 watchdog
  为 300 ms。1800 ms 只属于 Fastread。

### RADIO 生命周期

- 固件启动后 CardManager 已永久轮询，因此第三方客户端只发送 DETECT 也可以持续取得卡片。
- RADIO_OFF 停止 CardManager，但保留当前快照和 PN532 target，不加入卡片类型特判。
- RADIO_ON 在 CardManager 已停止时清空旧快照并从完整轮询开头重新开始，利用游戏固定的
  约 300 ms 窗口取得新 target。
- 保留项目原有 RADIO_OFF 后 10 秒自动恢复 CardManager 的路径。

### 固件空间

全部八个固件目标都必须小于 14,336 bytes。本轮快照实现增加一个 35-byte XRAM 暂存结构；
最紧的 `HINATA-STD` 从 13,823 bytes 增至 13,895 bytes，剩余 441 bytes Flash。

## 必须回退或重新审查的未确认改动

- Go：Key B 任意读取/解析失败后完整重试 Key A。
- Go：立即展示基础读取失败的卡片。
- Go：`targetPresent` 阻止当前卡片移除。
- Go：没有多设备设计便加入稳定 HID `connectionId`。
- AimeIO：使用真实 block 2 代替游戏要求的兼容占位符。
- AimeIO：改变 MIFARE 错误传播并扩大 Key A 回退范围。
- AimeIO：删除 16 ms timer。
- Neo：固定 1000 ms 的目标保持时间、全局 200 ms PN532 超时。
- Neo：认证失败后自动 `InDeselect`，或依赖 `CARD_HALT` 结束目标生命周期。
- Neo：删除原有 10 秒 CardManager 自动恢复，或加入 RADIO_OFF/FeliCa 会话特判。

## 后续执行纪律

- 修改上述行为前先整理实现计划并得到批准。
- 每项行为修正后运行针对性测试。
- Go 运行 `dart format`、`flutter analyze` 和相关 Flutter 测试。
- AimeIO 使用支持的 Windows target 构建。
- Neo 的每个批准步骤都构建全部固件变体并记录 flash/RAM 变化。
