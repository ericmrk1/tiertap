import SwiftUI
import MapKit
import UIKit

enum FlightGeodesic {
    /// Spherical interpolation for a curved great-circle path between two coordinates.
    static func coordinates(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, steps: Int = 72) -> [CLLocationCoordinate2D] {
        guard steps >= 2 else { return [a, b] }

        let lat1 = a.latitude * .pi / 180
        let lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let lon2 = b.longitude * .pi / 180

        let sinHalfDLat = sin((lat2 - lat1) / 2)
        let sinHalfDLon = sin((lon2 - lon1) / 2)
        let h = min(1, sinHalfDLat * sinHalfDLat + cos(lat1) * cos(lat2) * sinHalfDLon * sinHalfDLon)
        let d = 2 * asin(sqrt(h))

        guard d > 1e-8 else { return [a, b] }

        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(steps)
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            out.append(slerp(aLat: lat1, aLon: lon1, bLat: lat2, bLon: lon2, frac: t, angularDistance: d))
        }
        return out
    }

    private static func slerp(aLat: Double, aLon: Double, bLat: Double, bLon: Double, frac: Double, angularDistance d: Double) -> CLLocationCoordinate2D {
        let sinD = sin(d)
        let A = sin((1 - frac) * d) / sinD
        let B = sin(frac * d) / sinD
        let x = A * cos(aLat) * cos(aLon) + B * cos(bLat) * cos(bLon)
        let y = A * cos(aLat) * sin(aLon) + B * cos(bLat) * sin(bLon)
        let z = A * sin(aLat) + B * sin(bLat)
        let lat = atan2(z, hypot(x, y))
        let lon = atan2(y, x)
        return CLLocationCoordinate2D(
            latitude: lat * 180 / .pi,
            longitude: lon * 180 / .pi
        )
    }
}

struct FlightRouteMapView: UIViewRepresentable {
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    var originLabel: String
    var destinationLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        let o = MKPointAnnotation()
        o.coordinate = origin
        o.title = originLabel
        let d = MKPointAnnotation()
        d.coordinate = destination
        d.title = destinationLabel
        mapView.addAnnotations([o, d])

        let coords = FlightGeodesic.coordinates(from: origin, to: destination)
        let poly = MKPolyline(coordinates: coords, count: coords.count)
        mapView.addOverlay(poly)

        let rect = poly.boundingMapRect
        let pad = UIEdgeInsets(top: 56, left: 44, bottom: 56, right: 44)
        mapView.setVisibleMapRect(rect, edgePadding: pad, animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = UIColor.systemCyan
                r.lineWidth = 3
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Static map for trip share image

@MainActor
enum TripFlightRouteSnapshot {
    /// Single map showing all bookable legs (great-circle paths in cyan), matching `FlightRouteMapView` styling.
    static func makeImage(legs: [TripFlightLeg], mapSize: CGSize) async -> UIImage? {
        let routed = legs.filter(\.hasRoute)
        guard !routed.isEmpty else { return nil }

        var polylines: [[CLLocationCoordinate2D]] = []
        var mergedForRegion: [CLLocationCoordinate2D] = []
        for leg in routed {
            guard let o = leg.originCoordinate, let d = leg.destinationCoordinate else { continue }
            let coords = FlightGeodesic.coordinates(from: o, to: d)
            polylines.append(coords)
            mergedForRegion.append(contentsOf: coords)
        }
        guard !polylines.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = regionCovering(mergedForRegion, paddingFraction: 0.28)
        options.mapType = .mutedStandard
        options.size = mapSize
        options.scale = UIScreen.main.scale

        return await withCheckedContinuation { continuation in
            let snapshotter = MKMapSnapshotter(options: options)
            snapshotter.start { snapshot, error in
                guard let snapshot, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.drawRoutes(on: snapshot, polylines: polylines))
            }
        }
    }

    private static func regionCovering(_ coordinates: [CLLocationCoordinate2D], paddingFraction: CGFloat) -> MKCoordinateRegion {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for c in coordinates {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        var latDelta = (maxLat - minLat) * (1 + paddingFraction * 2)
        var lonDelta = (maxLon - minLon) * (1 + paddingFraction * 2)
        latDelta = max(latDelta, 0.12)
        lonDelta = max(lonDelta, 0.12)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    private static func drawRoutes(on snapshot: MKMapSnapshotter.Snapshot, polylines: [[CLLocationCoordinate2D]]) -> UIImage {
        let base = snapshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        return renderer.image { ctx in
            base.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor.cyan.cgColor)
            cg.setLineWidth(3)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for coords in polylines {
                guard let first = coords.first else { continue }
                cg.beginPath()
                cg.move(to: snapshot.point(for: first))
                for c in coords.dropFirst() {
                    cg.addLine(to: snapshot.point(for: c))
                }
                cg.strokePath()
            }
            cg.setFillColor(UIColor.systemOrange.cgColor)
            for coords in polylines {
                if let a = coords.first {
                    let p = snapshot.point(for: a)
                    cg.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
                if let b = coords.last, coords.count > 1 {
                    let p = snapshot.point(for: b)
                    cg.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
            }
        }
    }
}
