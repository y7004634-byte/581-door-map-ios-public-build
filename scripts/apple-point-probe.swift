// Source-only live probe. Compile with Xcode 27 on macOS 26+:
// xcrun swiftc -parse-as-library scripts/apple-point-probe.swift -o /tmp/apple-point-probe
// /tmp/apple-point-probe > /tmp/apple-point-probe.json
// No nearby POI result is required for PASS. This does not test the iOS wrapper.
import Foundation
import CoreLocation
import MapKit
import Darwin

struct PointProbeItem: Codable {
    let name: String
    let address: String
    let shortAddress: String
    let latitude: Double
    let longitude: Double
}

struct PointProbeLookup: Codable {
    let items: [PointProbeItem]
    let error: String?
}

struct PointProbeReport: Codable {
    let contract: String
    let addressQuery: String
    let shopQuery: String
    let addressSearch: PointProbeLookup
    let selectedAddress: PointProbeItem?
    let reverseAddress: PointProbeLookup
    let directShopDiagnostic: PointProbeLookup
    let nearbyPOIDiagnostic: PointProbeLookup
    let addressSearchPassed: Bool
    let reverseAddressPassed: Bool
    let passed: Bool
}

@main
struct ApplePointProbe {
    static let addressQuery = "台中市中華路一段134號"
    static let shopQuery = "吳家紅茶冰"

    // Match the exact road and house in Apple's address, never the item name.
    // Full-width text and numeric section spelling are harmless equivalents;
    // 126, 1134, 134之1, 134-1 and 134號之1 must not prove house 134.
    static func isPrecise134(_ item: PointProbeItem) -> Bool {
        let address = (item.address + " " + item.shortAddress)
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let exact = #"中華路(?:一|1)段134[號号](?![之0-9/\-－])"#
        return address.range(of: exact, options: .regularExpression) != nil
            && item.latitude.isFinite && item.longitude.isFinite
            && (20...27).contains(item.latitude) && (117...123).contains(item.longitude)
    }

    @available(macOS 26.0, *)
    static func record(_ item: MKMapItem) -> PointProbeItem {
        PointProbeItem(name: item.name ?? "", address: item.address?.fullAddress ?? "",
                       shortAddress: item.address?.shortAddress ?? "",
                       latitude: item.location.coordinate.latitude,
                       longitude: item.location.coordinate.longitude)
    }

    @MainActor @available(macOS 26.0, *)
    static func search(_ request: MKLocalSearch.Request) async -> PointProbeLookup {
        await search(MKLocalSearch(request: request))
    }

    @MainActor @available(macOS 26.0, *)
    static func search(_ search: MKLocalSearch) async -> PointProbeLookup {
        let timeout = DispatchWorkItem { search.cancel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel() }
        do {
            let response = try await search.start()
            return PointProbeLookup(items: response.mapItems.map(record), error: nil)
        } catch {
            return PointProbeLookup(items: [], error: error.localizedDescription)
        }
    }

    @MainActor @available(macOS 26.0, *)
    static func reverse(_ point: PointProbeItem) async -> PointProbeLookup {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return PointProbeLookup(items: [], error: "Invalid reverse coordinate")
        }
        request.preferredLocale = Locale(identifier: "zh_TW")
        let timeout = DispatchWorkItem { request.cancel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel() }
        do {
            let items = try await request.mapItems
            return PointProbeLookup(items: items.map(record), error: nil)
        } catch {
            return PointProbeLookup(items: [], error: error.localizedDescription)
        }
    }

    @MainActor @available(macOS 26.0, *)
    static func run() async -> PointProbeReport {
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 24.1477, longitude: 120.6736),
                                        latitudinalMeters: 15000, longitudinalMeters: 15000)
        let addressRequest = MKLocalSearch.Request()
        addressRequest.naturalLanguageQuery = addressQuery
        addressRequest.resultTypes = .address
        addressRequest.region = region
        let addressSearch = await search(addressRequest)
        let selectedAddress = addressSearch.items.first(where: isPrecise134)
        let reverseAddress: PointProbeLookup
        if let selectedAddress {
            reverseAddress = await reverse(selectedAddress)
        } else {
            reverseAddress = PointProbeLookup(items: [], error: "No precise Apple address coordinate; reverse not run")
        }
        let addressSearchPassed = selectedAddress != nil
        let reverseAddressPassed = reverseAddress.items.contains(where: isPrecise134)
        let passed = addressSearchPassed && reverseAddressPassed

        // Diagnostics cannot affect the contract verdict, including zero items,
        // errors, or a shop found at 134 only by direct text search.
        let shopRequest = MKLocalSearch.Request()
        shopRequest.naturalLanguageQuery = shopQuery
        shopRequest.resultTypes = .pointOfInterest
        shopRequest.region = region
        let directShopDiagnostic = await search(shopRequest)
        let nearbyPOIDiagnostic: PointProbeLookup
        if let selectedAddress {
            let center = CLLocationCoordinate2D(latitude: selectedAddress.latitude, longitude: selectedAddress.longitude)
            nearbyPOIDiagnostic = await search(MKLocalSearch(request: MKLocalPointsOfInterestRequest(center: center, radius: 50)))
        } else {
            nearbyPOIDiagnostic = PointProbeLookup(items: [], error: "No address coordinate; diagnostic not run")
        }
        return PointProbeReport(contract: "APPLE_COORDINATE_ADDRESS_AUTHORITY_ONLY",
            addressQuery: addressQuery, shopQuery: shopQuery, addressSearch: addressSearch,
            selectedAddress: selectedAddress, reverseAddress: reverseAddress,
            directShopDiagnostic: directShopDiagnostic, nearbyPOIDiagnostic: nearbyPOIDiagnostic,
            addressSearchPassed: addressSearchPassed, reverseAddressPassed: reverseAddressPassed, passed: passed)
    }

    @MainActor static func main() async {
        guard #available(macOS 26.0, *) else {
            FileHandle.standardError.write(Data("NOT RUN: requires macOS 26+ and a current MapKit SDK\n".utf8))
            exit(2)
        }
        let report = await run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(report.passed ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data("encode failed: \(error)\n".utf8))
            exit(2)
        }
    }
}
