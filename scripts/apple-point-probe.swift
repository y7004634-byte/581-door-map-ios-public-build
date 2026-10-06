import CoreLocation
import Foundation
import MapKit

private let road134Query = "\u{81FA}\u{4E2D}\u{5E02}\u{4E2D}\u{5340}\u{4E2D}\u{83EF}\u{8DEF}\u{4E00}\u{6BB5}134\u{865F}"
private let roadName = "\u{4E2D}\u{83EF}\u{8DEF}\u{4E00}\u{6BB5}"
private let wuName = "\u{5433}\u{5BB6}\u{7D05}\u{8336}\u{51B0}"
private let shinKongToken = "\u{65B0}\u{5149}"

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

func emit(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

@main
struct ApplePointProbe {
    static func main() async {
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = road134Query
            request.resultTypes = [.address, .pointOfInterest]
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 24.143, longitude: 120.681),
                latitudinalMeters: 20_000,
                longitudinalMeters: 20_000
            )

            let response = try await MKLocalSearch(request: request).start()
            guard let target = response.mapItems.first(where: {
                let a = address($0.placemark)
                return house($0.placemark) == "134" ||
                    (a.contains(roadName) && a.contains("134"))
            }) else {
                try emit([
                    "status": "OBSERVED_NO_134_ADDRESS_RESULT",
                    "query": road134Query,
                    "resultCount": response.mapItems.count,
                    "note": "Live Apple result variance is informational; build must not fail."
                ])
                return
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
            let hasWu = sameHouseNames.contains { $0.contains(wuName) }
            let wrongBankAt134 = sameHouseNames.contains { $0.contains(shinKongToken) }

            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                preferredLocale: Locale(identifier: "zh_TW")
            )
            let reverse = placemarks.first

            try emit([
                "status": wrongBankAt134 ? "FAIL_WRONG_HOUSE_POI" : "PASS_OBSERVED",
                "targetName": target.name ?? "",
                "targetAddress": address(target.placemark),
                "targetHouse": house(target.placemark),
                "coordinate": ["lat": coordinate.latitude, "lng": coordinate.longitude],
                "reverseAddress": reverse.map(address) ?? "",
                "reverseHouse": reverse.map(house) ?? "",
                "nearbyCount": nearby.count,
                "sameHouseNames": sameHouseNames,
                "sameHouseWu": hasWu,
                "sameHouseWrongBank": wrongBankAt134,
                "note": "Wu POI is optional. Different-house POIs must not be promoted by Web matching policy."
            ])

            if wrongBankAt134 {
                throw NSError(domain: "ApplePointProbe", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Apple reported a Shin Kong POI as house 134."
                ])
            }
        } catch {
            FileHandle.standardError.write(Data(("APPLE POINT PROBE FAIL: \(error)\n").utf8))
            exit(1)
        }
    }
}
