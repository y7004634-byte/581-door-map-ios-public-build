import CoreLocation
import Foundation
import MapKit

func norm(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_TW"))
        .replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression)
        .lowercased()
}

func canonicalHouse(_ placemark: CLPlacemark) -> String {
    let raw = (placemark.subThoroughfare ?? "")
        .replacingOccurrences(of: "\u{865F}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let match = raw.range(of: #"\d+(?:[-之]\d+)?"#, options: .regularExpression) {
        return String(raw[match]).replacingOccurrences(of: "-", with: "之")
    }
    return raw
}

func fullAddress(_ placemark: CLPlacemark) -> String {
    let street = [placemark.thoroughfare, placemark.subThoroughfare]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined()
    return [placemark.administrativeArea, placemark.locality, placemark.subLocality, street]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined()
}

func isZhonghuaSec1(_ placemark: CLPlacemark) -> Bool {
    let s = norm((placemark.thoroughfare ?? "") + " " + fullAddress(placemark))
    return s.contains(norm("中華路一段"))
        || s.contains("zhonghuardsec1")
        || s.contains("zhonghuaroadsec1")
        || s.contains("zhonghuaroadsection1")
}

func jsonItem(_ item: MKMapItem, origin: CLLocation? = nil) -> [String: Any] {
    let p = item.placemark
    let c = p.coordinate
    var out: [String: Any] = [
        "name": item.name ?? p.name ?? "",
        "address": fullAddress(p),
        "house": canonicalHouse(p),
        "road": p.thoroughfare ?? "",
        "lat": c.latitude,
        "lng": c.longitude
    ]
    if let origin {
        out["distanceM"] = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: origin)
    }
    return out
}

func emit(_ object: [String: Any], exitCode: Int32) -> Never {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    exit(exitCode)
}

@main
struct ApplePointProbe {
    static func main() async {
        let taichungCenter = CLLocation(latitude: 24.145, longitude: 120.6765)
        let region = MKCoordinateRegion(
            center: taichungCenter.coordinate,
            latitudinalMeters: 12_000,
            longitudinalMeters: 12_000
        )

        do {
            // Seed ONLY the test coordinate. Product point resolution below does
            // not know/query the shop name; it receives just the chosen point.
            let seedRequest = MKLocalSearch.Request()
            seedRequest.naturalLanguageQuery = "吳家紅茶冰"
            seedRequest.resultTypes = [.pointOfInterest, .address]
            seedRequest.region = region

            let seedResponse = try await MKLocalSearch(request: seedRequest).start()
            let seedCandidates = seedResponse.mapItems.map { jsonItem($0) }
            guard let target = seedResponse.mapItems.first(where: {
                let p = $0.placemark
                let c = p.coordinate
                let dist = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: taichungCenter)
                let n = norm($0.name ?? p.name ?? "")
                return dist < 10_000
                    && canonicalHouse(p) == "134"
                    && isZhonghuaSec1(p)
                    && (n.contains(norm("吳家紅茶冰")) || n.contains("wujia"))
            }) else {
                emit([
                    "pass": false,
                    "stage": "seed-search",
                    "message": "Apple search did not expose a Taichung Zhonghua Sec 1 house 134 Wu Jia item",
                    "seedCandidates": seedCandidates
                ], exitCode: 1)
            }

            let coordinate = target.placemark.coordinate
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

            // This is the actual product behavior being tested: coordinate only.
            let nearbyRequest = MKLocalPointsOfInterestRequest(center: coordinate, radius: 60)
            let nearbyResponse = try await MKLocalSearch(request: nearbyRequest).start()
            let nearbyItems = nearbyResponse.mapItems.map { jsonItem($0, origin: origin) }
            let sameHouseItems = nearbyResponse.mapItems.filter {
                canonicalHouse($0.placemark) == "134" && isZhonghuaSec1($0.placemark)
            }
            let sameHouseNames = sameHouseItems.map { $0.name ?? $0.placemark.name ?? "" }

            let normalizedSameHouse = sameHouseNames.map(norm)
            let hasWu = normalizedSameHouse.contains {
                $0.contains(norm("吳家紅茶冰")) || $0.contains("wujia")
            }
            let wrongBankAt134 = normalizedSameHouse.contains {
                $0.contains(norm("新光")) || $0.contains("shinkong")
            }

            let geocoder = CLGeocoder()
            let reverseMarks = try await geocoder.reverseGeocodeLocation(
                origin,
                preferredLocale: Locale(identifier: "zh_TW")
            )
            let reverse = reverseMarks.first

            emit([
                "pass": hasWu && !wrongBankAt134,
                "stage": "nearby-poi",
                "seed": jsonItem(target),
                "reverseAddress": reverse.map(fullAddress) ?? "",
                "reverseHouse": reverse.map(canonicalHouse) ?? "",
                "nearbyCount": nearbyItems.count,
                "nearby": nearbyItems,
                "sameHouseNames": sameHouseNames,
                "sameHouseWu": hasWu,
                "sameHouseWrongBank": wrongBankAt134
            ], exitCode: hasWu && !wrongBankAt134 ? 0 : 2)
        } catch {
            emit([
                "pass": false,
                "stage": "exception",
                "message": error.localizedDescription
            ], exitCode: 3)
        }
    }
}
