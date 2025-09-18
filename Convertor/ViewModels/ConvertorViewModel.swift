import AVFoundation
import Combine
import Foundation
import SwiftUI
import UserNotifications

class ConvertorViewModel: ObservableObject {
    @Published var conversionItems: [ConversionItem] = []
    @Published var selectedOutputFormat: OutputFormat
    @Published var isConverting: Bool = false

    private let conversionService = ConversionService()
    private var conversionQueue = PassthroughSubject<UUID, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let settings: Settings
    private var activeConversions = 0

    init(settings: Settings) {
        self.settings = settings
        self.selectedOutputFormat = settings.defaultOutputFormat
        setupConversionQueue()
    }

    private func setupConversionQueue() {
        conversionQueue
            .flatMap(maxPublishers: .max(settings.maxConcurrentTasks)) {
                [weak self] itemID -> AnyPublisher<(UUID, Result<URL, Error>), Never> in
                guard let self = self,
                    let index = self.conversionItems.firstIndex(where: { $0.id == itemID })
                else {
                    return Empty().eraseToAnyPublisher()
                }

                let item = self.conversionItems[index]

                return self.conversionService.convert(
                    fileURL: item.sourceURL,
                    to: self.selectedOutputFormat,
                    quality: self.settings.audioQuality,
                    outputDirectory: self.settings.outputDirectory,
                    progressHandler: { progress in
                        DispatchQueue.main.async {
                            self.updateProgress(for: itemID, progress: progress)
                        }
                    }
                )
                .map { url in (itemID, .success(url)) }
                .catch { error in Just((itemID, .failure(error))) }
                .handleEvents(receiveSubscription: { subscription in
                    DispatchQueue.main.async {
                        self.activeConversions += 1
                        if let index = self.conversionItems.firstIndex(where: { $0.id == itemID }) {
                            var item = self.conversionItems[index]
                            item.status = .converting
                            item.cancellable = AnyCancellable(subscription)
                            self.conversionItems[index] = item
                        }
                    }
                })
                .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (itemID, result) in
                guard let self = self else { return }
                switch result {
                case .success(_):
                    self.updateStatus(for: itemID, status: .completed)
                case .failure(let error):
                    self.updateStatus(
                        for: itemID, status: .failed, error: error.localizedDescription)
                }
                self.activeConversions -= 1
                self.sendNextPending()
            }
            .store(in: &cancellables)
    }

    func addFile(url: URL) {
        if url.pathExtension.lowercased() == "flac" {
            let newItem = ConversionItem(sourceURL: url, outputFormat: selectedOutputFormat)
            if !conversionItems.contains(where: { $0.sourceURL == newItem.sourceURL }) {
                conversionItems.append(newItem)
            }
        } else {
            print(String(localized: "Non-FLAC file ignored: ") + url.lastPathComponent)
        }
    }

    func removeItems(at offsets: IndexSet) {
        let idsToRemove = offsets.map { conversionItems[$0].id }
        idsToRemove.forEach { cancelConversion(for: $0) }
        conversionItems.remove(atOffsets: offsets)
    }

    func clearConversionItems() {
        cancelAllConversions()
        conversionItems.removeAll()
    }

    func convertAllFiles() {
        guard !isConverting else { return }
        isConverting = true
        activeConversions = 0

        for _ in 0..<settings.maxConcurrentTasks {
            sendNextPending()
        }
    }

    private func sendNextPending() {
        if activeConversions < settings.maxConcurrentTasks,
            let nextItem = conversionItems.first(where: { $0.status == .pending })
        {
            conversionQueue.send(nextItem.id)
        }
    }

    func cancelConversion(for itemID: UUID) {
        if let index = conversionItems.firstIndex(where: { $0.id == itemID }) {
            conversionItems[index].cancellable?.cancel()
        }
    }

    func cancelAllConversions() {
        for item in conversionItems {
            item.cancellable?.cancel()
        }
        activeConversions = 0
        isConverting = false
    }

    private func updateStatus(for itemID: UUID, status: ConversionStatus, error: String? = nil) {
        if let index = conversionItems.firstIndex(where: { $0.id == itemID }) {
            var item = conversionItems[index]
            item.status = status
            if let error = error {
                item.errorMessage = error
            }
            conversionItems[index] = item

            if status == .completed {
                sendCompletionNotification(for: item)
            }

            if conversionItems.allSatisfy({
                $0.status == .completed || $0.status == .failed || $0.status == .cancelled
            }) {
                isConverting = false
            }
        }
    }

    private func sendCompletionNotification(for item: ConversionItem) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Conversion Completed")
        content.body = String(
            format: NSLocalizedString("%@ has been converted successfully.", comment: ""),
            item.sourceURL.lastPathComponent)
        content.sound = .default

        // Pour macOS, l'icône de l'application est automatiquement utilisée
        // Pas besoin de la définir explicitement

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func updateProgress(for itemID: UUID, progress: Double) {
        if let index = conversionItems.firstIndex(where: { $0.id == itemID }) {
            conversionItems[index].progress = progress
        }
    }
}
