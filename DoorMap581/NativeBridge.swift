import Foundation
import WebKit

/// WKUserContentController owns its handlers; forward without owning the screen.
final class WeakNativeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

protocol NativeBridgeDelegate: AnyObject {
    func requestNativeLocation()
    func setNativeLocationStreaming(_ enabled: Bool)
    func searchApple(
        requestID: String,
        query: String,
        latitude: Double?,
        longitude: Double?,
        radiusM: Double
    )
    func reverseApple(requestID: String, latitude: Double, longitude: Double, radiusM: Double)
    func openExternalURL(_ url: URL)
    func webContentReady()
}

/// The JS bridge and native resolver use the same bounded destination request.
struct AppleReversePoint {
    let latitude: Double
    let longitude: Double
    let radiusM: Double

    init?(latitude: Double, longitude: Double, radiusM: Double = 50) {
        guard latitude.isFinite, longitude.isFinite,
              (20...27).contains(latitude), (117...123).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        self.radiusM = radiusM.isFinite ? min(100, max(20, radiusM)) : 50
    }

    init?(payload: [String: Any]) {
        guard let point = payload["point"] as? [String: Any],
              let latitude = point["lat"] as? Double,
              let longitude = point["lng"] as? Double else { return nil }
        self.init(latitude: latitude, longitude: longitude, radiusM: payload["radiusM"] as? Double ?? 50)
    }
}

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var delegate: NativeBridgeDelegate?

    static var bootstrapScript: WKUserScript {
        let source = """
        (() => {
          if (window.Door581Native) return;
          const pending = new Map();
          let seq = 0;

          const post = (type, payload = {}) => {
            window.webkit.messageHandlers.doorMapNative.postMessage({ type, payload });
          };
          const call = (type, payload = {}, timeoutMs = 0) => new Promise((resolve, reject) => {
            const requestID = 'n' + Date.now().toString(36) + '-' + (++seq).toString(36);
            const timer = timeoutMs ? setTimeout(() => {
              pending.delete(requestID);
              reject(new Error('Native request timeout'));
            }, timeoutMs) : null;
            pending.set(requestID, { resolve, reject, timer });
            try { post(type, { ...payload, requestID }); }
            catch (error) { clearTimeout(timer); pending.delete(requestID); reject(error); }
          });

          window.Door581Native = Object.freeze({
            isNative: true,
            shell: '0.3.2',
            post,
            requestLocation() {
              post('requestLocation');
            },
            startLocation() {
              post('locationStream', { enabled: true });
            },
            stopLocation() {
              post('locationStream', { enabled: false });
            },
            searchApple(query, center = null, radiusM = 3000) {
              return call('appleSearch', { query, center, radiusM });
            },
            reverseApple(point, radiusM = 50) {
              if (!point || !Number.isFinite(point.lat) || !Number.isFinite(point.lng) ||
                  point.lat < 20 || point.lat > 27 || point.lng < 117 || point.lng > 123) {
                return Promise.reject(new Error('Invalid Apple reverse coordinate'));
              }
              const radius = Number.isFinite(radiusM) ? Math.min(100, Math.max(20, radiusM)) : 50;
              return call('appleReverse', { point: { lat: point.lat, lng: point.lng }, radiusM: radius }, 12000);
            },
            _resolve(requestID, ok, payload) {
              const entry = pending.get(requestID);
              if (!entry) return;
              pending.delete(requestID);
              clearTimeout(entry.timer);
              if (ok) entry.resolve(payload);
              else entry.reject(new Error(payload?.message || 'Native request failed'));
            }
          });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
    static var readyScript: WKUserScript {
        let source = """
        (() => {
          const detail = { platform: 'ios', shell: '0.3.2' };
          window.dispatchEvent(new CustomEvent('door581:nativeReady', { detail }));
          try {
            window.webkit.messageHandlers.doorMapNative.postMessage({ type: 'ready', payload: detail });
          } catch (_) {}
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == AppConfig.nativeBridgeName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]
        handle(type: type, payload: payload) { [weak webView = message.webView] requestID, message in
            guard let script = Self.resolutionScript(requestID: requestID, ok: false, payload: ["message": message]) else { return }
            webView?.evaluateJavaScript(script)
        }
    }

    /// Kept separate from WKScriptMessage so validation/dispatch can be tested without a WebKit message instance.
    func handle(type: String, payload: [String: Any], reject: (String, String) -> Void) {
        switch type {
        case "requestLocation":
            delegate?.requestNativeLocation()

        case "locationStream":
            let enabled = (payload["enabled"] as? Bool) ?? false
            delegate?.setNativeLocationStreaming(enabled)

        case "appleSearch":
            guard let requestID = payload["requestID"] as? String,
                  let query = payload["query"] as? String,
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let center = payload["center"] as? [String: Any]
            let latitude = center?["lat"] as? Double
            let longitude = center?["lng"] as? Double

            delegate?.searchApple(
                requestID: requestID,
                query: query,
                latitude: latitude,
                longitude: longitude,
                radiusM: min(8000, max(3000, payload["radiusM"] as? Double ?? 3000))
            )

        case "appleReverse":
            guard let requestID = payload["requestID"] as? String, !requestID.isEmpty else { return }
            guard let point = AppleReversePoint(payload: payload) else {
                reject(requestID, "Invalid Apple reverse coordinate")
                return
            }
            guard let delegate else {
                reject(requestID, "Apple reverse unavailable")
                return
            }
            delegate.reverseApple(requestID: requestID, latitude: point.latitude, longitude: point.longitude, radiusM: point.radiusM)

        case "openExternal":
            guard let raw = payload["url"] as? String,
                  let url = URL(string: raw) else { return }
            delegate?.openExternalURL(url)

        case "ready":
            delegate?.webContentReady()

        default:
            break
        }
    }

    static func resolutionScript(requestID: String, ok: Bool, payload: [String: Any]) -> String? {
        let args: [Any] = [requestID, ok, payload]
        guard JSONSerialization.isValidJSONObject(args),
              let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "window.Door581Native && window.Door581Native._resolve && window.Door581Native._resolve.apply(window.Door581Native, \(json));"
    }
}
