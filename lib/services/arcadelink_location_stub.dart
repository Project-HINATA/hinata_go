class ArcadeLinkLocationSample {
  const ArcadeLinkLocationSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}

class ArcadeLinkLocationException implements Exception {
  const ArcadeLinkLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<ArcadeLinkLocationSample> currentArcadeLinkLocation() {
  throw const ArcadeLinkLocationException('location_unavailable');
}
