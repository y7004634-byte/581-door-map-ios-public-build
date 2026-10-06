import Foundation
import Contacts
import CoreLocation
import MapKit
import WebKit

/// Coordinate identity uses only the address. POIs remain diagnostic, including
/// same-house results; only an explicit Apple text-search selection names a PIN.
/// Independent halves preserve the address when the diagnostic POI lookup fails.
struct AppleReverseResult {
    var address: [String: Any]?
    var pois: [[String: Any]] = []
    var errors: [String: String] = [:]

    func payload(point: AppleReversePoint) -> [String: Any] {
        return [
            "source": "apple-reverse",
            "point": ["lat": point.latitude, "lng": point.longitude],
            "radiusM": point.radiusM,
            "address": address.map { $0 as Any } ?? NSNull(),
            "pois": pois,
            "errors": errors
        ]
    }
}

final class AppleSearchBridge {
    private struct QueryPlan {
        let term: String
        let alias: String?
        let acceptedNameTokens: [String]
        let brandKey: String?
    }

    weak var webView: WKWebView?
    private var activeSearch: MKLocalSearch?
    private var activeReverse: ReverseRequest?

    private final class ReverseRequest {
        let requestID: String
        let point: AppleReversePoint
        let geocoder = CLGeocoder()
        var search: MKLocalSearch?
        var timeout: DispatchWorkItem?
        var result = AppleReverseResult()
        var addressFinished = false
        var poisFinished = false

        init(requestID: String, point: AppleReversePoint) {
            self.requestID = requestID
            self.point = point
        }

        func cancel() {
            timeout?.cancel()
            geocoder.cancelGeocode()
            search?.cancel()
        }
    }

    func cancel() {
        activeSearch?.cancel(); activeSearch = nil
        cancelReverse()
    }

    private func cancelReverse() {
        guard let previous = activeReverse else { return }
        activeReverse = nil
        previous.cancel()
        resolve(requestID: previous.requestID, ok: false, payload: ["message": "Apple reverse cancelled"])
    }

    /// Destination-only lookup; ordinary text search has a separate cancellation slot.
    func reverse(requestID: String, latitude: Double, longitude: Double, radiusM: Double = 50) {
        guard let point = AppleReversePoint(latitude: latitude, longitude: longitude, radiusM: radiusM) else {
            resolve(requestID: requestID, ok: false, payload: ["message": "Invalid Apple reverse coordinate"])
            return
        }
        cancelReverse()
        let pending = ReverseRequest(requestID: requestID, point: point)
        activeReverse = pending
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: point.radiusM)
        let search = MKLocalSearch(request: request)
        pending.search = search

