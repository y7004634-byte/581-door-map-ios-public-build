import XCTest
import MapKit
import Contacts
@testable import DoorMap581

final class AppleReverseBridgeTests: XCTestCase {
    private final class DelegateSpy: NativeBridgeDelegate {
        var reverse: (id: String, lat: Double, lng: Double, radius: Double)?
        func requestNativeLocation() {}
        func setNativeLocationStreaming(_ enabled: Bool) {}
        func searchApple(requestID: String, query: String, latitude: Double?, longitude: Double?, radiusM: Double) {}
        func reverseApple(requestID: String, latitude: Double, longitude: Double, radiusM: Double) {
            reverse = (requestID, latitude, longitude, radiusM)
        }
        func openExternalURL(_ url: URL) {}
        func webContentReady() {}
    }

    func testBootstrapExposesReverseAndUnchangedSearchSignature() {
        let js = NativeBridge.bootstrapScript.source
        XCTAssertTrue(js.contains("reverseApple(point, radiusM = 50)"))
        XCTAssertTrue(js.contains("call('appleReverse'"))
        XCTAssertTrue(js.contains("searchApple(query, center = null, radiusM = 3000)"))
        XCTAssertTrue(js.contains("shell: '0.3.2'"))
    }

    func testValidationAndRadiusBounds() {
        for (lat, lng) in [(Double.nan, 120.0), (24, Double.infinity), (19.99, 120), (27.01, 120), (24, 116.99), (24, 123.01)] {
            XCTAssertNil(AppleReversePoint(latitude: lat, longitude: lng))
        }
        XCTAssertEqual(AppleReversePoint(latitude: 24, longitude: 120)?.radiusM, 50)
        XCTAssertEqual(AppleReversePoint(latitude: 24, longitude: 120, radiusM: -1)?.radiusM, 20)
        XCTAssertEqual(AppleReversePoint(latitude: 24, longitude: 120, radiusM: 9000)?.radiusM, 100)
        XCTAssertEqual(AppleReversePoint(latitude: 24, longitude: 120, radiusM: .nan)?.radiusM, 50)
        XCTAssertNil(AppleReversePoint(payload: ["point": ["lat": "24", "lng": "120"]]))
    }

    func testHandlerValidatesAndForwardsClampedRequest() {
        let bridge = NativeBridge(), spy = DelegateSpy()
        bridge.delegate = spy
        bridge.handle(type: "appleReverse", payload: ["requestID": "r1", "point": ["lat": 24.135, "lng": 120.688], "radiusM": 1000.0]) { _, _ in XCTFail("valid request rejected") }
        XCTAssertEqual(spy.reverse?.id, "r1")
        XCTAssertEqual(spy.reverse?.lat, 24.135)
        XCTAssertEqual(spy.reverse?.lng, 120.688)
        XCTAssertEqual(spy.reverse?.radius, 100)
        spy.reverse = nil
        var rejected = false
        bridge.handle(type: "appleReverse", payload: ["requestID": "r2", "point": ["lat": 35.0, "lng": 139.0]]) { id, message in
            rejected = true
            XCTAssertEqual(id, "r2")
            XCTAssertTrue(message.contains("Invalid"))
        }
        XCTAssertTrue(rejected)
        XCTAssertNil(spy.reverse)
    }

    func testMissingDelegateRejectsInsteadOfLeavingPromisePending() {
        var rejected = false
        NativeBridge().handle(type: "appleReverse", payload: ["requestID": "r", "point": ["lat": 24.0, "lng": 120.0]]) { _, _ in rejected = true }
        XCTAssertTrue(rejected)
    }

    func testJSONWireNumbersDefaultRadiusAndRegionEdges() throws {
        // WebKit dictionaries bridge JavaScript numbers through NSNumber.
        for (lat, lng) in [(20.0, 117.0), (27.0, 123.0)] {
            let data = try JSONSerialization.data(withJSONObject: ["point": ["lat": lat, "lng": lng]])
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let point = try XCTUnwrap(AppleReversePoint(payload: payload))
            XCTAssertEqual(point.latitude, lat)
            XCTAssertEqual(point.longitude, lng)
            XCTAssertEqual(point.radiusM, 50)
        }
        XCTAssertNil(AppleReversePoint(payload: [:]))
        XCTAssertNil(AppleReversePoint(payload: ["point": ["lat": true, "lng": 120.0]]))
        XCTAssertEqual(AppleReversePoint(latitude: 24, longitude: 120, radiusM: .infinity)?.radiusM, 50)
    }

