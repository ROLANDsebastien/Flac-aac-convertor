import XCTest

@testable import Convertor

class ConvertorViewModelTests: XCTestCase {

    var viewModel: ConvertorViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ConvertorViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    func test_add_flac_file() {
        // Given
        let flacURL = URL(fileURLWithPath: "/path/to/test.flac")

        // When
        viewModel.addFile(flacURL)

        // Then
        XCTAssertEqual(viewModel.conversionItems.count, 1)
        XCTAssertEqual(viewModel.conversionItems.first?.sourceURL, flacURL)
        XCTAssertEqual(viewModel.conversionItems.first?.status, .pending)
        XCTAssertEqual(viewModel.conversionItems.first?.outputFormat, .aac)
    }

    func test_add_invalid_file() {
        // Given
        let mp3URL = URL(fileURLWithPath: "/path/to/test.mp3")

        // When
        viewModel.addFile(mp3URL)

        // Then
        XCTAssertEqual(viewModel.conversionItems.count, 0)
    }
}
