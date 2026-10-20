import CoreGraphics
import TrastCore

enum LayoutEngineTests {
    static func runAll(_ t: TestRunner) {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 700)

        func frame(
            width: WindowDimension?,
            height: WindowDimension?,
            anchor: Anchor,
            offsetX: WindowDimension = .percent(0),
            offsetY: WindowDimension = .percent(0),
            usable: CGRect? = nil,
            current: CGRect = .zero
        ) -> CGRect {
            LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable ?? area,
                currentFrame: current,
                width: width,
                height: height,
                anchor: anchor,
                offsetX: offsetX,
                offsetY: offsetY
            ))
        }

        t.run("LayoutEngine.leftHalf") {
            let result = frame(width: .percent(50), height: .percent(100), anchor: .topLeft)
            t.check(result == CGRect(x: 0, y: 0, width: 500, height: 700), "got \(result)")
        }

        t.run("LayoutEngine.rightHalf") {
            let result = frame(width: .percent(50), height: .percent(100), anchor: .topRight)
            t.check(result == CGRect(x: 500, y: 0, width: 500, height: 700), "got \(result)")
        }

        t.run("LayoutEngine.centerPercent") {
            let result = frame(width: .percent(60), height: .percent(60), anchor: .center)
            t.check(result == CGRect(x: 200, y: 140, width: 600, height: 420), "got \(result)")
        }

        t.run("LayoutEngine.pointsSize") {
            let result = frame(width: .points(400), height: .points(300), anchor: .topLeft)
            t.check(result == CGRect(x: 0, y: 400, width: 400, height: 300), "got \(result)")
        }

        t.run("LayoutEngine.negativePercentOffsetShiftsLeft") {
            let result = frame(width: .percent(50), height: .percent(100), anchor: .topLeft, offsetX: .percent(-10))
            t.check(result == CGRect(x: -100, y: 0, width: 500, height: 700), "got \(result)")
        }

        t.run("LayoutEngine.positivePointsOffsets") {
            let result = frame(width: .percent(50), height: .percent(100), anchor: .topLeft, offsetX: .points(25), offsetY: .points(10))
            t.check(result == CGRect(x: 25, y: -10, width: 500, height: 700), "got \(result)")
        }

        t.run("LayoutEngine.bottomAnchor") {
            let result = frame(width: .percent(100), height: .percent(50), anchor: .bottomLeft)
            t.check(result == CGRect(x: 0, y: 0, width: 1000, height: 350), "got \(result)")
        }

        t.run("LayoutEngine.middleLeftAnchor") {
            let result = frame(width: .percent(50), height: .percent(50), anchor: .middleLeft)
            t.check(result == CGRect(x: 0, y: 175, width: 500, height: 350), "got \(result)")
        }

        t.run("LayoutEngine.keepsCurrentSizeWhenNil") {
            let current = CGRect(x: 100, y: 100, width: 300, height: 200)
            let result = frame(width: nil, height: nil, anchor: .center, current: current)
            t.check(result.width == 300, "width \(result.width)")
            t.check(result.height == 200, "height \(result.height)")
            t.check(result.midX == 500, "midX \(result.midX)")
            t.check(result.midY == 350, "midY \(result.midY)")
        }

        t.run("LayoutEngine.gapInsetsUsableArea") {
            t.check(LayoutEngine.usableArea(in: area, gap: 10) == CGRect(x: 10, y: 10, width: 980, height: 680), "gap inset mismatch")
        }

        t.run("LayoutEngine.percentSizesRelativeToGapInsetArea") {
            let usable = LayoutEngine.usableArea(in: area, gap: 10)
            let result = frame(width: .percent(50), height: .percent(100), anchor: .topLeft, usable: usable)
            t.check(result == CGRect(x: 10, y: 10, width: 490, height: 680), "got \(result)")
        }

        t.run("LayoutEngine.zeroGapReturnsVisibleFrameUnchanged") {
            t.check(LayoutEngine.usableArea(in: area, gap: 0) == area, "zero gap changed the frame")
        }

        t.run("LayoutEngine.negativeSizeClampedToZero") {
            t.check(frame(width: .points(-50), height: .percent(50), anchor: .topLeft).width == 0, "negative width not clamped")
        }

        t.run("LayoutEngine.offsetBeyondScreenIsAllowed") {
            t.check(frame(width: .percent(50), height: .percent(100), anchor: .topLeft, offsetX: .percent(100)).minX == 1000, "offset clamped unexpectedly")
        }

        t.run("LayoutEngine.moveLeftKeepsVerticalPosition") {
            let current = CGRect(x: 100, y: 200, width: 300, height: 150)
            let result = frame(width: nil, height: nil, anchor: .moveLeft, current: current)
            t.check(result == CGRect(x: 0, y: 200, width: 300, height: 150), "got \(result)")
        }

        t.run("LayoutEngine.moveRightKeepsVerticalPosition") {
            let current = CGRect(x: 100, y: 200, width: 300, height: 150)
            let result = frame(width: nil, height: nil, anchor: .moveRight, current: current)
            t.check(result == CGRect(x: 700, y: 200, width: 300, height: 150), "got \(result)")
        }

        t.run("LayoutEngine.moveUpKeepsHorizontalPosition") {
            let current = CGRect(x: 100, y: 200, width: 300, height: 150)
            let result = frame(width: nil, height: nil, anchor: .moveUp, current: current)
            t.check(result == CGRect(x: 100, y: 550, width: 300, height: 150), "got \(result)")
        }

        t.run("LayoutEngine.moveDownKeepsHorizontalPosition") {
            let current = CGRect(x: 100, y: 200, width: 300, height: 150)
            let result = frame(width: nil, height: nil, anchor: .moveDown, current: current)
            t.check(result == CGRect(x: 100, y: 0, width: 300, height: 150), "got \(result)")
        }

        t.run("LayoutEngine.keepHorizontalWithResizing") {
            let current = CGRect(x: 100, y: 200, width: 300, height: 150)
            let result = frame(width: .percent(50), height: nil, anchor: Anchor(horizontal: .keep, vertical: .keep), current: current)
            t.check(result == CGRect(x: 100, y: 200, width: 500, height: 150), "got \(result)")
        }

        t.run("LayoutEngine.nextDisplayPreservesRelativePosition") {
            let current = CGRect(x: 0, y: 0, width: 1000, height: 700)
            let next = CGRect(x: 1000, y: 0, width: 2000, height: 1400)
            let window = CGRect(x: 0, y: 350, width: 500, height: 350)
            let result = LayoutEngine.frameForNextDisplay(currentFrame: window, currentUsable: current, nextUsable: next)
            t.check(result == CGRect(x: 1000, y: 700, width: 500, height: 350), "got \(result)")
        }

        t.run("LayoutEngine.nextDisplayPreservesSize") {
            let current = CGRect(x: 0, y: 0, width: 1000, height: 700)
            let next = CGRect(x: 1000, y: 0, width: 1000, height: 700)
            let window = CGRect(x: 100, y: 100, width: 300, height: 200)
            let result = LayoutEngine.frameForNextDisplay(currentFrame: window, currentUsable: current, nextUsable: next)
            t.check(result.width == 300, "width \(result.width)")
            t.check(result.height == 200, "height \(result.height)")
        }

        t.run("LayoutEngine.nextDisplaySameSizeScreensPreservesPosition") {
            let current = CGRect(x: 0, y: 0, width: 1000, height: 700)
            let next = CGRect(x: 1000, y: 0, width: 1000, height: 700)
            let window = CGRect(x: 250, y: 175, width: 500, height: 350)
            let result = LayoutEngine.frameForNextDisplay(currentFrame: window, currentUsable: current, nextUsable: next)
            t.check(result == CGRect(x: 1250, y: 175, width: 500, height: 350), "got \(result)")
        }

        t.run("LayoutEngine.nextDisplayZeroSizeCurrentFallsBackToOrigin") {
            let current = CGRect.zero
            let next = CGRect(x: 1000, y: 0, width: 1000, height: 700)
            let window = CGRect(x: 0, y: 0, width: 300, height: 200)
            let result = LayoutEngine.frameForNextDisplay(currentFrame: window, currentUsable: current, nextUsable: next)
            t.check(result == CGRect(x: 1000, y: 0, width: 300, height: 200), "got \(result)")
        }

        func frameWithGap(
            width: WindowDimension?,
            height: WindowDimension?,
            anchor: Anchor,
            gap: CGFloat,
            offsetX: WindowDimension = .percent(0),
            offsetY: WindowDimension = .percent(0),
            usable: CGRect? = nil,
            current: CGRect = .zero
        ) -> CGRect {
            LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable ?? area,
                currentFrame: current,
                width: width,
                height: height,
                anchor: anchor,
                offsetX: offsetX,
                offsetY: offsetY,
                interGap: gap
            ))
        }

        t.run("LayoutEngine.interGapLeftHalf") {
            let result = frameWithGap(width: .percent(50), height: .percent(100), anchor: .topLeft, gap: 10)
            t.check(result == CGRect(x: 0, y: 0, width: 495, height: 700), "got \(result)")
        }

        t.run("LayoutEngine.interGapRightHalf") {
            let result = frameWithGap(width: .percent(50), height: .percent(100), anchor: .topRight, gap: 10)
            t.check(result == CGRect(x: 505, y: 0, width: 495, height: 700), "got \(result)")
        }

        t.run("LayoutEngine.interGapCenter") {
            let result = frameWithGap(width: .percent(50), height: .percent(50), anchor: .center, gap: 10)
            t.check(result == CGRect(x: 252.5, y: 177.5, width: 495, height: 345), "got \(result)")
        }

        t.run("LayoutEngine.interGapKeepAnchorNoShrink") {
            let current = CGRect(x: 100, y: 200, width: 300, height: 150)
            let result = frameWithGap(width: nil, height: nil, anchor: .moveLeft, gap: 10, current: current)
            t.check(result == CGRect(x: 0, y: 200, width: 300, height: 150), "keep anchor should not shrink with gap")
        }

        t.run("LayoutEngine.interGapZeroMatchesNoGap") {
            let result = frameWithGap(width: .percent(50), height: .percent(100), anchor: .topLeft, gap: 0)
            t.check(result == CGRect(x: 0, y: 0, width: 500, height: 700), "zero gap should match no-gap behavior")
        }

        t.run("LayoutEngine.interGapTopLeftQuarter") {
            let result = frameWithGap(width: .percent(50), height: .percent(50), anchor: .topLeft, gap: 10)
            t.check(result == CGRect(x: 0, y: 355, width: 495, height: 345), "got \(result)")
        }

        t.run("LayoutEngine.interGapBottomLeftQuarter") {
            let result = frameWithGap(width: .percent(50), height: .percent(50), anchor: .bottomLeft, gap: 10)
            t.check(result == CGRect(x: 0, y: 0, width: 495, height: 345), "got \(result)")
        }

        t.run("LayoutEngine.interGapVerticalGapBetweenQuarters") {
            let top = frameWithGap(width: .percent(50), height: .percent(50), anchor: .topLeft, gap: 10)
            let bottom = frameWithGap(width: .percent(50), height: .percent(50), anchor: .bottomLeft, gap: 10)
            let gapBetween = top.minY - bottom.maxY
            t.check(gapBetween == 10, "vertical gap between top and bottom quarters should be 10, got \(gapBetween)")
        }

        t.run("LayoutEngine.interGapHorizontalGapBetweenQuarters") {
            let left = frameWithGap(width: .percent(50), height: .percent(50), anchor: .topLeft, gap: 10)
            let right = frameWithGap(width: .percent(50), height: .percent(50), anchor: .topRight, gap: 10)
            let gapBetween = right.minX - left.maxX
            t.check(gapBetween == 10, "horizontal gap between left and right quarters should be 10, got \(gapBetween)")
        }

        t.run("LayoutEngine.interGapVerticalGapBetweenRightQuarters") {
            let top = frameWithGap(width: .percent(50), height: .percent(50), anchor: .topRight, gap: 10)
            let bottom = frameWithGap(width: .percent(50), height: .percent(50), anchor: .bottomRight, gap: 10)
            let gapBetween = top.minY - bottom.maxY
            t.check(gapBetween == 10, "vertical gap between top right and bottom right quarters should be 10, got \(gapBetween)")
        }

        t.run("LayoutEngine.interGapWithUsableAreaMatchesEdgeGap") {
            let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
            let gap: CGFloat = 10
            let usable = LayoutEngine.usableArea(in: screen, gap: gap)

            let topLeft = LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable, currentFrame: .zero,
                width: .percent(50), height: .percent(50), anchor: .topLeft,
                offsetX: .percent(0), offsetY: .percent(0), interGap: gap
            ))
            let bottomLeft = LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable, currentFrame: .zero,
                width: .percent(50), height: .percent(50), anchor: .bottomLeft,
                offsetX: .percent(0), offsetY: .percent(0), interGap: gap
            ))
            let topRight = LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable, currentFrame: .zero,
                width: .percent(50), height: .percent(50), anchor: .topRight,
                offsetX: .percent(0), offsetY: .percent(0), interGap: gap
            ))
            let bottomRight = LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable, currentFrame: .zero,
                width: .percent(50), height: .percent(50), anchor: .bottomRight,
                offsetX: .percent(0), offsetY: .percent(0), interGap: gap
            ))

            let edgeLeft = topLeft.minX - screen.minX
            let edgeRight = screen.maxX - topRight.maxX
            let edgeTop = screen.maxY - topLeft.maxY
            let edgeBottom = bottomLeft.minY - screen.minY
            let gapVLeft = topLeft.minY - bottomLeft.maxY
            let gapVRight = topRight.minY - bottomRight.maxY
            let gapHTop = topRight.minX - topLeft.maxX
            let gapHBottom = bottomRight.minX - bottomLeft.maxX

            t.check(edgeLeft == gap, "left edge gap \(edgeLeft) != \(gap)")
            t.check(edgeRight == gap, "right edge gap \(edgeRight) != \(gap)")
            t.check(edgeTop == gap, "top edge gap \(edgeTop) != \(gap)")
            t.check(edgeBottom == gap, "bottom edge gap \(edgeBottom) != \(gap)")
            t.check(gapVLeft == gap, "vertical gap left \(gapVLeft) != \(gap)")
            t.check(gapVRight == gap, "vertical gap right \(gapVRight) != \(gap)")
            t.check(gapHTop == gap, "horizontal gap top \(gapHTop) != \(gap)")
            t.check(gapHBottom == gap, "horizontal gap bottom \(gapHBottom) != \(gap)")
        }
        t.run("LayoutEngine.clampedSizeReanchors") {
            let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
            let gap: CGFloat = 10
            let usable = LayoutEngine.usableArea(in: screen, gap: gap)

            func correctedFrame(actual: CGRect, anchor: Anchor) -> CGRect {
                LayoutEngine.frame(for: LayoutEngine.Request(
                    usableArea: usable,
                    currentFrame: actual,
                    width: .points(actual.width),
                    height: .points(actual.height),
                    anchor: anchor,
                    offsetX: .percent(0),
                    offsetY: .percent(0)
                ))
            }

            let rightThird = LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable, currentFrame: .zero,
                width: .percent(100.0 / 3.0), height: .percent(100),
                anchor: .topRight,
                offsetX: .percent(0), offsetY: .percent(0), interGap: gap
            ))
            // The app clamps the 1/3 width to 400; the position must be
            // recomputed so the anchored edge stays at the margin.
            let clampedRight = correctedFrame(actual: CGRect(origin: rightThird.origin, size: CGSize(width: 400, height: 680)), anchor: .topRight)
            t.check(clampedRight.width == 400 && clampedRight.height == 680, "clamped size should be preserved, got \(clampedRight)")
            t.check(clampedRight.maxX == usable.maxX, "right-anchored clamp should keep its right edge at the margin, got \(clampedRight)")

            let clampedLeft = correctedFrame(actual: CGRect(x: 0, y: 0, width: 400, height: 680), anchor: .topLeft)
            t.check(clampedLeft.minX == usable.minX, "left-anchored clamp should keep its left edge at the margin, got \(clampedLeft)")
        }
    }
}
