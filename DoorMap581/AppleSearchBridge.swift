import CoreLocation
import Foundation
import MapKit
import WebKit

final class AppleSearchBridge {
    private struct QueryPlan {
        let term: String
        let alias: String?
        let acceptedNameTokens: [String]
        let brandKey: String?
    }

    weak var webView: WKWebView?
    private var activeSearch: MKLocalSearch?
    private var activePointSearch: MKLocalSearch?
    private let geocoder = CLGeocoder()

    func cancel() {
        activeSearch?.cancel()
        activeSearch = nil
        activePointSearch?.cancel()
        activePointSearch = nil
        geocoder.cancelGeocode()
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

    private func addressFields(_ placemark: CLPlacemark) -> [String: Any] {
        let road = (placemark.thoroughfare ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHouse = (placemark.subThoroughfare ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let houseNumber = rawHouse
            .replacingOccurrences(of: "\u{865F}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let street = [road, rawHouse].filter { !$0.isEmpty }.joined()
        let address = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            street.isEmpty ? nil : street
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined()

        var out: [String: Any] = [
            "road": road,
            "houseNumber": houseNumber,
            "address": address
        ]
        if let name = placemark.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            out["name"] = name
        }
        return out
    }

    private func pointItem(
        _ item: MKMapItem,
        origin: CLLocation? = nil
    ) -> [String: Any]? {
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        var out = addressFields(placemark)
        let displayName = (item.name ?? placemark.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        out["displayName"] = displayName
        out["lat"] = coordinate.latitude
        out["lng"] = coordinate.longitude
        out["source"] = "apple-mapkit"
        out["feature"] = item.pointOfInterestCategory?.rawValue
            .replacingOccurrences(of: "MKPOICategory", with: "")
            .lowercased() ?? ""
        if let origin {
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            out["distanceM"] = here.distance(from: origin)
        }
        return out
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
        longitude: Double?
    ) {
        activeSearch?.cancel()
        let plan = plan(for: query)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = plan.term
        request.resultTypes = [.pointOfInterest, .address]

        if let latitude, let longitude {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
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
                    "source": "apple-mklocalsearch"
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

    func resolvePoint(
        requestID: String,
        latitude: Double,
        longitude: Double,
        radiusM: Double = 45
    ) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            resolve(requestID: requestID, ok: false, payload: ["message": "Invalid Apple lookup coordinate"])
            return
        }

        activePointSearch?.cancel()
        activePointSearch = nil
        geocoder.cancelGeocode()

        let origin = CLLocation(latitude: latitude, longitude: longitude)
        let radius = min(80, max(20, radiusM))
        let group = DispatchGroup()
        var reverse: [String: Any] = [:]
        var pois: [[String: Any]] = []
        var reverseError = ""
        var poiError = ""

        group.enter()
        geocoder.reverseGeocodeLocation(
            origin,
            preferredLocale: Locale(identifier: "zh_TW")
        ) { [weak self] placemarks, error in
            guard let self else { group.leave(); return }
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    reverse = self.addressFields(placemark)
                } else if let error {
                    reverseError = error.localizedDescription
                }
                group.leave()
            }
        }

        group.enter()
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        let search = MKLocalSearch(request: request)
        activePointSearch = search
        search.start { [weak self] response, error in
            guard let self else { group.leave(); return }
            DispatchQueue.main.async {
                if let error {
                    poiError = error.localizedDescription
                } else {
                    pois = response?.mapItems
                        .compactMap { self.pointItem($0, origin: origin) }
                        .sorted {
                            ($0["distanceM"] as? Double ?? .greatestFiniteMagnitude) <
                            ($1["distanceM"] as? Double ?? .greatestFiniteMagnitude)
                        } ?? []
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            var payload: [String: Any] = [
                "address": reverse,
                "pois": Array(pois.prefix(24)),
                "radiusM": radius
            ]
            if !reverseError.isEmpty { payload["reverseError"] = reverseError }
            if !poiError.isEmpty { payload["poiError"] = poiError }
            self.resolve(requestID: requestID, ok: true, payload: payload)
        }
    }

    private func resolve(requestID: String, ok: Bool, payload: [String: Any]) {
        let args: [Any] = [requestID, ok, payload]
        guard JSONSerialization.isValidJSONObject(args),
              let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8) else { return }

        let script = """
        window.Door581Native &&
        window.Door581Native._resolve &&
        window.Door581Native._resolve.apply(window.Door581Native, \(json));
        """

        DispatchQueue.main.async { [weak webView] in
            webView?.evaluateJavaScript(script)
        }
    }
}
