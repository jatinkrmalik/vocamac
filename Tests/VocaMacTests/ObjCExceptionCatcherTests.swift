// ObjCExceptionCatcherTests.swift
// VocaMac

import Foundation
import VocaMacObjC
import XCTest

final class ObjCExceptionCatcherTests: XCTestCase {

    func testCatchExceptionReturnsNilWhenBlockDoesNotRaise() {
        let error = VocaObjCExceptionCatcher.catchException {
            _ = "safe block"
        }

        XCTAssertNil(error)
    }

    func testCatchExceptionConvertsNSExceptionToNSError() throws {
        let error = VocaObjCExceptionCatcher.catchException {
            NSException(
                name: NSExceptionName("VocaMacTestException"),
                reason: "simulated Objective-C exception",
                userInfo: nil
            ).raise()
        }

        let unwrappedError = try XCTUnwrap(error as NSError?)
        XCTAssertEqual(unwrappedError.domain, "com.vocamac.objc-exception")
        XCTAssertEqual(unwrappedError.localizedDescription, "simulated Objective-C exception")
        XCTAssertEqual(unwrappedError.userInfo["NSExceptionName"] as? String, "VocaMacTestException")
    }
}
