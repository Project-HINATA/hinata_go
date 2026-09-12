import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'package:hinata_go/features/prism/services/prism_location_stub.dart';

export 'package:hinata_go/features/prism/services/prism_location_stub.dart'
    show PrismLocationException, PrismLocationSample;

Future<PrismLocationSample> currentPrismLocation() {
  final completer = Completer<PrismLocationSample>();
  final geolocation = window.navigator.geolocation;

  geolocation.getCurrentPosition(
    ((GeolocationPosition position) {
      if (completer.isCompleted) return;
      final coordinates = position.coords;
      completer.complete(
        PrismLocationSample(
          latitude: coordinates.latitude,
          longitude: coordinates.longitude,
          accuracy: coordinates.accuracy,
        ),
      );
    }).toJS,
    ((GeolocationPositionError error) {
      if (completer.isCompleted) return;
      completer.completeError(PrismLocationException(_messageFor(error)));
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