        let timeout = DispatchWorkItem { [weak self, weak pending] in
            guard let self, let pending, self.activeReverse === pending else { return }
            if !pending.addressFinished { pending.result.errors["address"] = "timeout" }
            if !pending.poisFinished { pending.result.errors["pois"] = "timeout" }
            self.finishReverse(pending)
        }
        pending.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        pending.geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_TW")) { [weak self, weak pending] placemarks, error in
            DispatchQueue.main.async {
                guard let self, let pending, self.activeReverse === pending else { return }
                pending.addressFinished = true
                if let placemark = placemarks?.first {
                    pending.result.address = Self.addressPayload(placemark)
                } else {
                    pending.result.errors["address"] = error?.localizedDescription ?? "No Apple address"
                }
                if pending.poisFinished { self.finishReverse(pending) }
            }
        }
        search.start { [weak self, weak pending] response, error in
            DispatchQueue.main.async {
                guard let self, let pending, self.activeReverse === pending else { return }
                pending.poisFinished = true
                if let response {
                    pending.result.pois = response.mapItems.compactMap {
                        Self.poiPayload($0, origin: location, radiusM: point.radiusM)
                    }.sorted { ($0["distanceM"] as? Double ?? .infinity) < ($1["distanceM"] as? Double ?? .infinity) }
                } else {
                    pending.result.errors["pois"] = error?.localizedDescription ?? "No Apple POI response"
                }
                if pending.addressFinished { self.finishReverse(pending) }
            }
        }
    }

    private func finishReverse(_ pending: ReverseRequest) {
        guard activeReverse === pending else { return }
        activeReverse = nil
        pending.cancel()
        resolve(requestID: pending.requestID, ok: true, payload: pending.result.payload(point: pending.point))
    }

    static func addressPayload(_ placemark: CLPlacemark) -> [String: Any] {
        let house = placemark.subThoroughfare ?? ""
        let road = placemark.thoroughfare ?? ""
        let fallback = [placemark.administrativeArea, placemark.locality, placemark.subLocality, road, house]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined()
        let formatted = placemark.postalAddress.map {
            CNPostalAddressFormatter.string(from: $0, style: .mailingAddress).replacingOccurrences(of: "\n", with: " ")
        } ?? fallback
        var result: [String: Any] = [
            "houseNumber": house, "subThoroughfare": house,
            "road": road, "thoroughfare": road,
            "locality": placemark.locality ?? "",
            "subLocality": placemark.subLocality ?? "",
            "administrativeArea": placemark.administrativeArea ?? "",
            "address": formatted, "formattedAddress": formatted,
            "source": "apple-clgeocoder"
        ]
        if let coordinate = placemark.location?.coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            result["lat"] = coordinate.latitude
            result["lng"] = coordinate.longitude
            result["coordinate"] = ["lat": coordinate.latitude, "lng": coordinate.longitude]
        }
        return result
    }

    static func poiPayload(_ item: MKMapItem, origin: CLLocation, radiusM: Double) -> [String: Any]? {
        let coordinate = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        guard distance.isFinite, distance <= radiusM else { return nil }
        var result = addressPayload(item.placemark)
        result["displayName"] = name
        result["lat"] = coordinate.latitude
        result["lng"] = coordinate.longitude
        result["coordinate"] = ["lat": coordinate.latitude, "lng": coordinate.longitude]
        result["distanceM"] = distance
        result["poiCategory"] = item.pointOfInterestCategory?.rawValue ?? ""
        result["source"] = "apple-mklocalsearch"
        return result
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_TW"))
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}]",
                with: "",
                options: .regularExpression
            )
            .lowercased()
    }

    private func plan(for query: String) -> QueryPlan {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalized(raw)

        let spec: (String, [String], String)?
        switch key {
        case "711", "7eleven", "統一超商":
            spec = ("7-Eleven", ["7eleven", "統一超商"], "7eleven")
        case "全家", "全家便利商店", "familymart":
            spec = ("FamilyMart", ["familymart", "全家"], "familymart")
        case "三媽", "三媽臭臭鍋":
            spec = ("三媽臭臭鍋", ["三媽"], "三媽")
        case "麥當勞", "mcdonald", "mcdonalds":
            spec = ("McDonald's", ["mcdonald", "麥當勞"], "mcdonalds")
        case "50嵐", "50lan":
            spec = ("50 Lan", ["50lan", "50嵐"], "50lan")
        case "清心福全", "chingshinfuchuan":
            spec = ("清心福全", ["清心福全", "chingshinfuchuan"], "清心福全")
        case "胖老爹", "fatdaddy":
            spec = ("Fat Daddy American Fried Chicken", ["fatdaddy", "胖老爹"], "fatdaddy")
        case "築間", "築間幸福鍋物", "jhujian", "zhujian":
            spec = ("築間幸福鍋物", ["築間", "jhujian", "zhujian"], "築間")
        default:
            spec = nil
        }

        guard let spec else {
            return QueryPlan(term: raw, alias: nil, acceptedNameTokens: [], brandKey: nil)
        }
        return QueryPlan(
            term: spec.0,
            alias: raw,
            acceptedNameTokens: spec.1,
            brandKey: spec.2
        )
    }
    func search(
        requestID: String,
        query: String,
        latitude: Double?,
        longitude: Double?,
        radiusM: Double = 3000
    ) {
        activeSearch?.cancel()
        let plan = plan(for: query)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = plan.term
        request.resultTypes = [.pointOfInterest, .address]

        if let latitude, let longitude {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                latitudinalMeters: min(8000, max(3000, radiusM)) * 2,
                longitudinalMeters: min(8000, max(3000, radiusM)) * 2
            )
        } else {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 23.7, longitude: 120.95),
                span: MKCoordinateSpan(latitudeDelta: 4.5, longitudeDelta: 3.0)
            )
        }

        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, error in
            guard let self else { return }

            if let error {
                self.resolve(
                    requestID: requestID,
                    ok: false,
                    payload: ["message": error.localizedDescription]
                )
                return
            }
            let items = response?.mapItems.prefix(30).compactMap { item -> [String: Any]? in
                let placemark = item.placemark
                let displayName = item.name ?? placemark.name ?? ""
                let normalizedName = self.normalized(displayName)

                if !plan.acceptedNameTokens.isEmpty &&
                    !plan.acceptedNameTokens.contains(where: { normalizedName.contains($0) }) {
                    return nil
                }

                let coordinate = placemark.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

                let road = [placemark.thoroughfare, placemark.subThoroughfare]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "")
                let address = [
                    placemark.administrativeArea,
                    placemark.locality,
                    placemark.subLocality,
                    road
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "")

                var result: [String: Any] = [
                    "displayName": displayName,
                    "address": address,
                    "lat": coordinate.latitude,
                    "lng": coordinate.longitude,
                    "source": "apple-mklocalsearch",
                    "feature": item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "").lowercased() ?? "",
                    "sourceLabel": "Apple 地圖"
                ]
                if let alias = plan.alias { result["aliases"] = alias }
                if let brandKey = plan.brandKey { result["appleBrandKey"] = brandKey }
                return result
            } ?? []
            self.resolve(
                requestID: requestID,
                ok: true,
                payload: [
                    "results": items,
                    "query": query,
                    "appleQuery": plan.term
                ]
            )
        }
    }

    private func resolve(requestID: String, ok: Bool, payload: [String: Any]) {
        guard let script = NativeBridge.resolutionScript(requestID: requestID, ok: ok, payload: payload) else { return }

        DispatchQueue.main.async { [weak webView] in
            webView?.evaluateJavaScript(script)
        }
    }
}
