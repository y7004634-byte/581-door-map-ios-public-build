import CoreLocation
import Foundation
import MapKit

func house(_ placemark: CLPlacemark) -> String {
    (placemark.subThoroughfare ?? "")
        .replacingOccurrences(of: "\u{865F}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func address(_ placemark: CLPlacemark) -> String {
    let street = [placemark.thoroughfare, placemark.subThoroughfare]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined()
    return [placemark.administrativeArea, placemark.locality, placemark.subLocality, street]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined()
}

@main
struct ApplePointProbe {
    static func main() async {
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "吳家紅茶冰"
            request.resultTypes = [.pointOfInterest, .address]
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 24.143, longitude: 120.681),
                latitudinalMeters: 20_000,
                longitudinalMeters: 20_000
            )
            let response = try await MKLocalSearch(request: request).start()
            guard let target = response.mapItems.first(where: {
                let a = address($0.placemark)
                return a.contains("中華路一段") && a.contains("134")
            }) else {
                throw NSError(domain: "ApplePointProbe", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Apple search did not return 吳家紅茶冰 at 中華路一段134"
                ])
            }

            let coordinate = target.placemark.coordinate
            let nearbyRequest = MKLocalPointsOfInterestRequest(center: coordinate, radius: 45)
            let nearbyResponse = try await MKLocalSearch(request: nearbyRequest).start()
            let nearby = nearbyResponse.mapItems.map { item in
                [
                    "name": item.name ?? item.placemark.name ?? "",
                    "address": address(item.placemark),
                    "house": house(item.placemark),
                    "lat": item.placemark.coordinate.latitude,
                    "lng": item.placemark.coordinate.longitude
                ] as [String: Any]
            }
            let sameHouse = nearby.filter { ($0["house"] as? String) == "134" }
            let sameHouseNames = sameHouse.compactMap { $0["name"] as? String }
            let hasWu = sameHouseNames.contains { $0.contains("吳家紅茶冰") }
            let wrongBankAt134 = sameHouseNames.contains { $0.contains("新光") }

            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                preferredLocale: Locale(identifier: "zh_TW")
            )
            let reverse = placemarks.first

            let output: [String: Any] = [
                "targetName": target.name ?? "",
                "targetAddress": address(target.placemark),
                "targetHouse": house(target.placemark),
                "coordinate": ["lat": coordinate.latitude, "lng": coordinate.longitude],
                "reverseAddress": reverse.map(address) ?? "",
                "reverseHouse": reverse.map(house) ?? "",
                "nearbyCount": nearby.count,
                "sameHouseNames": sameHouseNames,
                "sameHouseWu": hasWu,
                "sameHouseWrongBank": wrongBankAt134
            ]
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            guard hasWu, !wrongBankAt134 else {
                throw NSError(domain: "ApplePointProbe", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Nearby Apple POI same-house match failed"
                ])
            }
        } catch {
            FileHandle.standardError.write(Data(("APPLE POINT PROBE FAIL: \(error)\n").utf8))
            exit(1)
        }
    }
}
