import 'package:flutter/material.dart';

class Destination {
  final Widget? icon;
  final Widget? reversedIcon;
  final String label;

  Destination(this.label, {this.icon, this.reversedIcon});

  Widget? getIcon(bool isSelected) {
    if (!isSelected) {
      return reversedIcon;
    } else {
      return icon;
    }
  }
}
