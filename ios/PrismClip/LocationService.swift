@preconcurrency import CoreLocation
import Foundation

struct LocationSample {
  let latitude: Double
  let longitude: Double
  let accuracy: Double
}

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var timeout: Task<Void, Never>?
  private var continuation: CheckedContinuation<LocationSample, Error>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
  }

  func currentLocation() async throws -> LocationSample {
    guard continuation == nil, CLLocationManager.locationServicesEnabled() else {
      throw LocationError.unavailable
    }

    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      return try await requestLocation()
    case .notDetermined:
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        manager.requestWhenInUseAuthorization()
      }
    case .denied, .restricted:
      throw LocationError.denied
    @unknown default:
      throw LocationError.unavailable
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let continuation else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      self.continuation = continuation
      beginLocationRequest()
    case .denied, .restricted:
      self.continuation = nil
      continuation.resume(throwing: LocationError.denied)
    default:
      break
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) <= 15, let continuation else { return }
    self.continuation = nil
    timeout?.cancel()
    continuation.resume(returning: LocationSample(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      accuracy: max(location.horizontalAccuracy, 0),
    ))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard let continuation else { return }
    self.continuation = nil
    timeout?.cancel()
    continuation.resume(throwing: error)
  }

  private func beginLocationRequest() {
    timeout?.cancel()
    timeout = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
      guard let self, let pending = self.continuation else { return }
      self.continuation = nil
      pending.resume(throwing: LocationError.unavailable)
    }
    manager.requestLocation()
  }

  private func requestLocation() async throws -> LocationSample {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      beginLocationRequest()
    }
  }
}

enum LocationError: LocalizedError {
  case denied
  case unavailable

  var errorDescription: String? {
    switch self {
    case .denied:
      return String(localized: "需要定位权限才能确认你在店内")
    case .unavailable:
      return String(localized: "定位获取失败")
    }
  }
}
