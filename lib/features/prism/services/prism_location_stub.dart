class PrismLocationSample {
  const PrismLocationSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}

class PrismLocationException implements Exception {
  const PrismLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<PrismLocationSample> currentPrismLocation() {
  throw const PrismLocationException('location_unavailable');
}
