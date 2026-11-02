# Changelog

HINATA Go for Android, iOS and the web (<https://go.neri.moe>).

## 2.9.0 - 2026-11-03

### 中文

- 现在读 Felica 卡片会读取所有系统，并且会保存所有未加密的块，模拟的时候也会用上这些数据
- 读 Suica 的时候会优先读取交易记录，同一张卡重新扫描的话会合并进之前的交易记录里
- 读卡器固件更新到 2026110220 及以上之后，用读卡器读 Felica 卡片会快很多，模拟 NDEF 标签的时候一次也能传更多数据了

### English

- Reading a FeliCa card now reads every system and saves every unencrypted block, and emulation uses that data too
- Suica history is read first, and scanning the same card again merges into the history you already have
- With reader firmware 2026110220 or later, reading FeliCa cards through the reader is a lot faster, and emulated NDEF tags can send more data at a time

## 2.8.0 - 2026-10-24

### 中文

- 现在可以在项目内读取 NDEF 标签和添加 NDEF 数据集
- 现在支持了 NESiCA 的读取和保存，贡献来自社区 PR
- 现在可以直接使用读卡器模拟在卡包内保存的 NDEF 数据集和 Felica / Amusement IC 卡片
  - 需要读卡器固件更新至 2026102022-8e2ac084
  - 但是要注意模拟出来的 Felica 与 Amusement IC 卡片无法用于 SEGA 游戏官方服务器，可以用于私服以及 Konami 游戏
  - 该功能仅限 Android 手机或 Web 端的 HINATA Go 连接 HINATA 读卡器使用，iOS 不支持
  - 以后你出勤可以携带一台安卓手机和一台 HINATA 读卡器便可以刷卡（x
- iOS：正式适配了 iPhone Duo
- iOS：更多的 Liquid Glass 和 iOS 原生动画
- iOS：支持了 NDEF 标签和 NESiCA 的扫描

### English

- You can now read NDEF tags and add NDEF datasets in the app
- NESiCA cards can now be read and saved, contributed by a community PR
- The reader can now directly emulate the NDEF datasets and FeliCa / Amusement IC cards saved in your wallet
  - Needs reader firmware 2026102022-8e2ac084
  - Note that emulated FeliCa and Amusement IC cards don't work with official SEGA game servers, but they do work with private servers and Konami games
  - Only for HINATA Go on Android or the web connected to a HINATA reader; iOS isn't supported
  - From now on an Android phone and a HINATA reader are all you need to swipe in at the arcade (x
- iOS: proper support for iPhone Duo
- iOS: more Liquid Glass and native iOS animations
- iOS: scans NDEF tags and NESiCA

## 2.7.1 - 2026-10-15

### 中文

- iOS：适配了液态玻璃
- iOS：增加了 PRiSM Link 功能和对应 App Clip，以供音游窝集成功能，使用 iPhone 扫描对应二维码或 NFC 标签时会展示漂亮的卡片以及可以拉起无需安装的 App Clip
- 欢迎使用免费开源的音游窝管理系统 PRiSM（<https://link.neri.moe>）

### English

- iOS: Liquid Glass design
- iOS: added PRiSM Link and its App Clip for arcade venue integration: scanning the venue's QR code or NFC tag with an iPhone shows a pretty card and can open the App Clip without installing anything
- Come try PRiSM, the free and open source arcade venue management system (<https://link.neri.moe>)

## 2.4.1 - 2026-08-12

### 中文

- 优化了扫描流程，现在 HINATA Lite 不需要贴铜箔也可以稳定读取兼容卡和交通联合等卡片
- 适配了 HINATA IO 的端到端加密功能

### English

- Improved scanning, so HINATA Lite now reads compatible cards, China T-Union cards and the like reliably without the copper foil
- Works with HINATA IO's end-to-end encryption

## 2.4.0 - 2026-08-06

### 中文

- 优化了扫描流程，现在 HINATA Lite 不需要贴铜箔也可以稳定读取兼容卡和交通联合等卡片
- 适配了 HINATA IO 的端到端加密功能

### English

- Improved scanning, so HINATA Lite now reads compatible cards, China T-Union cards and the like reliably without the copper foil
- Works with HINATA IO's end-to-end encryption

## 2.3.2 - 2026-06-16

### 中文

- iOS：修复了部分情况下读取后不显示的问题
- iOS：增加了启动画面

### English

- iOS: fixed results sometimes not showing after a read
- iOS: added a launch screen

## 2.3.1 - 2026-06-02

### 中文

- 大幅优化了使用读卡器扫描 iPhone 的 Suica 时的效果
- 提升了在扫描 Suica 时读取交易记录的稳定性

### English

- Much better at reading Suica on iPhone through the reader
- More reliable at reading Suica history

## 2.3.0 - 2026-06-01

### 中文

- 支持读取中国的交通联合卡片和日本的交通系卡片的内容，可以显示余额和交易记录
- 修复了安卓手机 NFC 在读取 iPhone 的 Suica 时会读不到卡的问题
- 一些 UI 优化

### English

- Reads China T-Union cards and Japanese transit cards, showing their balance and history
- Fixed Android phones' NFC not picking up Suica on iPhone
- Some UI improvements

## 2.1.0 - 2026-04-10

### 中文

- HINATA Go 网页版上线（<https://go.neri.moe>），后续将会用于替代 HINATA 控制中心
- 优化了一些布局和修复了 bug
- 支援了 epass 和 banapass 解密显示

### English

- HINATA Go for the web is live (<https://go.neri.moe>), and will replace HINATA Control Center
- Some layout improvements and bug fixes
- Decrypts and shows e-amusement pass and Banapass cards

## 2.0.0 - 2026-04-09

### 中文

本次更新着重于重新思考整个应用的用途，把 HINATA 控制中心的功能给合并进来，并重新设计了主页 UI

- 现在你可以在安卓设备上连接 HINATA 读卡器了，在手机上就可以轻易修改设备的设置以及为设备更新固件，或者使用设备来读取卡片
- 将读卡模式分为了信息查看模式和发送卡号模式，前者可以很方便的查看一张卡的信息，后者则是向远程设备发送卡号登录
- 移除了二维码扫描器
- 优化了横屏和大屏布局，并同时支持 Web 版本，后续会逐步替代掉 HINATA 控制中心（cc.neri.moe）

### English

This update rethinks what the whole app is for: HINATA Control Center's features are merged in, and the home screen UI is redesigned

- You can now connect a HINATA reader to an Android device, and easily change its settings, update its firmware, or read cards with it right from your phone
- Reading is split into an info mode and a send mode: the first makes it easy to look at a card's details, the second sends the card number to a remote device to log in
- Removed the QR code scanner
- Better landscape and large-screen layouts, plus a web version that will gradually replace HINATA Control Center (cc.neri.moe)

## 1.7.0 - 2026-03-24

### 中文

- 增添了数据导入导出功能

### English

- Added data import and export

## 1.6.0 - 2026-03-13

### 中文

- 新增 spicetools 支持，Konami 游戏也可以轻松使用
- 增加了国际化支持，现在有 English 和简体中文两种语言

### English

- Added spicetools support, so Konami games are easy to use too
- Added localization, now in English and Simplified Chinese

## 1.5.0 - 2026-03-09

### 中文

- 让你的手机与 HINATA AimeIO 协同使用，使用手机 NFC 或 QR 扫码登录游戏
- 上线 iOS 版（TestFlight），感谢 滑稽 的大力支持

### English

- Use your phone together with HINATA AimeIO, and log in to games with your phone's NFC or a QR code
- The iOS version is out on TestFlight, with big thanks to 滑稽 for the support

## 1.4.0 - 2026-03-09

### 中文

- 修复了很多 bug
- 已严肃开源：<https://github.com/Project-HINATA/hinata_go>

### English

- Fixed lots of bugs
- Now seriously open source: <https://github.com/Project-HINATA/hinata_go>

## 1.1.0 - 2026-03-08

### 中文

- 可能修复了一些 bug
- 增加了一个卡片信息的页面
- 为 apk 增加了签名，需要卸载掉旧版才能安装

### English

- Probably fixed some bugs
- Added a card info page
- The apk is now signed, so uninstall the old version before installing

## 1.0.0 - 2026-03-05

### 中文

- 支援 NFC 刷卡传入游戏
- 支援二维码扫描卡号传入游戏
- 被保存的卡片可以无需介质直接传入游戏
- 完善的卡片管理，可以保存卡片到卡包
- 与 HINATA IO 深度融合，实现手机与读卡器协同使用
- 非常正确的卡片读取流程
- 完整支持所有 Material Design 3 特性，现代化的 UI

### English

- Tap a card on NFC to send it into the game
- Scan a card number QR code to send it into the game
- Saved cards go straight into the game, no physical card needed
- Proper card management, with a wallet to keep your cards in
- Deep integration with HINATA IO, so your phone and the reader work together
- A very correct card reading flow
- Full support for every Material Design 3 feature, with a modern UI
