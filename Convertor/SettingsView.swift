import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var showFileImporter = false
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Form {
                Picker(
                    String(localized: "Default Output Format"),
                    selection: $settings.defaultOutputFormat
                ) {
                    ForEach(OutputFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }

                Picker(String(localized: "Audio Quality"), selection: $settings.audioQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.name).tag(quality)
                    }
                }

                Stepper(
                    String(
                        format: NSLocalizedString("Maximum Concurrent Tasks: %d", comment: ""),
                        settings.maxConcurrentTasks), value: $settings.maxConcurrentTasks,
                    in: 1...16)

                LabeledContent {
                    Text(
                        settings.outputDirectory?.lastPathComponent
                            ?? String(localized: "Documents"))
                    Button(String(localized: "Select...")) {
                        showFileImporter = true
                    }
                } label: {
                    Text(String(localized: "Output Directory"))
                }
            }
            HStack {
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()
        }
        .padding()
        .frame(width: 400)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                settings.outputDirectory = urls.first
            case .failure(let error):
                print("Error selecting output directory: \(error.localizedDescription)")
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: Settings())
    }
}
