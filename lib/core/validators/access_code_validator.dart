class AccessCodeValidator {
  static const int accessCodeLength = 20;
  static const String banapassPrefix = '3';
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  const AccessCodeValidator._();

  static bool isTwentyDigitAccessCode(String? accessCode) {
    return accessCode != null &&
        accessCode.length == accessCodeLength &&
        _digitsOnly.hasMatch(accessCode);
  }

  static bool startsWithBanapassPrefix(String? accessCode) {
    return accessCode != null && accessCode.startsWith(banapassPrefix);
  }

  static bool isValidAimeAccessCode(String? accessCode) {
    return isTwentyDigitAccessCode(accessCode) &&
        !startsWithBanapassPrefix(accessCode);
  }

  static bool isValidDecodedBanapassAccessCode(String? accessCode) {
    return isTwentyDigitAccessCode(accessCode) &&
        startsWithBanapassPrefix(accessCode);
  }
}
