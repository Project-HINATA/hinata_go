import 'package:flutter/material.dart';

enum WindowSize { compact, medium, expanded }

extension ContextWindowSize on BuildContext {
  WindowSize get windowSize => getWindowSize(this);
}

WindowSize getWindowSize(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;

  if (width < 600) return WindowSize.compact;
  if (width < 840) return WindowSize.medium;
  return WindowSize.expanded;
}

extension WindowSizeExtension on WindowSize {
  bool get isCompact => this == WindowSize.compact;
  bool get isMedium => this == WindowSize.medium;
  bool get isExpanded => this == WindowSize.expanded;

  double get padding {
    switch (this) {
      case WindowSize.compact:
        return 8;
      case WindowSize.medium:
        return 16;
      case WindowSize.expanded:
        return 32;
    }
  }
}
