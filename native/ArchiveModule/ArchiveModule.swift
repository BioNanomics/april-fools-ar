import Foundation
import AVFoundation
import React

@objc(ArchiveModule)
final class ArchiveModule: NSObject {
    private let archiveQueue = DispatchQueue(label: "com.aprilfoolsar.session-archive", qos: .utility)
    // All presentation state is confined to the main queue.
    private let recordingPreview = RecordingPreview()

    @objc static func requiresMainQueueSetup() -> Bool { false }

    @objc(archiveSession:resolver:rejecter:)
    func archiveSession(_ folderPath: String,
                        resolver resolve: @escaping RCTPromiseResolveBlock,
                        rejecter reject: @escaping RCTPromiseRejectBlock) {
        archiveQueue.async {
            do {
                let archive = try SavedRecordingStore.shared.prepare(folderPath: folderPath)
                resolve(Self.descriptor(archive))
            } catch {
                reject("session_export_failed", error.localizedDescription, error)
            }
        }
    }

    @objc(previewSession:resolver:rejecter:)
    func previewSession(_ folderPath: String,
                        resolver resolve: @escaping RCTPromiseResolveBlock,
                        rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            do {
                try self.recordingPreview.beginPreparation()
            } catch {
                reject("session_preview_failed", error.localizedDescription, error)
                return
            }
            self.archiveQueue.async {
                do {
                    let recording = try SavedRecordingStore.shared.prepare(folderPath: folderPath)
                    guard FileManager.default.isReadableFile(atPath: recording.url.path) else {
                        throw RecordingPreview.PreviewError.missingRecording
                    }
                    let asset = AVURLAsset(url: recording.url)
                    Task {
                        do {
                            guard try await asset.load(.isPlayable) else {
                                throw RecordingPreview.PreviewError.unplayableRecording
                            }
                            DispatchQueue.main.async {
                                do {
                                    try self.recordingPreview.present(asset: asset) {
                                        resolve(Self.descriptor(recording))
                                    }
                                } catch {
                                    self.recordingPreview.cancelPreparation()
                                    reject("session_preview_failed", error.localizedDescription, error)
                                }
                            }
                        } catch {
                            self.rejectPreview(error, reject: reject)
                        }
                    }
                } catch {
                    self.rejectPreview(error, reject: reject)
                }
            }
        }
    }

    private func rejectPreview(_ error: Error, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            self.recordingPreview.cancelPreparation()
            reject("session_preview_failed", error.localizedDescription, error)
        }
    }

    private static func descriptor(_ recording: SessionMP4Writer.Result) -> [String: Any] {
        ["url": recording.url.absoluteString, "path": recording.url.path,
         "bytes": NSNumber(value: recording.bytes), "format": "mp4", "mimeType": "video/mp4"]
    }
}
