import XCTest
import UIKit

/// Tests production geometry/overlay with ordinary UIView coordinates; no ARSession.
@MainActor
final class PreviewZoomUIKitTests: XCTestCase {
    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x,expected.x,accuracy:1e-8,file:file,line:line)
        XCTAssertEqual(actual.y,expected.y,accuracy:1e-8,file:file,line:line)
    }
    private func zoomedPixel(_ point: CGPoint, viewport: CGSize, zoom: Double) -> CGPoint {
        let normalized=CGPoint(x:point.x/viewport.width,y:point.y/viewport.height)
            .applying(PreviewZoom.normalizedTransform(for:zoom))
        return CGPoint(x:normalized.x*viewport.width,y:normalized.y*viewport.height)
    }

    func testCenteredPresetMappingAndInverseUseBothNonSquareViewportDimensions() {
        let portrait=CGSize(width:390,height:844)
        let portraitExpected:[CGPoint]=[CGPoint(x:240,y:400),CGPoint(x:285,y:378),CGPoint(x:375,y:334)]
        let landscape=CGSize(width:844,height:390)
        let landscapeExpected:[CGPoint]=[CGPoint(x:500,y:200),CGPoint(x:578,y:205),CGPoint(x:734,y:215)]
        for (index,zoom) in [1.0,2,4].enumerated() {
            assertPoint(zoomedPixel(CGPoint(x:240,y:400),viewport:portrait,zoom:zoom),portraitExpected[index])
            assertPoint(zoomedPixel(CGPoint(x:500,y:200),viewport:landscape,zoom:zoom),landscapeExpected[index])
            for viewport in [portrait,landscape] {
                let center=CGPoint(x:viewport.width/2,y:viewport.height/2)
                assertPoint(zoomedPixel(center,viewport:viewport,zoom:zoom),center)
                let transform=PreviewZoom.normalizedTransform(for:zoom)
                for original in [CGPoint(x:0,y:0),CGPoint(x:1,y:1),CGPoint(x:0.2,y:0.8)] {
                    assertPoint(original.applying(transform).applying(transform.inverted()),original)
                }
            }
        }
        // Zoom crops rather than clamping offscreen geometry to a plausible edge.
        assertPoint(CGPoint(x:0,y:0).applying(PreviewZoom.normalizedTransform(for:4)),CGPoint(x:-1.5,y:-1.5))
    }

    func testDisplayCompositionAppliesBaseBeforeCenteredZoom() {
        // An off-center affine fixture is intentionally noncommutative with zoom.
        let base=CGAffineTransform(a:0.8,b:0.1,c:-0.05,d:1.2,tx:0.11,ty:-0.07)
        let source=CGPoint(x:0.2,y:0.7)
        let expected=[CGPoint(x:0.235,y:0.79),CGPoint(x:-0.03,y:1.08),CGPoint(x:-0.56,y:1.66)]
        for (index,zoom) in [1.0,2,4].enumerated() {
            let transform=PreviewZoom.displayTransform(base:base,zoom:zoom)
            assertPoint(source.applying(transform),expected[index])
            assertPoint(expected[index].applying(transform.inverted()),source)
        }
    }

    func testFiniteClampingAndInvalidInputsNeverPropagateInvalidTransforms() throws {
        for (input,expected) in [(-20.0,1.0),(0,1),(1,1),(1.75,1.75),(2,2),(4,4),(100,4)] {
            XCTAssertEqual(try PreviewZoom.clamped(input),expected)
        }
        for input in [Double.nan,Double.infinity,-Double.infinity] {
            XCTAssertThrowsError(try PreviewZoom.clamped(input))
            XCTAssertEqual(PreviewZoom.normalizedTransform(for:input),.identity)
            let base=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:1,ty:0)
            XCTAssertEqual(PreviewZoom.displayTransform(base:base,zoom:input),base)
        }
        assertPoint(CGPoint(x:0.75,y:0.25).applying(PreviewZoom.normalizedTransform(for:100)),CGPoint(x:1.5,y:-0.5))
    }

    func testActualOverlaySelectionTracksDisplayedZoomInsteadOfRawPixelPosition() {
        let viewport=CGSize(width:390,height:844)
        let overlay=AprilTagOverlayView(frame:CGRect(origin:.zero,size:viewport))
        let corners=[[230,390],[250,390],[250,410],[230,410]].map { $0.map(NSNumber.init(value:)) }
        let detection:[String:Any]=["id":42,"corners":corners]
        let expectedCenters=[CGPoint(x:240,y:400),CGPoint(x:285,y:378),CGPoint(x:375,y:334)]
        for (index,zoom) in [1.0,2,4].enumerated() {
            overlay.show([detection],imageSize:viewport,
                         displayTransform:PreviewZoom.displayTransform(base:.identity,zoom:zoom),
                         frameID:"zoom-\(zoom)",expiresAt:ProcessInfo.processInfo.systemUptime+1)
            overlay.layoutIfNeeded()
            XCTAssertEqual(overlay.tagID(at:expectedCenters[index]),42)
            if zoom>1 { XCTAssertNil(overlay.tagID(at:CGPoint(x:240,y:400))) }
            XCTAssertEqual(overlay.bounds.size,viewport)
            XCTAssertEqual(overlay.transform,.identity,"Overlay uses projected coordinates, not a second view scale")
        }
        overlay.clear()
    }

    func testUIKitMeasurementCoordinatesUndoDisplayScaleBeforeBaseSensorMapping() {
        let base=CGAffineTransform(a:0,b:1.2,c:-0.8,d:0,tx:0.9,ty:-0.1)
        let originalSensor=CGPoint(x:0.45,y:0.55)
        // Independently calculated from the base fixture: (0.9-0.8*0.55,1.2*0.45-0.1).
        let originalViewNormalized=CGPoint(x:0.46,y:0.44)
        for viewport in [CGSize(width:390,height:844),CGSize(width:844,height:390)] {
            for zoom in [1.0,2,4] {
                let container=UIView(frame:CGRect(origin:.zero,size:viewport))
                container.clipsToBounds=true
                let camera=UIView(frame:container.bounds)
                container.addSubview(camera)
                camera.transform=CGAffineTransform(scaleX:zoom,y:zoom)
                let rawPoint=CGPoint(x:originalViewNormalized.x*viewport.width,y:originalViewNormalized.y*viewport.height)
                // Touch screen point based on independently known center + scale*(raw-center).
                let screenPoint=CGPoint(x:viewport.width/2+CGFloat(zoom)*(rawPoint.x-viewport.width/2),
                                        y:viewport.height/2+CGFloat(zoom)*(rawPoint.y-viewport.height/2))
                assertPoint(camera.convert(rawPoint,to:container),screenPoint)
                // UIGestureRecognizer.location(in: camera) uses this UIKit conversion.
                let localPoint=camera.convert(screenPoint,from:container)
                assertPoint(localPoint,rawPoint)
                let unzoomedNormalized=CGPoint(x:localPoint.x/viewport.width,y:localPoint.y/viewport.height)
                assertPoint(unzoomedNormalized.applying(base.inverted()),originalSensor)
                XCTAssertEqual(camera.bounds.size,viewport,"Display scale must not change the raw AR viewport")
                XCTAssertEqual(container.bounds.size,viewport)
            }
        }
    }
}
