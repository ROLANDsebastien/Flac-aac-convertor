import Combine
import Foundation

enum AudioQuality: Int, CaseIterable, Identifiable {
    case low, medium, high, veryHigh, lossless
    var id: Int { self.rawValue }

    var name: String {
        switch self {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very High")
        case .lossless: return String(localized: "Lossless")
        }
    }

    var bitrate: Int {
        switch self {
        case .low: return 96
        case .medium: return 128
        case .high: return 192
        case .veryHigh: return 256
        case .lossless: return 0  // alac is lossless
        }
    }
}

class Settings: ObservableObject {
    @Published var defaultOutputFormat: OutputFormat {
        didSet {
            UserDefaults.standard.set(defaultOutputFormat.rawValue, forKey: "defaultOutputFormat")
        }
    }

    @Published var audioQuality: AudioQuality {
        didSet {
            UserDefaults.standard.set(audioQuality.rawValue, forKey: "audioQuality")
        }
    }

    @Published var maxConcurrentTasks: Int {
        didSet {
            UserDefaults.standard.set(maxConcurrentTasks, forKey: "maxConcurrentTasks")
        }
    }

    @Published var outputDirectory: URL? {
        didSet {
            guard let url = outputDirectory else {
                UserDefaults.standard.removeObject(forKey: "outputDirectory")
                return
            }
            do {
                let bookmark = try url.bookmarkData(
                    options: .withSecurityScope, includingResourceValuesForKeys: nil,
                    relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: "outputDirectory")
            } catch {
                print("Error saving output directory bookmark: \(error.localizedDescription)")
                // If bookmark creation fails (e.g., Downloads folder), reset to nil
                // This will cause the app to use the default Documents directory
                DispatchQueue.main.async {
                    self.outputDirectory = nil
                }
            }
        }
    }

    init() {
        self.defaultOutputFormat =
            OutputFormat(
                rawValue: UserDefaults.standard.string(forKey: "defaultOutputFormat") ?? "aac")
            ?? .aac
        self.audioQuality =
            AudioQuality(rawValue: UserDefaults.standard.integer(forKey: "audioQuality")) ?? .high
        self.maxConcurrentTasks =
            UserDefaults.standard.integer(forKey: "maxConcurrentTasks") == 0
            ? 4 : UserDefaults.standard.integer(forKey: "maxConcurrentTasks")
        if let bookmark = UserDefaults.standard.data(forKey: "outputDirectory") {
            do {
                var isStale = false
                self.outputDirectory = try URL(
                    resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                    bookmarkDataIsStale: &isStale)
                if isStale {
                    // Clear stale bookmark
                    UserDefaults.standard.removeObject(forKey: "outputDirectory")
                    self.outputDirectory = nil
                }
            } catch {
                print("Error resolving output directory bookmark: \(error.localizedDescription)")
                // Clear invalid bookmark data so user can select a new directory
                UserDefaults.standard.removeObject(forKey: "outputDirectory")
                self.outputDirectory = nil
            }
        }
    }
}
