//
//  LocationManager.swift
//  PlaceFinder
//
//  Created on 18.07.26.
//

import Foundation
import CoreLocation
import Combine

enum TransitType: String, CaseIterable {
    case walking = "A piedi"
    case driving = "In macchina"

    var radiusInMeters: Int {
        switch self {
        case .walking:
            return 1500
        case .driving:
            return 15000
        }
    }
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published var currentLatitude: Double?
    @Published var currentLongitude: Double?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?

    private var continuation: CheckedContinuation<(Double, Double), Error>?
    private var lastFixTimestamp: Date?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Returns (latitude, longitude) async, requesting permission and location if needed.
    func fetchCurrentCoordinates() async throws -> (Double, Double) {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            requestPermission()
            // Wait briefly for authorization to propagate
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return try await fetchCurrentCoordinates()
        case .restricted, .denied:
            throw LocationError.permissionDenied
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            throw LocationError.unknown
        }

        // If we have a fix fresher than 60s, return cached coordinates immediately
        if let lat = currentLatitude, let lon = currentLongitude,
           let ts = lastFixTimestamp, Date().timeIntervalSince(ts) < 60 {
            return (lat, lon)
        }

        // Cached data is stale or absent: request a fresh single-shot location
        do {
            let result = try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                manager.requestLocation()
            }
            return result
        } catch {
            // GPS failed but we have old coordinates (even if stale): return them as fallback
            if let lat = currentLatitude, let lon = currentLongitude {
                return (lat, lon)
            }
            throw error
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLatitude = location.coordinate.latitude
        currentLongitude = location.coordinate.longitude
        lastFixTimestamp = Date()
        locationError = nil

        if let continuation = continuation {
            self.continuation = nil
            continuation.resume(returning: (location.coordinate.latitude, location.coordinate.longitude))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error.localizedDescription
        if let continuation = continuation {
            self.continuation = nil
            continuation.resume(throwing: error)
        }
    }
}

enum LocationError: LocalizedError {
    case permissionDenied
    case unknown

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accesso alla posizione negato. Abilitalo nelle Impostazioni."
        case .unknown:
            return "Errore sconosciuto nel recupero della posizione."
        }
    }
}