import Combine
import Foundation

struct ConversionItem: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
    var status: ConversionStatus = .pending
    var outputFormat: OutputFormat = .aac
    var progress: Double = 0.0
    var errorMessage: String? = nil
    var cancellable: AnyCancellable?

    static func == (lhs: ConversionItem, rhs: ConversionItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum ConversionStatus: Equatable {
    case pending
    case converting
    case completed
    case failed
    case cancelled
}

enum OutputFormat: String, CaseIterable, Identifiable, Equatable {
    case aac = "AAC"
    case alac = "Apple Lossless"
    var id: String { rawValue }
}
