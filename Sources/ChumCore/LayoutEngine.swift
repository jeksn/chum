import CoreGraphics

public enum LayoutEngine {
    public struct Request {
        public var usableArea: CGRect
        public var currentFrame: CGRect
        public var width: WindowDimension?
        public var height: WindowDimension?
        public var anchor: Anchor
        public var offsetX: WindowDimension
        public var offsetY: WindowDimension
        public var interGap: CGFloat

        public init(
            usableArea: CGRect,
            currentFrame: CGRect,
            width: WindowDimension?,
            height: WindowDimension?,
            anchor: Anchor,
            offsetX: WindowDimension,
            offsetY: WindowDimension,
            interGap: CGFloat = 0
        ) {
            self.usableArea = usableArea
            self.currentFrame = currentFrame
            self.width = width
            self.height = height
            self.anchor = anchor
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.interGap = interGap
        }
    }

    public static func frame(for request: Request) -> CGRect {
        let area = request.usableArea
        let gap = request.interGap

        let rawWidth = max(0, resolve(request.width, axisLength: area.width, fallback: request.currentFrame.width))
        let rawHeight = max(0, resolve(request.height, axisLength: area.height, fallback: request.currentFrame.height))

        let isFullWidth = rawWidth >= area.width
        let isFullHeight = rawHeight >= area.height

        let halfGap = gap / 2

        let adjustedWidth: CGFloat
        switch request.anchor.horizontal {
        case .left, .right, .center:
            adjustedWidth = (isFullWidth || request.width == nil) ? rawWidth : max(0, rawWidth - halfGap)
        case .keep:
            adjustedWidth = rawWidth
        }

        let adjustedHeight: CGFloat
        switch request.anchor.vertical {
        case .top, .bottom, .center:
            adjustedHeight = (isFullHeight || request.height == nil) ? rawHeight : max(0, rawHeight - halfGap)
        case .keep:
            adjustedHeight = rawHeight
        }

        let baseX: CGFloat
        switch request.anchor.horizontal {
        case .left: baseX = area.minX
        case .center: baseX = area.midX - adjustedWidth / 2
        case .right: baseX = area.maxX - adjustedWidth
        case .keep: baseX = request.currentFrame.minX
        }

        let baseY: CGFloat
        switch request.anchor.vertical {
        case .top: baseY = area.maxY - adjustedHeight
        case .center: baseY = area.midY - adjustedHeight / 2
        case .bottom: baseY = area.minY
        case .keep: baseY = request.currentFrame.minY
        }

        let x = baseX + resolve(request.offsetX, axisLength: area.width, fallback: 0)
        let y = baseY - resolve(request.offsetY, axisLength: area.height, fallback: 0)

        return CGRect(x: x, y: y, width: adjustedWidth, height: adjustedHeight)
    }

    public static func usableArea(in visibleFrame: CGRect, gap: CGFloat) -> CGRect {
        guard gap > 0 else { return visibleFrame }
        return visibleFrame.insetBy(dx: gap, dy: gap)
    }

    public static func frameForNextDisplay(
        currentFrame: CGRect,
        currentUsable: CGRect,
        nextUsable: CGRect
    ) -> CGRect {
        guard currentUsable.width > 0, currentUsable.height > 0 else {
            return CGRect(x: nextUsable.minX, y: nextUsable.minY, width: currentFrame.width, height: currentFrame.height)
        }
        let relX = (currentFrame.minX - currentUsable.minX) / currentUsable.width
        let relY = (currentFrame.minY - currentUsable.minY) / currentUsable.height
        let newX = nextUsable.minX + relX * nextUsable.width
        let newY = nextUsable.minY + relY * nextUsable.height
        return CGRect(x: newX, y: newY, width: currentFrame.width, height: currentFrame.height)
    }

    private static func resolve(_ dimension: WindowDimension?, axisLength: CGFloat, fallback: CGFloat) -> CGFloat {
        switch dimension {
        case .percent(let value): return axisLength * value / 100
        case .points(let value): return value
        case nil: return fallback
        }
    }
}
