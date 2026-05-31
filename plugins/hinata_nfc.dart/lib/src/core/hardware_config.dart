enum ConfigIndex {
  segaBrightness(0),
  config0(1),
  config1(2),
  idleR(3),
  idleG(4),
  idleB(5),
  busyR(6),
  busyG(7),
  busyB(8);

  final int value;
  const ConfigIndex(this.value);
  int toInt() => value;
}

class Config0 {
  bool isFirstLaunch = false;
  bool cardioDisableIso14443a = false;
  bool cardioIso14443aStartWithE004 = false;
  bool enableLedRainbow = true;
  bool serialDescriptorUnique = false;
  bool segaHwFw = false;
  bool segaFastRead = false;
  bool isNotFirstLaunch = true;

  int asByte() {
    int value = 0;
    value |= (isFirstLaunch ? 1 : 0) << 0;
    value |= (cardioDisableIso14443a ? 1 : 0) << 1;
    value |= (cardioIso14443aStartWithE004 ? 1 : 0) << 2;
    value |= (enableLedRainbow ? 1 : 0) << 3;
    value |= (serialDescriptorUnique ? 1 : 0) << 4;
    value |= (segaHwFw ? 1 : 0) << 5;
    value |= (segaFastRead ? 1 : 0) << 6;
    value |= (isNotFirstLaunch ? 1 : 0) << 7;
    return value;
  }

  static Config0 fromByte(int byte) {
    var c = Config0();
    c.isFirstLaunch = (byte & (1 << 0)) != 0;
    c.cardioDisableIso14443a = (byte & (1 << 1)) != 0;
    c.cardioIso14443aStartWithE004 = (byte & (1 << 2)) != 0;
    c.enableLedRainbow = (byte & (1 << 3)) != 0;
    c.serialDescriptorUnique = (byte & (1 << 4)) != 0;
    c.segaHwFw = (byte & (1 << 5)) != 0;
    c.segaFastRead = (byte & (1 << 6)) != 0;
    c.isNotFirstLaunch = (byte & (1 << 7)) != 0;
    return c;
  }
}
