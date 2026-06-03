### [English Guide](README_en.md)

# HINATA Go

[![Flutter](https://img.shields.io/badge/Flutter-3.11+-02569B?logo=flutter&style=flat-square)](https://flutter.dev)
[![Material 3](https://img.shields.io/badge/Material_3-Yes-757575?logo=materialdesign&style=flat-square)](https://m3.material.io)

HINATA Go 是一款多平台 NFC 卡片工具，支持卡片信息查看与读卡器模拟，并可与外接 HINATA 读卡器协同工作。

## 下载与访问

<p align="left">
  <a href="https://apps.apple.com/app/id6760301105" target="_blank" rel="noopener noreferrer">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="40" />
  </a>
  <a href="https://github.com/nerimoe/hinata_go/releases" target="_blank" rel="noopener noreferrer">
    <img src="readme_assets/download-on-android.svg" alt="Download APK for Android" height="40" />
  </a>
  <a href="https://go.neri.moe" target="_blank" rel="noopener noreferrer">
    <img src="readme_assets/open-on-web.svg" alt="Launch App on Web Browser" height="40" />
  </a>
</p>

## 核心模式与功能

### 1. 卡片信息查看
使用设备内置 NFC 或连接外接 HINATA 读卡器扫描卡片，在应用内展示卡片详细数据，并可保存至本地卡包中。

* **交通卡**
  * **日本交通系卡片 (Suica, PASMO 等)**：查看卡片余额、最近 20 条交易记录（包括交易类型、日期、金额、以及基于内置数据库解析的乘降车站名称）。
  * **交通联合 (China T-Union)**：查看卡号、余额及最近 10 条刷卡记录。
* **街机游戏卡**
  * **Amusement IC**：Access Code, Konami游戏内卡号，生产厂商等
  * **旧式 Aime 或兼容卡**：Access Code, 游戏内合法性等
  * **旧式 Banapass 或兼容卡**：Access Code
  * **旧式 E-Amusement Pass**： Konami游戏内卡号
* **其他卡片**
  * **任意 Felica 卡片**：IDm, PMm, SystemCodes, Konami游戏内卡号 等
  * **任意 ISO15693 卡片**：Konami游戏内卡号

### 2. 读卡器模式
选择活跃的游戏实例后，通过设备 NFC、扫码或外接 HINATA 读卡器刷卡，应用会自动将卡号发送至目标游戏以实现登录。

* **实例管理**：支持添加并保存多个 `HINATA AimeIO` 或 `SpiceAPI` 实例 / 机器。
* **自动发送**：在 Sender 模式下，刷卡后无需手动操作，卡号会实时传输至当前选中的活跃实例。

---

## 读卡器模式连接指南

### HINATA AimeIO (Segatools)
> **以下配置以 HINATA 公共刷卡服务器 ( `aime-ws.neri.moe` ) 为例，请确保网络环境可以正常访问 Cloudflare 服务**

1. 在游戏端部署 [HINATA AimeIO](https://hinata.neri.moe/game-setting/sega/hinata-client/)，并在 `segatools.ini` 中配置远程刷卡服务器（或使用 HINATA Client 工具进行配置）：
    ```ini
    [aime]
    enable=1

    [aimeio]
    path=hinata.dll
    serverUrl=wss://aime-ws.neri.moe/REPLACEME
    ```
    ![alt text](readme_assets/image.png)
    *请将 `REPLACEME` 替换为自定义的唯一英文字符串。*

2. 打开 HINATA Go。
3. 添加一个 Instance，名称自定义，URL 配置为 `https://aime-ws.neri.moe/REPLACEME`。
   ![alt text](readme_assets/image-1.png)
4. 将 HINATA Go 切换为 **Sender 模式**，选择添加的实例，运行游戏即可刷卡登录。

### SpiceAPI (KONAMI 游戏)
> **仅限局域网使用，或使用 Cloudflare Tunnel 等工具自行进行公网转发**

1. 打开 `spicecfg.exe`。
2. 配置 SpiceAPI 端口，将密码留空。
3. 在 HINATA Go 内添加一个 Instance，URL 配置为 `电脑局域网IP:Spice监听端口`（例如 `192.168.0.114:1145`，无需携带 `http://` 协议头）。
4. 将 HINATA Go 切换为 **Sender 模式**，选择该实例后运行游戏。

---

## 外接硬件管理
* 支持通过 USB-OTG 连接实体 HINATA 读卡器。
* 可直接在应用内修改硬件设置（如 LED 亮度、工作模式等）并进行固件 OTA 更新。

## 其他特色
* **系统集成**：Android 平台支持 `USB_DEVICE_ATTACHED` 广播，插入外接读卡器时可自动提示启动程序；支持通过 Android 系统 Intent 扫卡直接启动应用并发送。
* **界面与布局**：采用 Material Design 3 规范与动态配色 (Dynamic Color)；支持响应式分栏布局，在横屏或平板设备上自动展示双栏界面。

## 交流群
[QQ 1085979135](https://qun.qq.com/universal-share/share?ac=1&authKey=YzIhakJWJ7BmvG%2F1JJLr27LFwpC050aWFeatFIjOhQM0i5RgEOVVZHuDop7nvlV%2F&busi_data=eyJncm91cENvZGUiOiIxMDg1OTc5MTM1IiwidG9rZW4iOiJHOHEwYmlqYWNyakJaeDlGQ1B2Mm5TUUNCUTZESUo2cGtpWUZwZEkrSVAyOTJwUmNsWWFnckd5NmdvMDJhMWtGIiwidWluIjoiMTAxNTkyOTQ1MiJ9&data=Dp-q7I-pDdniotBs8a4b6u7WM2CuxwRxphBKcVkxtF_IB8A1xp4oKNytX9NglpUJcpD0wc2hjgP4dIF4-7xpkw&svctype=4&tempid=h5_group_info)
