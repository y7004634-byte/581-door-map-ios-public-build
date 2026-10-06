import XCTest
@testable import DoorMap581

final class ApplePointBridgeTests: XCTestCase {
    func testBootstrapExposesApplePointResolver() {
        let source = NativeBridge.bootstrapScript.source
        XCTAssertTrue(source.contains("resolveApplePoint"))
        XCTAssertTrue(source.contains("applePointResolve"))
        XCTAssertTrue(source.contains("radiusM = 45"))
    }

    func testNativeVersionBumpedForBridgeContract() {
        XCTAssertTrue(AppConfig.userAgentSuffix.contains("0.2.1"))
    }
}
