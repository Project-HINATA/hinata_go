import 'dart:math';

double mapWithGamma(int value, double gamma) {
  double v = value / 255.0;
  return pow(v, 1.0 / gamma).toDouble();
}

int unmapWithGamma(double value, double gamma) {
  return (pow(value, gamma) * 255).round();
}
