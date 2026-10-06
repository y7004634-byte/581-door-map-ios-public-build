import CoreLocation
import Foundation
import WebKit

final class LocationBridge: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pendingOneShot = false
    private var continuousLocationRequested = false
    private var appActive = true
    weak var webView: WKWebView?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = true
        manager.headingFilter = 1
    }

    func requestOneShot() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            pendingOneShot = true
            manager.requestWhenInUseAuthorization()
            return
        }
        guard isAuthorized(status) else {
            emitAuthorization(status)
            return
        }
        manager.requestLocation()
    }

    func setContinuousLocationEnabled(_ enabled: Bool) {
        continuousLocationRequested = enabled
        reconcileLocation()
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        reconcileHeading()
        reconcileLocation()
    }
    func setHeadingOrientation(_ orientation: CLDeviceOrientation) {
        manager.headingOrientation = orientation
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func reconcileHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        if appActive {
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
        }
    }

    private func reconcileLocation() {
        guard isAuthorized(manager.authorizationStatus) else {
            manager.stopUpdatingLocation()
            return
        }
        if appActive && continuousLocationRequested {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        emitAuthorization(status)

        if pendingOneShot {
            pendingOneShot = false
            if isAuthorized(status) {
                manager.requestLocation()
            }
        }
        reconcileHeading()
        reconcileLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let detail: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "speed": location.speed >= 0 ? location.speed : NSNull(),
            "heading": location.course >= 0 ? location.course : NSNull(),
            "timestamp": location.timestamp.timeIntervalSince1970 * 1000
        ]
        emit(event: "door581:nativeLocation", detail: detail)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let detail: [String: Any] = [
            "heading": heading,
            "accuracy": newHeading.headingAccuracy,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        emit(event: "door581:nativeHeading", detail: detail)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        emit(event: "door581:nativeLocationError", detail: ["message": error.localizedDescription])
    }

    private func emitAuthorization(_ status: CLAuthorizationStatus) {
        emit(event: "door581:nativeLocationAuthorization", detail: ["status": status.rawValue])
    }

    private func emit(event: String, detail: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(detail),
              let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return }

        let script = "window.dispatchEvent(new CustomEvent('\(event)', {detail:\(json)}));"
        DispatchQueue.main.async { [weak webView] in
            webView?.evaluateJavaScript(script)
        }
    }
}
