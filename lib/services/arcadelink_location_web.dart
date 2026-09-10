import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'arcadelink_location_stub.dart';

export 'arcadelink_location_stub.dart'
    show ArcadeLinkLocationException, ArcadeLinkLocationSample;

Future<ArcadeLinkLocationSample> currentArcadeLinkLocation() {
  final completer = Completer<ArcadeLinkLocationSample>();
  final geolocation = window.navigator.geolocation;

  geolocation.getCurrentPosition(
    ((GeolocationPosition position) {
      if (completer.isCompleted) return;
      final coordinates = position.coords;
      completer.complete(
        ArcadeLinkLocationSample(
          latitude: coordinates.latitude,
          longitude: coordinates.longitude,
          accuracy: coordinates.accuracy,
        ),
      );
    }).toJS,
    ((GeolocationPositionError error) {
      if (completer.isCompleted) return;
      completer.completeError(ArcadeLinkLocationException(_messageFor(error)));
    }).toJS,
    PositionOptions(enableHighAccuracy: true, timeout: 10000, maximumAge: 0),
  );

  return completer.future;
}

String _messageFor(GeolocationPositionError error) {
  switch (error.code) {
    case GeolocationPositionError.PERMISSION_DENIED:
      return 'location_denied';
    case GeolocationPositionError.TIMEOUT:
      return 'location_timeout';
    default:
      return 'location_unavailable';
  }
}
