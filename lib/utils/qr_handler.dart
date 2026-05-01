import 'access_code_validator.dart';

class QrHandler {
  /// 检查二维码内容是否是不以3开头的20位纯数字
  static bool isValidQrData(String qrData) {
    return AccessCodeValidator.isValidAimeAccessCode(qrData);
  }
}
