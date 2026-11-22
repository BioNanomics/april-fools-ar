import XCTest

final class HeightDisplayFormatterTests: XCTestCase {
    func testCentimeterPrecisionAndOptionalEnglishUnits() {
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 1.42), "142.0 cm (4 ft 7.9 in)")
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 1.42, showImperial: false), "142.0 cm")
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 1.23456, showImperial: false), "123.5 cm")
    }
    func testRoundedInchesCarryIntoFeet() {
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 11.94 * 0.0254), "30.3 cm (0 ft 11.9 in)")
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 11.96 * 0.0254), "30.4 cm (1 ft 0.0 in)")
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 0.3048), "30.5 cm (1 ft 0.0 in)")
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 59.96 * 0.0254), "152.3 cm (5 ft 0.0 in)")
    }
    func testZeroAndNegativeZeroAreRealValuesButInvalidInputsStayUnavailable() {
        XCTAssertEqual(HeightDisplayFormatter.string(meters: 0), "0.0 cm (0 ft 0.0 in)")
        XCTAssertEqual(HeightDisplayFormatter.string(meters: -0.0), "0.0 cm (0 ft 0.0 in)")
        for value in [Double.nan, Double.infinity, -Double.infinity, -0.001, Double.greatestFiniteMagnitude] {
            XCTAssertNil(HeightDisplayFormatter.string(meters: value))
            XCTAssertNil(HeightDisplayFormatter.string(meters: value, showImperial: false))
        }
    }
    func testLargeEnglishValuesRejectUnsafeIntegerConversionWithoutRejectingFiniteMetricDisplay() {
        let huge = 1e20
        XCTAssertNil(HeightDisplayFormatter.string(meters: huge))
        XCTAssertNotNil(HeightDisplayFormatter.string(meters: huge, showImperial: false))
    }
}
