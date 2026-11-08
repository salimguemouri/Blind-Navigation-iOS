import SwiftUI
import MapKit
import CoreLocation

struct NavigationMapView: View {
    let route: MKRoute
    let userCoordinate: CLLocationCoordinate2D?
    let destinationCoordinate: CLLocationCoordinate2D
    let destinationName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            RouteMapRepresentable(
                route: route,
                userCoordinate: userCoordinate,
                destinationCoordinate: destinationCoordinate,
                destinationName: destinationName
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Close route map")

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Live Route Map")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Text("Destination: \(destinationName)")
                        .font(.subheadline)

                    Text("Distance: \(formatDistance(route.distance))")
                        .font(.subheadline)

                    Text("Estimated time: \(formatTime(route.expectedTravelTime))")
                        .font(.subheadline)

                    Text("Map follows the user’s live location during movement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)

        if minutes < 1 {
            return "Less than 1 minute"
        } else if minutes == 1 {
            return "1 minute"
        } else {
            return "\(minutes) minutes"
        }
    }
}

struct RouteMapRepresentable: UIViewRepresentable {
    let route: MKRoute
    let userCoordinate: CLLocationCoordinate2D?
    let destinationCoordinate: CLLocationCoordinate2D
    let destinationName: String

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()

        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.pointOfInterestFilter = .includingAll

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        let destinationPin = MKPointAnnotation()
        destinationPin.coordinate = destinationCoordinate
        destinationPin.title = destinationName.isEmpty ? "Destination" : destinationName
        mapView.addAnnotation(destinationPin)

        mapView.addOverlay(route.polyline)

        if !context.coordinator.didFitInitialRoute {
            context.coordinator.didFitInitialRoute = true

            let routeRect = route.polyline.boundingMapRect
            let padding = UIEdgeInsets(top: 120, left: 60, bottom: 120, right: 60)
            mapView.setVisibleMapRect(routeRect, edgePadding: padding, animated: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                mapView.userTrackingMode = .follow
            }
        } else {
            if mapView.userTrackingMode == .none {
                mapView.userTrackingMode = .follow
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var didFitInitialRoute = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 6
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
