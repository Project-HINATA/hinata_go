import 'package:flutter/material.dart';

class IconUtils {
  static IconData getIconData(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'cloud':
        return Icons.cloud;
      case 'computer':
        return Icons.computer;
      case 'api':
        return Icons.api;
      case 'webhook':
        return Icons.webhook;
      default:
        return Icons.dns;
    }
  }
}
