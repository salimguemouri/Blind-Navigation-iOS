//
//  ContentView.swift
//  BlindNavigation
//
//  Created by Salim Guemouri on 21/12/2025.
//

import SwiftUI
import AVFoundation
import MapKit
import CoreLocation

// MARK: - Route Step Model
struct RouteStepItem: Identifiable, Hashable {
    let id = UUID()
    let index: Int
    let instruction: String
    let stepDistanceMeters: Double
    let endCoordinate: CLLocationCoordinate2D?

    static func == (lhs: RouteStepItem, rhs: RouteStepItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ContentView: View {
    @StateObject private var liveLocation = LiveLocation()
    @StateObject private var speech = SpeechDestination()

    private let speaker = AVSpeechSynthesizer()

    @State private var destinationText: String = ""
    @State private var routingStatus: String = ""

    // Route + Guidance state
    @State private var steps: [RouteStepItem] = []
    @State private var currentStepIndex: Int = 0
    @State private var liveRemainingMeters: Double? = nil
    @State private var guidanceActive: Bool = false
    @State private var lastSpokenRemainingBucket: Int? = nil

    // Timer for live updates
    @State private var timer: Timer?

    // Hazard scan sheet
    @State private var showHazardScan: Bool = false

    // Route map sheet
    @State private var showRouteMap: Bool = false
    @State private var calculatedRoute: MKRoute? = nil
    @State private var destinationMapItem: MKMapItem? = nil
    @State private var selectedDestinationName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Blind Navigation")
                .font(.title)
                .bold()
                .accessibilityAddTraits(.isHeader)

            // Start location tracking
            Button("Start Navigation") {
                speak("Navigation started. Location is being tracked.")
                liveLocation.requestPermissionAndStart()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Starts location tracking for navigation")

            // Set destination by voice
            Button(speech.isListening ? "Stop Listening" : "Set Destination (Voice)") {
                if speech.isListening {
                    speech.stopListening()
                } else {
                    // Stop TTS so it doesn't get recorded by mic
                    speaker.stopSpeaking(at: .immediate)

                    speech.requestPermissions { ok in
                        if ok {
                            speech.startListening { finalText in
                                let cleaned = extractDestination(from: finalText)
                                destinationText = cleaned

                                if cleaned.isEmpty {
                                    speak("I did not catch the destination. Please try again.")
                                } else {
                                    speak("Destination set to \(cleaned). Tap start route.")
                                }
                            }
                        } else {
                            speak("Speech permission not granted.")
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Set destination by voice")
            .accessibilityHint("Double tap then speak a destination, like a postcode or place name")

            Text("Heard: \(speech.transcript.isEmpty ? "—" : speech.transcript)")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityLabel("Heard destination")
                .accessibilityValue(speech.transcript.isEmpty ? "None" : speech.transcript)

            // Start route
            Button("Start Route") {
                let cleaned = extractDestination(from: speech.transcript)
                if !cleaned.isEmpty {
                    destinationText = cleaned
                }
                startRoute(to: destinationText)
            }
            .buttonStyle(.borderedProminent)
            .disabled(destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityHint("Calculates the walking route to the destination")

            // Show live route map
            Button("Show Route Map") {
                showRouteMap = true
            }
            .buttonStyle(.bordered)
            .disabled(calculatedRoute == nil || destinationMapItem == nil)
            .accessibilityHint("Opens a map showing your current location, destination, and walking route.")
            .sheet(isPresented: $showRouteMap) {
                if let route = calculatedRoute,
                   let destination = destinationMapItem {
                    NavigationMapView(
                        route: route,
                        userCoordinate: liveLocation.currentLocation?.coordinate,
                        destinationCoordinate: destination.placemark.coordinate,
                        destinationName: selectedDestinationName.isEmpty ? "Destination" : selectedDestinationName
                    )
                } else {
                    Text("No route available yet.")
                        .padding()
                }
            }

            // Guidance
            Button(guidanceActive ? "Guidance (Listening…)" : "Guidance") {
                toggleGuidance()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Starts guidance mode. Then say next step, previous, repeat, or stop guidance.")

            // Hazard scan
            Button("Hazard Scan (Camera)") {
                showHazardScan = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens the camera to detect hazards like cars or obstacles.")
            .sheet(isPresented: $showHazardScan) {
                HazardScannerView()
            }

            // Current step + live distance
            if !steps.isEmpty {
                VStack(spacing: 6) {
                    Text("Step \(min(currentStepIndex + 1, steps.count)) of \(steps.count)")
                        .font(.headline)

                    if let remaining = liveRemainingMeters {
                        Text("Remaining to this step: \(formatMeters(remaining))")
                            .font(.subheadline)
                            .accessibilityLabel("Distance remaining")
                            .accessibilityValue(formatMeters(remaining))
                    }

                    Text(steps[safe: currentStepIndex]?.instruction ?? "")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityLabel("Current instruction")
                        .accessibilityValue(steps[safe: currentStepIndex]?.instruction ?? "")
                }
                .padding(.top, 8)
            }

            // Debug info
            VStack(alignment: .leading, spacing: 6) {
                Text("Location: \(liveLocation.statusText)")

                if let lat = liveLocation.latitude,
                   let lon = liveLocation.longitude {
                    Text(String(format: "Lat: %.6f", lat))
                    Text(String(format: "Lon: %.6f", lon))
                }

                if let acc = liveLocation.accuracy {
                    Text(String(format: "Accuracy: %.1f m", acc))
                }

                if !routingStatus.isEmpty {
                    Text("Routing: \(routingStatus)")
                }

                if let route = calculatedRoute {
                    Text("Route distance: \(formatMeters(route.distance))")
                }
            }
            .font(.system(.footnote, design: .monospaced))
            .padding(.top, 8)

            // Full list for visual debugging
            if !steps.isEmpty {
                List(steps) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(s.index + 1). \(s.instruction)")
                        Text("Distance: \(formatMeters(s.stepDistanceMeters))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding()
        .onChange(of: liveLocation.currentLocation) { _ in
            updateLiveRemaining()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Guidance Mode

    private func toggleGuidance() {
        if guidanceActive {
            stopGuidance()
        } else {
            startGuidance()
        }
    }

    private func startGuidance() {
        guard !steps.isEmpty else {
            speak("Please create a route first.")
            return
        }

        guidanceActive = true
        speakCurrentStep(withDistance: true)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateLiveRemaining()
            autoSpeakDistanceIfChanged()
        }

        listenForGuidanceCommand()
    }

    private func stopGuidance() {
        guidanceActive = false
        timer?.invalidate()
        timer = nil
        speech.stopListening()
        speak("Guidance stopped.")
    }

    private func listenForGuidanceCommand() {
        guard guidanceActive else { return }

        speaker.stopSpeaking(at: .immediate)

        speech.requestPermissions { ok in
            if !ok {
                speak("Speech permission not granted.")
                stopGuidance()
                return
            }

            speech.startListening { finalText in
                let cmd = finalText.lowercased()

                if cmd.contains("stop") {
                    stopGuidance()
                    return
                }

                if cmd.contains("next") {
                    goNextStep()
                } else if cmd.contains("previous") || cmd.contains("back") {
                    goPreviousStep()
                } else if cmd.contains("repeat") || cmd.contains("again") {
                    speakCurrentStep(withDistance: true)
                } else {
                    speak("Say next step, previous, repeat, or stop guidance.")
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    listenForGuidanceCommand()
                }
            }
        }
    }

    private func goNextStep() {
        guard currentStepIndex < steps.count - 1 else {
            speak("You are on the final step. The destination should be nearby.")
            return
        }

        currentStepIndex += 1
        lastSpokenRemainingBucket = nil
        updateLiveRemaining()
        speakCurrentStep(withDistance: true)
    }

    private func goPreviousStep() {
        guard currentStepIndex > 0 else {
            speak("You are at the first step.")
            return
        }

        currentStepIndex -= 1
        lastSpokenRemainingBucket = nil
        updateLiveRemaining()
        speakCurrentStep(withDistance: true)
    }

    private func speakCurrentStep(withDistance: Bool) {
        guard let s = steps[safe: currentStepIndex] else { return }

        if withDistance, let remaining = liveRemainingMeters {
            speak("\(distancePhrase(remaining)), \(s.instruction)")
        } else {
            speak(s.instruction)
        }
    }

    private func autoSpeakDistanceIfChanged() {
        guard guidanceActive, let remaining = liveRemainingMeters else { return }

        let bucket = Int(remaining / 25.0)

        if lastSpokenRemainingBucket == nil {
            lastSpokenRemainingBucket = bucket
            return
        }

        if bucket != lastSpokenRemainingBucket {
            lastSpokenRemainingBucket = bucket

            if remaining <= 300 {
                speak(distancePhrase(remaining))
            }
        }

        if remaining <= 12, currentStepIndex < steps.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let r = liveRemainingMeters, r <= 12, guidanceActive {
                    goNextStep()
                }
            }
        }
    }

    // MARK: - TTS

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        speaker.speak(utterance)
    }

    // MARK: - Transcript Cleaning

    private func extractDestination(from raw: String) -> String {
        var t = raw.lowercased()

        let junk = [
            "please send your destination",
            "please say your destination",
            "please tell me your destination",
            "say your destination",
            "send your destination",
            "destination is",
            "the destination is",
            "go to",
            "navigate to"
        ]

        for j in junk {
            t = t.replacingOccurrences(of: j, with: "")
        }

        t = t.replacingOccurrences(of: "\n", with: " ")

        while t.contains("  ") {
            t = t.replacingOccurrences(of: "  ", with: " ")
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Routing

    private func startRoute(to destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            speak("Please set a destination first.")
            return
        }

        routingStatus = "Searching destination…"
        steps = []
        currentStepIndex = 0
        liveRemainingMeters = nil
        lastSpokenRemainingBucket = nil

        calculatedRoute = nil
        destinationMapItem = nil
        selectedDestinationName = trimmed

        searchDestination(query: trimmed, useRegion: true) { mapItem in
            if let mapItem {
                calculateRoute(to: mapItem, destinationName: trimmed)
            } else {
                self.searchDestination(query: trimmed, useRegion: false) { mapItem2 in
                    guard let mapItem2 else {
                        routingStatus = "No results"
                        speak("I could not find that destination.")
                        return
                    }

                    calculateRoute(to: mapItem2, destinationName: trimmed)
                }
            }
        }
    }

    private func searchDestination(query: String, useRegion: Bool, completion: @escaping (MKMapItem?) -> Void) {
        let searchReq = MKLocalSearch.Request()
        searchReq.naturalLanguageQuery = query

        if useRegion, let loc = liveLocation.currentLocation {
            let center = loc.coordinate
            searchReq.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }

        MKLocalSearch(request: searchReq).start { response, _ in
            completion(response?.mapItems.first)
        }
    }

    private func calculateRoute(to destinationItem: MKMapItem, destinationName: String) {
        routingStatus = "Calculating walking route…"

        let directionsRequest = MKDirections.Request()

        if let loc = liveLocation.currentLocation {
            directionsRequest.source = MKMapItem(
                placemark: MKPlacemark(coordinate: loc.coordinate)
            )
        } else {
            directionsRequest.source = MKMapItem.forCurrentLocation()
        }

        directionsRequest.destination = destinationItem
        // Set the route type to walking, which matches the app's pedestrian navigation purpose
        directionsRequest.transportType = .walking
        // Ask MapKit to calculate the route between the current location and destination
        MKDirections(request: directionsRequest).calculate { result, error in
            if let error = error {
                routingStatus = "Route failed"
                // Speak the route error so the user gets audio feedback
                speak("Could not calculate route. \(error.localizedDescription)")
                return
            }
            guard let route = result?.routes.first else {
                routingStatus = "No route"
                
                // Inform the user when no walking route is available
                speak("No walking route found.")
                return
            }
            // Store the route data so it can be displayed on the live route map screen
            calculatedRoute = route
            destinationMapItem = destinationItem
            selectedDestinationName = destinationName
            // Remove any MapKit route steps that do not contain useful instructions
            let rawSteps = route.steps.filter {
                !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            var built: [RouteStepItem] = []

            for (i, s) in rawSteps.enumerated() {
                let endCoord = endCoordinate(of: s.polyline)

                built.append(
                    RouteStepItem(
                        index: i,
                        instruction: s.instructions,
                        stepDistanceMeters: s.distance,
                        endCoordinate: endCoord
                    )
                )
            }

            steps = built
            currentStepIndex = 0
            updateLiveRemaining()

            routingStatus = "Route ready ✅"

            if let first = steps.first {
                speak("Route to \(destinationName). \(distancePhrase(liveRemainingMeters ?? first.stepDistanceMeters)), \(first.instruction)")
            } else {
                speak("Route found, but no step instructions were available.")
            }
        }
    }

    // MARK: - Live Distance Remaining

    private func updateLiveRemaining() {
        // Stop if the user's current location is not available yet
        guard let userLoc = liveLocation.currentLocation else { return }
        // Stop if there is no valid route step at the current index
        guard let step = steps[safe: currentStepIndex] else { return }
        guard let endCoord = step.endCoordinate else {
            // If the step end coordinate is missing, use the original step distance
            liveRemainingMeters = step.stepDistanceMeters
            return
        }
        // Convert the step's end coordinate into a CLLocation object
        let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
        // Calculate the live distance from the user to the end of the current step
        liveRemainingMeters = userLoc.distance(from: endLoc)
    }

    private func endCoordinate(of polyline: MKPolyline) -> CLLocationCoordinate2D? {
        let count = polyline.pointCount
        guard count > 0 else { return nil }

        let points = polyline.points()
        let last = points[count - 1]

        return last.coordinate
    }

    private func formatMeters(_ meters: Double) -> String {
        if meters >= 1000 {
            let km = meters / 1000.0
            return String(format: "%.1f kilometers", km)
        } else {
            return String(format: "%.0f meters", meters)
        }
    }

    private func distancePhrase(_ meters: Double) -> String {
        if meters < 15 {
            return "Now"
        } else if meters < 1000 {
            return "In \(Int(meters.rounded())) meters"
        } else {
            let km = meters / 1000.0
            return String(format: "In %.1f kilometers", km)
        }
    }
}

// Safe array indexing
extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}