    func testHandlerRejectsMalformedPointsAndNeverDispatchesMissingRequestID() {
        let bridge = NativeBridge(), spy = DelegateSpy()
        bridge.delegate = spy
        let invalidPoints: [[String: Any]] = [[:], ["lat": Double.nan, "lng": 120.0], ["lat": 24.0, "lng": "120"]]
        for point in invalidPoints {
            var rejected = false
            bridge.handle(type: "appleReverse", payload: ["requestID": "invalid", "point": point]) { id, _ in
                XCTAssertEqual(id, "invalid")
                rejected = true
            }
            XCTAssertTrue(rejected)
            XCTAssertNil(spy.reverse)
        }
        for id in [nil, ""] as [String?] {
            var payload: [String: Any] = ["point": ["lat": 24.0, "lng": 120.0]]
            if let id { payload["requestID"] = id }
            bridge.handle(type: "appleReverse", payload: payload) { _, _ in XCTFail("no valid request to reject") }
            XCTAssertNil(spy.reverse)
        }
        bridge.handle(type: "appleReverse", payload: ["requestID": "low", "point": ["lat": 24.0, "lng": 120.0], "radiusM": -9.0]) { _, _ in XCTFail("valid request rejected") }
        XCTAssertEqual(spy.reverse?.radius, 20)
    }

    func testResolutionRejectsNonJSONPayload() {
        XCTAssertNil(NativeBridge.resolutionScript(requestID: "r", ok: true, payload: ["distance": Double.nan]))
    }

    func testPartialPayloadSerializationPreservesIndependentErrorsAndSubNumber() throws {
        let point = try XCTUnwrap(AppleReversePoint(latitude: 24.135, longitude: 120.688))
        var result = AppleReverseResult()
        result.address = ["houseNumber": "134之1", "road": "中山路四段"]
        result.errors["pois"] = "network"
        let addressOnly = result.payload(point: point)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(addressOnly))
        XCTAssertEqual((addressOnly["address"] as? [String: String])?["houseNumber"], "134之1")
        result.address = nil
        result.pois = [["displayName": "Fixture POI", "houseNumber": "126"]]
        result.errors = ["address": "network"]
        let poiOnly = result.payload(point: point)
        XCTAssertTrue(poiOnly["address"] is NSNull)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(poiOnly))
        XCTAssertEqual((poiOnly["pois"] as? [[String: String]])?.count, 1)
        let script = try XCTUnwrap(NativeBridge.resolutionScript(requestID: "quote'\"\\", ok: true, payload: poiOnly))
        XCTAssertTrue(script.contains("_resolve.apply"))
    }

    func testAddressAuthorityPayloadDoesNotRequireOrMergeDiagnosticPOIs() throws {
        let point = try XCTUnwrap(AppleReversePoint(latitude: 24.135, longitude: 120.688))
        let address = ["houseNumber": "134", "road": "中華路一段", "formattedAddress": "中華路一段134號"]
        for pois in [[], [["displayName": "吳家紅茶冰", "houseNumber": "134"]],
                     [["displayName": "臺灣新光商業銀行", "houseNumber": "126"]]] as [[[String: String]]] {
            var result = AppleReverseResult()
            result.address = address
            result.pois = pois
            if pois.isEmpty { result.errors["pois"] = "unavailable" }
            let payload = result.payload(point: point)
            XCTAssertEqual(payload["address"] as? [String: String], address)
            XCTAssertEqual(payload["source"] as? String, "apple-reverse")
            XCTAssertEqual(payload["pois"] as? [[String: String]], pois)
            XCTAssertNil(payload["placeName"])
            XCTAssertNil(payload["applePlaceLocked"])
            XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        }
    }

    func testPlacemarkAndDiagnosticPOISerializationUsesOnlyAppleFieldsAndRadius() throws {
        let origin = CLLocation(latitude: 24.135, longitude: 120.688)
        let postal = CNMutablePostalAddress()
        postal.street = "中山路四段134之1號"
        postal.city = "台中市"
        postal.isoCountryCode = "TW"
        let placemark = MKPlacemark(coordinate: origin.coordinate, postalAddress: postal)
        let address = AppleSearchBridge.addressPayload(placemark)
        XCTAssertEqual(address["houseNumber"] as? String, placemark.subThoroughfare ?? "")
        XCTAssertEqual(address["road"] as? String, placemark.thoroughfare ?? "")
        XCTAssertTrue((address["formattedAddress"] as? String)?.contains("134之1") == true)
        let item = MKMapItem(placemark: placemark)
        item.name = "Fixture name"
        item.pointOfInterestCategory = .cafe
        let poi = try XCTUnwrap(AppleSearchBridge.poiPayload(item, origin: origin, radiusM: 50))
        XCTAssertEqual(poi["displayName"] as? String, item.name)
        XCTAssertEqual(poi["poiCategory"] as? String, MKPointOfInterestCategory.cafe.rawValue)
        XCTAssertEqual(poi["distanceM"] as? Double, 0)
        XCTAssertNil(AppleSearchBridge.poiPayload(item, origin: CLLocation(latitude: 25, longitude: 121), radiusM: 50))
        item.name = " "
        XCTAssertNil(AppleSearchBridge.poiPayload(item, origin: origin, radiusM: 50))
    }
}
