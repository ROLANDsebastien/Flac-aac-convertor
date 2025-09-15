import XCTest

@testable import Convertor

class ConversionServiceTests: XCTestCase {

    var conversionService: ConversionService!

    override func setUp() {
        super.setUp()
        conversionService = ConversionService()
    }

    override func tearDown() {
        conversionService = nil
        super.tearDown()
    }

    func test_conversion_service_aac() {
        // Given
        let sourceURL = URL(fileURLWithPath: "/path/to/input.flac")
        let item = ConversionItem(sourceURL: sourceURL, outputFormat: .aac)

        // Then
        XCTAssertEqual(item.outputFormat, .aac)
    }

    func test_conversion_service_alac() {
        // Given
        let sourceURL = URL(fileURLWithPath: "/path/to/input.flac")
        let item = ConversionItem(sourceURL: sourceURL, outputFormat: .alac)

        // Then
        XCTAssertEqual(item.outputFormat, .alac)
    }
}
