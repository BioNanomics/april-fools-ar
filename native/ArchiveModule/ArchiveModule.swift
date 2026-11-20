import Foundation
import React

@objc(ArchiveModule)
final class ArchiveModule: NSObject {
    private let archiveQueue = DispatchQueue(label: "com.aprilfoolsar.session-archive", qos: .utility)

    @objc static func requiresMainQueueSetup() -> Bool { false }

    @objc(archiveSession:resolver:rejecter:)
    func archiveSession(_ folderPath: String,
                        resolver resolve: @escaping RCTPromiseResolveBlock,
                        rejecter reject: @escaping RCTPromiseRejectBlock) {
        archiveQueue.async {
            do {
                let fileManager = FileManager.default
                let documents = try fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
                let sessions = documents.appendingPathComponent("AprilFoolsAR/sessions", isDirectory: true)
                let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
                let exports = caches.appendingPathComponent("AprilFoolsAR/exports", isDirectory: true)
                let archive = try SessionZIPWriter().archiveSession(
                    folderPath: folderPath, allowedSessionsRoot: sessions, destinationDirectory: exports)
                resolve(["url": archive.url.absoluteString, "path": archive.url.path,
                         "bytes": NSNumber(value: archive.bytes)])
            } catch {
                reject("session_archive_failed", error.localizedDescription, error)
            }
        }
    }
}
