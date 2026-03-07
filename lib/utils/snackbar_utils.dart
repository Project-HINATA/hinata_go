import 'package:flutter/material.dart';

const Duration kSnackBarDuration = Duration(milliseconds: 500);

extension QuickSnackBar on ScaffoldMessengerState {
  /// Clears any existing SnackBar and immediately shows a new one
  /// with a short duration (0.5 s).
  void showQuickSnackBar(SnackBar snackBar) {
    clearSnackBars();
    showSnackBar(
      SnackBar(
        content: snackBar.content,
        duration: kSnackBarDuration,
        action: snackBar.action,
        behavior: snackBar.behavior,
      ),
    );
  }
}
