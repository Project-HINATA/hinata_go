# HINATA Go

[![Flutter](https://img.shields.io/badge/Flutter-3.11+-02569B?logo=flutter&style=flat-square)](https://flutter.dev)
[![Material 3](https://img.shields.io/badge/Material_3-Yes-757575?logo=materialdesign&style=flat-square)](https://m3.material.io)

HINATA Go is a multi-platform NFC card tool that supports card information viewing (Normal Mode) and game card reader capability (Sender Mode), working seamlessly with external HINATA card readers.

## Downloads & Access

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

## Core Modes & Features

### 1. Card Information Viewer (Normal Mode)
Scan cards using the device's built-in NFC or a connected external HINATA reader to view detailed card data and save cards to the local card folder.

* **Transit Cards**
  * **Japanese Transit Cards (Suica, PASMO, etc.)**: View card balances, up to 20 recent transaction records (including transaction type, date, amount, and boarding/alighting station names resolved using the built-in database).
  * **China T-Union (交通联合)**: View card numbers, balances, and up to 10 recent transaction records.
* **Arcade/Amusement Cards**
  * **Amusement IC**: Identify card manufacturers, display Access Codes, and view in-game legitimacy status.
  * **Other Game Cards (Aime, Bana Passport, E-Amusement Pass, FeliCa, ISO15693)**: Read basic card details, Access Codes, and validation data.

### 2. Card Reader Mode (Sender Mode)
Select an active game instance, and scan cards via device NFC, QR code scan, or a connected external HINATA reader to automatically send the card number to the target game for login.

* **Instance Management**: Add and save multiple remote instances (HINATA AimeIO) or local instances (SpiceAPI).
* **Automatic Forwarding**: In Sender Mode, swiped card numbers are sent immediately to the selected active instance without manual interaction.

---

## Connection Guide

### HINATA AimeIO (Segatools)
> **The following configuration uses the HINATA public card reader server ( `aime-ws.neri.moe` ) as an example. Please ensure your network environment can access Cloudflare services.**

1. Deploy [HINATA AimeIO](https://hinata.neri.moe/game-setting/sega/hinata-client/) to your game, and configure the remote card server in `segatools.ini` (or use the HINATA Client tool):
    ```ini
    [aime]
    enable=1

    [aimeio]
    path=hinata.dll
    serverUrl=wss://aime-ws.neri.moe/REPLACEME
    ```
    ![alt text](readme_assets/image.png)
    *Replace `REPLACEME` with your custom, unique string.*

2. Open HINATA Go.
3. Add an Instance, customize the name, and configure the URL as `https://aime-ws.neri.moe/REPLACEME`.
   ![alt text](readme_assets/image-1.png)
4. Switch HINATA Go to **Sender Mode**, select the instance, and start the game to swipe and log in.

### SpiceAPI (KONAMI Games)
> **Limited to local area network (LAN) usage, or use tools like Cloudflare Tunnel to handle public forwarding.**

1. Open `spicecfg.exe`.
2. Configure the SpiceAPI port and leave the password blank.
3. Add an Instance in HINATA Go, and set the URL to `your_pc_lan_ip:spice_listening_port` (e.g., `192.168.0.114:1145`, do not include the `http://` prefix).
4. Switch HINATA Go to **Sender Mode**, select the instance, and start the game.

---

## Hardware Reader Management
* Connect physical HINATA card readers via USB-OTG.
* Configure hardware settings (such as LED brightness, working mode restrictions) and perform OTA firmware updates directly inside the app.

## Other Highlights
* **QR Code Login**: Scan card QR/barcodes via the device camera and send card numbers directly to games.
* **System Integration**: On Android, support `USB_DEVICE_ATTACHED` broadcasts to automatically prompt to launch the app when a reader is plugged in; support launching and sending card numbers via system Intents.
* **Interface & Layout**: Follow Material Design 3 guidelines with Dynamic Color support; support responsive split-column layouts on landscape and tablet screens.

## Community Group
[QQ 1085979135](https://qun.qq.com/universal-share/share?ac=1&authKey=YzIhakJWJ7BmvG%2F1JJLr27LFwpC050aWFeatFIjOhQM0i5RgEOVVZHuDop7nvlV%2F&busi_data=eyJncm91cENvZGUiOiIxMDg1OTc5MTM1IiwidG9rZW4iOiJHOHEwYmlqYWNyakJaeDlGQ1B2Mm5TUUNCUTZESUo2cGtpWUZwZEkrSVAyOTJwUmNsWWFnckd5NmdvMDJhMWtGIiwidWluIjoiMTAxNTkyOTQ1MiJ9&data=Dp-q7I-pDdniotBs8a4b6u7WM2CuxwRxphBKcVkxtF_IB8A1xp4oKNytX9NglpUJcpD0wc2hjgP4dIF4-7xpkw&svctype=4&tempid=h5_group_info)
