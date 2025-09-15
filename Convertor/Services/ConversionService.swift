import Combine
import Foundation

enum ConversionError: Error, LocalizedError {
    case ffmpegNotFound
    case ffmpegNotExecutable
    case inputFileDoesNotExist
    case inputFileNotReadable
    case cannotCreateOutputDirectory(Error)
    case outputDirectoryNotAccessible
    case ffmpegProcessFailed(Int32, String)
    case ffmpegProcessStartFailed(Error)
    case durationParsingFailed

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound: return String(localized: "FFmpeg executable not found.")
        case .ffmpegNotExecutable: return String(localized: "FFmpeg executable is not executable.")
        case .inputFileDoesNotExist: return String(localized: "Input file does not exist.")
        case .inputFileNotReadable: return String(localized: "Input file is not readable.")
        case .cannotCreateOutputDirectory(let error):
            return String(localized: "Cannot create output directory: ")
                + error.localizedDescription
        case .outputDirectoryNotAccessible:
            return String(localized: "Output directory is not accessible. Please select a different directory in settings.")
        case .ffmpegProcessFailed(let code, let stderr):
            return String(
                format: NSLocalizedString(
                    "FFmpeg process failed with exit code %d: \n%@", comment: ""), code, stderr)
        case .ffmpegProcessStartFailed(let error):
            return String(localized: "Failed to start FFmpeg process: ")
                + error.localizedDescription
        case .durationParsingFailed: return String(localized: "Could not parse media duration.")
        }
    }
}

class ConversionService {

    func convert(
        fileURL: URL, to outputFormat: OutputFormat, quality: AudioQuality, outputDirectory: URL?,
        progressHandler: @escaping (Double) -> Void
    ) -> AnyPublisher<URL, Error> {
        Future<URL, Error> { promise in
            Task {
                do {
                    guard let ffmpegURL = Bundle.main.url(forResource: "ffmpeg", withExtension: nil)
                    else {
                        promise(.failure(ConversionError.ffmpegNotFound))
                        return
                    }

                    guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
                        promise(.failure(ConversionError.ffmpegNotExecutable))
                        return
                    }

                    guard FileManager.default.fileExists(atPath: fileURL.path) else {
                        promise(.failure(ConversionError.inputFileDoesNotExist))
                        return
                    }

                    guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
                        promise(.failure(ConversionError.inputFileNotReadable))
                        return
                    }

                    let outputURL = self.getOutputURL(
                        for: fileURL, outputFormat: outputFormat, outputDirectory: outputDirectory)
                    let outputDir = outputURL.deletingLastPathComponent()

                    print("📂 Output directory: \(outputDir.path)")
                    print("📄 Output file: \(outputURL.path)")

                    // Start accessing security scoped resources
                    let inputDidStartAccessing = fileURL.startAccessingSecurityScopedResource()
                    let outputDidStartAccessing = outputDir.startAccessingSecurityScopedResource()
                    defer {
                        if inputDidStartAccessing {
                            fileURL.stopAccessingSecurityScopedResource()
                        }
                        if outputDidStartAccessing {
                            outputDir.stopAccessingSecurityScopedResource()
                        }
                    }

                    // Check if output directory is accessible
                    if !FileManager.default.isWritableFile(atPath: outputDir.path) {
                        print("❌ ERROR: Output directory not writable: \(outputDir.path)")
                        throw ConversionError.outputDirectoryNotAccessible
                    }
                    print("✅ Output directory is writable: \(outputDir.path)")

                    try FileManager.default.createDirectory(
                        at: outputDir, withIntermediateDirectories: true)

                    let duration = try await self.getDuration(for: fileURL, ffmpegURL: ffmpegURL)
                    let hasPicture = self.checkForAttachedPicture(in: fileURL, ffmpegURL: ffmpegURL)

                    var arguments: [String]
                    if hasPicture {
                        arguments = [
                            "-i", fileURL.path,
                            "-map_metadata", "0",
                            "-map", "0:a",
                            "-map", "0:v",
                            "-c:a", outputFormat == .aac ? "aac" : "alac",
                            "-c:v", "copy",
                            "-disposition:v", "attached_pic",
                        ]
                    } else {
                        arguments = [
                            "-i", fileURL.path,
                            "-map_metadata", "0",
                            "-vn",
                            "-c:a", outputFormat == .aac ? "aac" : "alac",
                        ]
                    }

                    if outputFormat == .aac && quality != .lossless {
                        arguments.append(contentsOf: ["-b:a", "\(quality.bitrate)k"])
                    }

                    arguments.append(contentsOf: ["-y", outputURL.path])

                    let process = Process()
                    process.executableURL = ffmpegURL
                    process.arguments = arguments

                    let errorPipe = Pipe()
                    process.standardError = errorPipe

                    let errorFileHandle = errorPipe.fileHandleForReading
                    errorFileHandle.readabilityHandler = { handle in
                        let data = handle.availableData
                        if let output = String(data: data, encoding: .utf8) {
                            if let progress = self.parseProgress(from: output, duration: duration) {
                                progressHandler(progress)
                            }
                        }
                    }

                     process.terminationHandler = { process in
                         errorFileHandle.readabilityHandler = nil
                         if process.terminationStatus == 0 {
                             // Vérifier si le fichier de sortie existe réellement
                             if FileManager.default.fileExists(atPath: outputURL.path) {
                                 print("✅ SUCCESS: Output file created at: \(outputURL.path)")
                                 let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                                 if let fileSize = attributes?[.size] as? Int64 {
                                     print("📁 File size: \(fileSize) bytes")
                                 }
                                 promise(.success(outputURL))
                             } else {
                                 print("❌ ERROR: FFmpeg reported success but output file not found at: \(outputURL.path)")
                                 // Lister le contenu du répertoire de sortie
                                 let outputDir = outputURL.deletingLastPathComponent()
                                 if let contents = try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil) {
                                     print("📂 Output directory contents: \(contents.map { $0.lastPathComponent })")
                                 }
                                 promise(.failure(ConversionError.ffmpegProcessFailed(0, "Output file not created")))
                             }
                         } else {
                             let errorData = errorFileHandle.readDataToEndOfFile()
                             let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                             print("❌ FFmpeg failed with exit code: \(process.terminationStatus)")
                             print("❌ FFmpeg error output: \(errorOutput)")
                             promise(
                                 .failure(
                                     ConversionError.ffmpegProcessFailed(
                                         process.terminationStatus, errorOutput)))
                         }
                     }

                    print("FFmpeg Path: \(ffmpegURL.path)")
                    print("FFmpeg Arguments: \(arguments.joined(separator: " "))")
                    process.launch()
                } catch {
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }

