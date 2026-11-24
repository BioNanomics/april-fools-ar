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
        ARCaptureCoordinator.shared.onTagSelected = { [weak self] id in
            guard let self, self.listening else { return }
            self.sendEvent(withName: "ARCaptureTagSelected", body: ["id": id])
        }
    }
    @objc override static func requiresMainQueueSetup() -> Bool { true }
    override func supportedEvents() -> [String]! { ["ARCaptureStatus", "ARCaptureTagSelected"] }
    override func startObserving() { listening = true }
    override func stopObserving() { listening = false }

    @objc(getAppInfo:rejecter:)
    func getAppInfo(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async { resolve(AppBuildInfo.info) }
    }

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
    @objc(getFieldCatalog:rejecter:)
    func getFieldCatalog(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.getFieldCatalog { value in DispatchQueue.main.async { resolve(value) } }
    }
    @objc(getFieldDefinition:resolver:rejecter:)
    func getFieldDefinition(_ id: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.getFieldDefinition(id) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(selectField:resolver:rejecter:)
    func selectField(_ id: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.selectField(id) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(importFieldDefinition:resolver:rejecter:)
    func importFieldDefinition(_ text: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.selectField("", importedText: text) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(getFieldWalk:rejecter:)
    func getFieldWalk(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.getFieldWalk { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(getSavedFieldWalk:resolver:rejecter:)
    func getSavedFieldWalk(_ id: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.getSavedFieldWalk(id) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(clearFieldAlignment:rejecter:)
    func clearFieldAlignment(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.fieldAlignmentAction("clear") { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(recheckFieldAlignment:rejecter:)
    func recheckFieldAlignment(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.fieldAlignmentAction("recheck") { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(alignFieldUnverified:rejecter:)
    func alignFieldUnverified(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.fieldAlignmentAction("manual") { self.complete($0, resolve: resolve, reject: reject) }
    }

    @objc(getDebugSettings:rejecter:)
    func getDebugSettings(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.getDebugSettings { value in DispatchQueue.main.async { resolve(value) } }
    }
    @objc(setDebugSettings:resolver:rejecter:)
    func setDebugSettings(_ changes: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let changes = changes as? [String: Any] else { reject("AR_CAPTURE_ERROR", "Settings must be a dictionary.", nil); return }
        ARCaptureCoordinator.shared.setDebugSettings(changes) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(setDebugMode:resolver:rejecter:)
    func setDebugMode(_ enabled: Bool, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.setDebugMode(enabled) { value in DispatchQueue.main.async { resolve(value) } }
    }
    @objc(applyMeasuredTagSize:rejecter:)
    func applyMeasuredTagSize(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.applyMeasuredTagSize { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(addBookmark:resolver:rejecter:)
    func addBookmark(_ note: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.addBookmark(note: note) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(clearMeasurements:rejecter:)
    func clearMeasurements(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.clearMeasurements { value in DispatchQueue.main.async { resolve(value) } }
    }
    @objc(setSpatialMode:resolver:rejecter:)
    func setSpatialMode(_ mode: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.setSpatialMode(mode) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(completeFloorSetup:resolver:rejecter:)
    func completeFloorSetup(_ candidateID: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.completeFloorSetup(candidateID) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(setFloorVisible:resolver:rejecter:)
    func setFloorVisible(_ visible: Bool, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.setFloorVisible(visible) { value in DispatchQueue.main.async { resolve(value) } }
    }
    @objc(resetTracking:rejecter:)
    func resetTracking(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.resetTracking { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(setPreviewMode:resolver:rejecter:)
    func setPreviewMode(_ mode: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.setPreviewMode(mode) { self.complete($0, resolve: resolve, reject: reject) }
    }
    @objc(setDisplayZoom:resolver:rejecter:)
    func setDisplayZoom(_ zoom: Double, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.setDisplayZoom(zoom) { self.complete($0, resolve: resolve, reject: reject) }
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
    @objc(deleteSession:resolver:rejecter:)
    func deleteSession(_ id: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        ARCaptureCoordinator.shared.deleteSession(id: id) { self.complete($0, resolve: resolve, reject: reject) }
    }
}

@objc(ARCaptureViewManager)
final class ARCaptureViewManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }
    override func view() -> UIView! { ARCaptureView(frame: .zero) }
}

@objc(ARCaptureReadoutViewManager)
final class ARCaptureReadoutViewManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }
    override func view() -> UIView! {
        let view = ARCaptureReadoutView(frame: .zero)
        view.onWindowAttachmentChanged = { readout, attached in
            if attached { ARCaptureCoordinator.shared.attachReadout(readout) }
            else { ARCaptureCoordinator.shared.detachReadout(readout) }
        }
        return view
    }
}
