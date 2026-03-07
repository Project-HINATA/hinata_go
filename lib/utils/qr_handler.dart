class QrHandler {
  /// 检查二维码内容是否是不以3开头的20位纯数字
  static bool isValidQrData(String qrData) {
    if (qrData.length != 20) return false;
    if (qrData.startsWith('3')) return false;
    return RegExp(r'^\d+$').hasMatch(qrData);
  }
}