    private func getDuration(for fileURL: URL, ffmpegURL: URL) async throws -> Double {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-i", fileURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        let lines = errorOutput.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("Duration:") {
                let components = line.components(separatedBy: "Duration: ")
                if components.count > 1 {
                    let timeString = components[1].components(separatedBy: ",")[0]
                        .trimmingCharacters(in: .whitespaces)
                    let timeComponents = timeString.components(separatedBy: ":")
                    if timeComponents.count == 3 {
                        let hours = Double(timeComponents[0]) ?? 0
                        let minutes = Double(timeComponents[1]) ?? 0
                        let seconds = Double(timeComponents[2]) ?? 0
                        return hours * 3600 + minutes * 60 + seconds
                    }
                }
            }
        }

        throw ConversionError.durationParsingFailed
    }

    private nonisolated func parseProgress(from output: String, duration: Double) -> Double? {
        let lines = output.components(separatedBy: .init(charactersIn: "\r\n"))
        if let progressLine = lines.last(where: { $0.contains("time=") }) {
            let components = progressLine.components(separatedBy: "time=")
            if components.count > 1 {
                let timeString = components[1].components(separatedBy: " ")[0]
                let timeComponents = timeString.components(separatedBy: ":")
                if timeComponents.count == 3 {
                    let hours = Double(timeComponents[0]) ?? 0
                    let minutes = Double(timeComponents[1]) ?? 0
                    let seconds = Double(timeComponents[2]) ?? 0
                    let currentTime = hours * 3600 + minutes * 60 + seconds
                    if duration > 0 {
                        return min(max(currentTime / duration, 0), 1)
                    }
                }
            }
        }
        return nil
    }

    private nonisolated func checkForAttachedPicture(in inputURL: URL, ffmpegURL: URL) -> Bool {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-i", inputURL.path, "-map", "0:v?", "-f", "null", "-"]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if let errorData = try? errorPipe.fileHandleForReading.readToEnd(),
                let errorOutput = String(data: errorData, encoding: .utf8)
            {
                return errorOutput.contains("Stream #0:") && errorOutput.contains("Video:")
            }
        } catch {
            print("❌ ERROR: Cannot check for attached picture: \(error.localizedDescription)")
        }

        return false
    }

    private nonisolated func getOutputURL(for fileURL: URL, outputFormat: OutputFormat, outputDirectory: URL?)
        -> URL
    {
        let directory =
            outputDirectory ?? FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = outputFormat == .aac ? "m4a" : "m4a"
        return directory.appendingPathComponent("\(filename).\(fileExtension)")
    }
}
