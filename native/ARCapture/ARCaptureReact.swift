import Foundation
import React
import UIKit

@objc(ARCaptureEngine)
final class ARCaptureEngine: RCTEventEmitter {
    private var listening = false
    override init() {
        super.init()
        ARCaptureCoordinator.shared.onStatus = { [weak self] status in
            guard let self, self.listening else { return }
            self.sendEvent(withName: "ARCaptureStatus", body: status)
        }
    }
    @objc override static func requiresMainQueueSetup() -> Bool { true }
    override func supportedEvents() -> [String]! { ["ARCaptureStatus"] }
    override func startObserving() { listening = true }
    override func stopObserving() { listening = false }

    private func complete(_ result: Result<[String: Any], Error>, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            switch result {
            case .success(let value): resolve(value)
            case .failure(let error): reject("AR_CAPTURE_ERROR", error.localizedDescription, error)
            }
        }
    }
    @objc(startSession:resolver:rejecter:)
    func startSession(_ name: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.startSession(name: name) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(stopSession:rejecter:)
    func stopSession(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.stopSession { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(getStatus:rejecter:)
    func getStatus(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.getStatus { value in DispatchQueue.main.async { resolve(value) } }
    }
    @objc(addBookmark:resolver:rejecter:)
    func addBookmark(_ note: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.addBookmark(note: note) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(clearMeasurements:rejecter:)
    func clearMeasurements(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.clearMeasurements { value in DispatchQueue.main.async { resolve(value) } }
    }
    @objc(resetTracking:rejecter:)
    func resetTracking(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.resetTracking { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(setPreviewMode:resolver:rejecter:)
    func setPreviewMode(_ mode: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.setPreviewMode(mode) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(listSessions:rejecter:)
    func listSessions(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.listSessions { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sessions): resolve(sessions)
                case .failure(let error): reject("AR_CAPTURE_ERROR", error.localizedDescription, error)
                }
            }
        }
    }
    @objc(exportSession:resolver:rejecter:)
    func exportSession(_ id: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.exportSession(id: id) { self.complete($0, resolve: resolve, reject: reject) }
    }
}

@objc(ARCaptureViewManager)
final class ARCaptureViewManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }
    override func view() -> UIView! { ARCaptureView(frame: .zero) }
}
