# HINATA Go
While connecting via HINATA AimeIO, turns your mobile phone into a card reader or QR code scanner for arcade games, and can be used with various other devices.

## Downloads

| iOS | Android |
| --- | ------- |
| [![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/app/id6760301105) | [**APK Download**](https://github.com/nerimoe/hinata_go/releases) |

## Features

* Read card information
* Connect to arcade games as a card reader
* Configure & update HINATA Card Reader

## Read Card Information

Place the card in the mobile device's NFC recognition area to read its information.

You may use your mobile device's USB-OTG port to connect the **HINATA Card Reader** as an external card reader now.

### Supported Card Types

* **Amusement IC**
* **Legacy Aime**
* **Bana Passport**
* **E-Amusement Pass**
* **FeliCa**

## Connect to Games as a Card Reader

### Segatools
> **The following configuration uses the HINATA public card reader server ( `aime-ws.neri.moe` ) as an example. Please ensure your network environment can access Cloudflare services.**
1. First, deploy [HINATA AimeIO](https://hinata.neri.moe/game-setting/sega/hinata-client/) to your game. Then configure the remote card server. You can edit the `segatools.ini` directly or use the HINATA Client
    ```ini
    [aime]
    enable=1

    [aimeio]
    path=hinata.dll
    serverUrl=wss://aime-ws.neri.moe/REPLACEME
    ```
    ![alt text](readme_assets/image.png)

    **Replace `REPLACEME` with your custom serial string, and make sure it's unique enough to avoid conflicts with others.**
2. Download the latest version of HINATA Go from [Downloads](#downloads), install, and open it.
3. Add an Instance in the app, customize the name, and configure the URL as `https://aime-ws.neri.moe/REPLACEME`, as shown below ![alt text](readme_assets/image-1.png)

4. Run the game and start your experience.

### SpiceAPI
> **⚠️ Since there is currently no forwarding server set up for SpiceAPI, it can only be used on a local network. Well, you can also use cloudflared for forwarding yourself.**
1. Run `spicecfg.exe`.
2. Find the SpiceAPI configuration, set the port, and leave the password blank.
3. Add an Instance in HINATA Go, configure the URL as `<Your_IP_Address>:<Spice_Listening_Port>`, e.g. `192.168.0.114:1145`. No need to add `http://` from the begin.

## HINATA Card Reader Configuration & Firmware Update 

Connect the HINATA Card Reader via the mobile device's USB-OTG port.

Once the device is connected at the bottom of HINATA Go, you can proceed with **Configuration** and **Firmware Updates**.


## Special Features

* Relies on a public card server, allowing the phone and arcade machine to function normally in different network environments.
* Card IDs can be acquired via QR code and sent to the game.
* Full support for Amusement IC cards.
* Thanks to HINATA AimeIO, HINATA Go can also read old Banapass cards normally, provided you use supported segatools.
* Also thanks to HINATA AimeIO, it can co-exist with enter-key card swiping, physical card readers, and various other card swiping schemes like hand controllers, amnet, mageki, etc., via the dllMux feature.
* You can launch the app to swipe cards via Android system Intents, quickly sending the card ID to the target instance.
* Complete Material Design 3 UI and icons.


## Community Group
[QQ 1085979135](https://qun.qq.com/universal-share/share?ac=1&authKey=YzIhakJWJ7BmvG%2F1JJLr27LFwpC050aWFeatFIjOhQM0i5RgEOVVZHuDop7nvlV%2F&busi_data=eyJncm91cENvZGUiOiIxMDg1OTc5MTM1IiwidG9rZW4iOiJHOHEwYmlqYWNyakJaeDlGQ1B2Mm5TUUNCUTZESUo2cGtpWUZwZEkrSVAyOTJwUmNsWWFnckd5NmdvMDJhMWtGIiwidWluIjoiMTAxNTkyOTQ1MiJ9&data=Dp-q7I-pDdniotBs8a4b6u7WM2CuxwRxphBKcVkxtF_IB8A1xp4oKNytX9NglpUJcpD0wc2hjgP4dIF4-7xpkw&svctype=4&tempid=h5_group_info)
