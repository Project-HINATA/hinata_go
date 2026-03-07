class Validators {
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }
}
