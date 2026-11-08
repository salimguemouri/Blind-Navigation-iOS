//
//  LiveLocation.swift
//  BlindNavigation
//
//  Created by Salim Guemouri on 21/12/2025.
//

import Foundation
import CoreLocation
import Combine

final class LiveLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var statusText: String = "Idle"
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var accuracy: Double?
    @Published var currentLocation: CLLocation?

    private let manager = CLLocationManager()
    override init() {
        super.init()
        // Connect CLLocationManager to this class so location updates can be received
        manager.delegate = self
        // Request the best available location accuracy for navigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Update the location when the user moves by around 1 metre
        manager.distanceFilter = 1
    }
    func requestPermissionAndStart() {
        statusText = "Requesting location permission..."
        // Ask the user for permission to use location while the app is open
        manager.requestWhenInUseAuthorization()
        // Start receiving live GPS/location updates
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            statusText = "Receiving location ✅"
            manager.startUpdatingLocation()
        case .denied, .restricted:
            statusText = "Location denied ❌"
        case .notDetermined:
            statusText = "Waiting for permission…"
        @unknown default:
            statusText = "Unknown auth state"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        accuracy = loc.horizontalAccuracy
        statusText = "Receiving location ✅"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "Location error: \(error.localizedDescription)"
    }
}


