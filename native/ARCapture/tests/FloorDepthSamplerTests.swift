import XCTest
import CoreVideo
import simd

final class FloorDepthSamplerTests: XCTestCase {
    private func buffer(_ format: OSType) -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, format,
            [kCVPixelBufferBytesPerRowAlignmentKey: 128] as CFDictionary, &result), kCVReturnSuccess)
        return result!
    }
    private func fill(_ depth: CVPixelBuffer, _ confidence: CVPixelBuffer, z: Float = 2, quality: UInt8 = 2) {
        CVPixelBufferLockBaseAddress(depth, []); CVPixelBufferLockBaseAddress(confidence, [])
        defer { CVPixelBufferUnlockBaseAddress(depth, []); CVPixelBufferUnlockBaseAddress(confidence, []) }
        for y in 0..<16 {
            let d = CVPixelBufferGetBaseAddress(depth)!.advanced(by: y * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)
            let c = CVPixelBufferGetBaseAddress(confidence)!.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<16 { d[x] = z; c[x] = quality }
        }
    }
    private var k: simd_float3x3 { simd_float3x3(columns: ([32, 0, 0], [0, 32, 0], [32, 32, 1])) }
    private var lookingDown: simd_float4x4 {
        simd_float4x4(columns: ([1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]))
    }
    private func floor(y: Float = -2, halfWidth: Float = 3) -> SpatialPlane {
        SpatialPlane(id: "floor", classification: "floor", origin: [0, y, 0], normal: [0, 1, 0],
            vertices: [[-halfWidth,y,-halfWidth],[halfWidth,y,-halfWidth],[halfWidth,y,halfWidth],[-halfWidth,y,halfWidth]],
            segmentID: "segment", frameID: "frame", timestamp: 1)
    }
    private func sample(_ depth: CVPixelBuffer, _ confidence: CVPixelBuffer?, plane: SpatialPlane? = nil, limit: Int = 512) -> [SIMD3<Float>] {
        FloorDepthSampler.samples(depth: depth, confidence: confidence, intrinsics: k, cameraToWorld: lookingDown,
            imageSize: CGSize(width: 64, height: 64), plane: plane ?? floor(), maximumCount: limit)
    }
    func testDepthUsesSourceIntrinsicsCameraTransformAndPaddedRows() {
        let depth = buffer(kCVPixelFormatType_DepthFloat32), confidence = buffer(kCVPixelFormatType_OneComponent8)
        fill(depth, confidence)
        let points = sample(depth, confidence)
        XCTAssertEqual(points.count, 256)
        XCTAssertEqual(points.first!.x, -1.875, accuracy: 1e-5)
        XCTAssertEqual(points.first!.y, -2, accuracy: 1e-5)
        XCTAssertEqual(points.first!.z, -1.875, accuracy: 1e-5)
        XCTAssertTrue(points.allSatisfy { abs($0.y + 2) < 1e-5 })
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(depth), 16 * 4)
        let limited = sample(depth, confidence, limit: 31)
        XCTAssertEqual(limited.count, 31)
        XCTAssertGreaterThan(limited.last!.z, 1.5, "Sampling must retain coverage beyond the first image rows")
    }
    func testRejectsMissingWeakInvalidAndUnrelatedSurfaceDepth() {
        let depth = buffer(kCVPixelFormatType_DepthFloat32), confidence = buffer(kCVPixelFormatType_OneComponent8)
        fill(depth, confidence)
        XCTAssertTrue(sample(depth, nil).isEmpty)
        for quality in [UInt8(0), 1, 3] {
            fill(depth, confidence, quality: quality)
            XCTAssertTrue(sample(depth, confidence).isEmpty)
        }
        for z in [Float(0), -1, 6, .nan, .infinity] {
            fill(depth, confidence, z: z)
            XCTAssertTrue(sample(depth, confidence).isEmpty)
        }
        fill(depth, confidence, z: 6)
        XCTAssertTrue(sample(depth, confidence, plane: floor(y: -6)).isEmpty)
        fill(depth, confidence)
        XCTAssertTrue(sample(depth, confidence, plane: floor(y: -1)).isEmpty)
        let cropped = sample(depth, confidence, plane: floor(halfWidth: 0.5))
        XCTAssertFalse(cropped.isEmpty)
        XCTAssertTrue(cropped.allSatisfy { abs($0.x) <= 0.5 && abs($0.z) <= 0.5 })
        XCTAssertLessThan(cropped.count, 256)
    }
}
