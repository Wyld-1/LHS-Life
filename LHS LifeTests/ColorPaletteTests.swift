//
//  ColorPaletteTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class ColorPaletteTests: XCTestCase {

    // MARK: 8.1 Palette has exactly 10 colors

    func test_palette_hasTenColors() {
        XCTAssertEqual(ColorPalette.colors.count, 10)
    }

    // MARK: 8.2 IDs are sequential 0–9

    func test_palette_idsAreSequential() {
        XCTAssertEqual(ColorPalette.colors.map(\.id), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    }

    // MARK: 8.3 All hex strings are valid format

    func test_palette_hexStringsAreValid() {
        let hexChars = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        for color in ColorPalette.colors {
            XCTAssertTrue(color.hex.hasPrefix("#"), "\(color.name): hex should start with #")
            XCTAssertEqual(color.hex.count, 7, "\(color.name): hex should be 7 chars")
            let withoutHash = String(color.hex.dropFirst())
            XCTAssertTrue(withoutHash.unicodeScalars.allSatisfy { hexChars.contains($0) },
                          "\(color.name): hex contains invalid chars")
        }
    }

    // MARK: 8.4 color(at:) clamps below zero

    func test_colorAt_clampsBelow() {
        XCTAssertEqual(ColorPalette.color(at: -1).id, 0)
    }

    // MARK: 8.5 color(at:) clamps above 9

    func test_colorAt_clampsAbove() {
        XCTAssertEqual(ColorPalette.color(at: 10).id, 9)
        XCTAssertEqual(ColorPalette.color(at: 999).id, 9)
    }

    // MARK: 8.6 color(at:) returns correct entry

    func test_colorAt_returnsCorrectEntry() {
        XCTAssertEqual(ColorPalette.color(at: 6).name, "LaSalle Blue")
        XCTAssertEqual(ColorPalette.color(at: 6).hex, "#3A6FD8")
    }
}
