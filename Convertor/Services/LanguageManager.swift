import Foundation
import Combine
import SwiftUI // For Locale

class LanguageManager: ObservableObject {
    @Published var currentLocale: Locale {
        didSet {
            UserDefaults.standard.set(currentLocale.identifier, forKey: "selectedLanguageIdentifier")
            // This is crucial for SwiftUI to react to locale changes
            // However, for full app-wide localization, restarting might be needed
            // For now, we rely on SwiftUI's dynamic text updates
        }
    }

    init() {
        if let savedLanguageIdentifier = UserDefaults.standard.string(forKey: "selectedLanguageIdentifier") {
            self.currentLocale = Locale(identifier: savedLanguageIdentifier)
        } else {
            // Default to system locale if no preference saved
            self.currentLocale = Locale.current
        }
    }

    func setLanguage(languageCode: String) {
        self.currentLocale = Locale(identifier: languageCode)
    }
}