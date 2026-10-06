import Foundation
import MapKit

struct ProbeSpec {
    let query: String
    let appleQuery: String
    let accepted: [String]
}

struct ProbeItem: Codable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

struct ProbeResult: Codable {
    let query: String
    let appleQuery: String
    let count: Int
    let items: [ProbeItem]
    let error: String?
}

func norm(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_TW"))
        .replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression)
        .lowercased()
}
@main
struct AppleSearchProbe {
    static func main() async {
        let tests: [ProbeSpec] = [
            .init(query: "7-11", appleQuery: "7-Eleven", accepted: ["7eleven", "統一超商"]),
            .init(query: "全家", appleQuery: "FamilyMart", accepted: ["familymart", "全家"]),
            .init(query: "胖老爹", appleQuery: "Fat Daddy American Fried Chicken", accepted: ["fatdaddy", "胖老爹"]),
            .init(query: "三媽", appleQuery: "三媽臭臭鍋", accepted: ["三媽"]),
            .init(query: "麥當勞", appleQuery: "McDonald's", accepted: ["mcdonald", "麥當勞"]),
            .init(query: "50嵐", appleQuery: "50 Lan", accepted: ["50lan", "50嵐"]),
            .init(query: "清心福全", appleQuery: "清心福全", accepted: ["清心福全", "chingshinfuchuan"]),
            .init(query: "築間", appleQuery: "築間幸福鍋物", accepted: ["築間", "jhujian", "zhujian"])
        ]

        let center = CLLocationCoordinate2D(latitude: 24.1477, longitude: 120.6736)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
        )
        var results: [ProbeResult] = []

        for spec in tests {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = spec.appleQuery
            request.resultTypes = [.pointOfInterest, .address]
            request.region = region

            do {
                let response = try await MKLocalSearch(request: request).start()
                let items = response.mapItems.prefix(30).compactMap { item -> ProbeItem? in
                    let name = item.name ?? item.placemark.name ?? ""
                    let normalizedName = norm(name)
                    guard spec.accepted.contains(where: { normalizedName.contains(norm($0)) }) else {
                        return nil
                    }

                    let placemark = item.placemark
                    let address = [
                        placemark.administrativeArea,
                        placemark.locality,
                        placemark.subLocality,
                        placemark.thoroughfare,
                        placemark.subThoroughfare
                    ]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "")

                    return ProbeItem(
                        name: name,
                        address: address,
                        latitude: placemark.coordinate.latitude,
                        longitude: placemark.coordinate.longitude
                    )
                }

                results.append(
                    ProbeResult(
                        query: spec.query,
                        appleQuery: spec.appleQuery,
                        count: items.count,
                        items: Array(items),
                        error: nil
                    )
                )
            } catch {
                results.append(
                    ProbeResult(
                        query: spec.query,
                        appleQuery: spec.appleQuery,
                        count: 0,
                        items: [],
                        error: error.localizedDescription
                    )
                )
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(results)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data(("encode failed: \(error)\n").utf8))
            exit(2)
        }
    }
}
