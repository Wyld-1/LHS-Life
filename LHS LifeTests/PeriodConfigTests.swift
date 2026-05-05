//
//  PeriodConfigTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class PeriodConfigTests: XCTestCase {

    // MARK: 7.1 displayName uses customName when set

    func test_displayName_usesCustomName() {
        let config = PeriodConfig(id: 3, customName: "Chemistry", colorIndex: 0, isEnabled: true)
        XCTAssertEqual(config.displayName, "Chemistry")
    }

    // MARK: 7.2 displayName falls back to "Period N" when customName is empty

    func test_displayName_emptyCustomName_fallsBack() {
        let config = PeriodConfig(id: 3, customName: "", colorIndex: 0, isEnabled: true)
        XCTAssertEqual(config.displayName, "Period 3")
    }

    // MARK: 7.3 displayName falls back when customName is whitespace

    func test_displayName_whitespaceCustomName_fallsBack() {
        let config = PeriodConfig(id: 3, customName: "   ", colorIndex: 0, isEnabled: true)
        XCTAssertEqual(config.displayName, "Period 3")
    }

    // MARK: 7.4 Period 0 falls back to "Period 0"

    func test_displayName_period0_fallsBack() {
        let config = PeriodConfig(id: 0, customName: "", colorIndex: 0, isEnabled: true)
        XCTAssertEqual(config.displayName, "Period 0")
    }

    // MARK: 7.5 defaults has 9 entries (0–8)

    func test_defaults_count() {
        XCTAssertEqual(PeriodConfig.defaults.count, 9)
    }

    // MARK: 7.6 defaults — period 0 is disabled

    func test_defaults_period0_isDisabled() {
        XCTAssertFalse(PeriodConfig.defaults[0].isEnabled)
    }

    // MARK: 7.7 defaults — period 8 is disabled

    func test_defaults_period8_isDisabled() {
        XCTAssertFalse(PeriodConfig.defaults[8].isEnabled)
    }

    // MARK: 7.8 defaults — periods 1–7 are enabled

    func test_defaults_periods1to7_areEnabled() {
        for i in 1...7 {
            XCTAssertTrue(PeriodConfig.defaults[i].isEnabled, "Period \(i) should be enabled")
        }
    }

    // MARK: 7.9 defaults — color indices match rainbow order

    func test_defaults_colorIndices() {
        let expected = [0, 1, 2, 3, 4, 5, 6, 7, 0]
        for (i, expectedIndex) in expected.enumerated() {
            XCTAssertEqual(PeriodConfig.defaults[i].colorIndex, expectedIndex,
                           "Period \(i) colorIndex should be \(expectedIndex)")
        }
    }
}
