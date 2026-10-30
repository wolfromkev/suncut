import AppKit

/// Sunset sun cut by a pair of scissors.
/// Coordinates are top-left origin, y grows downward.
enum IconArtwork {
    private static let rayDegrees: [CGFloat] = [-75, -62.5, -50, -37.5, -25, -12.5, 0, 12.5, 25, 37.5, 50, 62.5, 75]

    /// How far each part reaches from the sun center, in sun radii. +y is down.
    private static let rayReach: CGFloat = 1.66
    private static let ringReach: CGFloat = 0.70
    private static let horizonReach: CGFloat = 1.32

    static func drawAppIcon(into context: CGContext, size: CGFloat, rounded: Bool) {
        context.saveGState()
        if rounded {
            let radius = size * 0.2237
            context.addPath(CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            ))
            context.clip()
        }
        drawBackground(into: context, size: size)
        drawMark(into: context, size: size, template: false)
        context.restoreGState()
    }

    /// Menu-bar mark. Drawn in black so it can be used as a template image.
    static func drawTemplate(into context: CGContext, size: CGFloat) {
        drawMark(into: context, size: size, template: true)
    }

    private static func drawMark(into context: CGContext, size: CGFloat, template: Bool) {
        let placed = placement(size: size, template: template)
        let center = placed.center
        let radius = placed.radius

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawRays(into: context, center: center, radius: radius, template: template)
        drawSun(into: context, center: center, radius: radius, template: template)
        drawHorizon(into: context, center: center, radius: radius, template: template)
        cutBlades(into: context, size: size, center: center, radius: radius, template: template)
        drawHandles(into: context, center: center, radius: radius, template: template)
        context.restoreGState()
    }

    private static func placement(size: CGFloat, template: Bool) -> (center: CGPoint, radius: CGFloat) {
        if !template {
            return (CGPoint(x: size * 0.5, y: size * 0.575), size * 0.30)
        }
        let pad = size * 0.05
        let avail = size - pad * 2
        let radius = min(avail / (horizonReach * 2), avail / (rayReach + ringReach))
        let boundsH = (rayReach + ringReach) * radius
        let centerY = (size - boundsH) / 2 + rayReach * radius
        return (CGPoint(x: size * 0.5, y: centerY), radius)
    }

    private static func drawBackground(into context: CGContext, size: CGFloat) {
        let colors = [
            color(0.31, 0.145, 0.24),
            color(0.16, 0.09, 0.24),
            color(0.07, 0.045, 0.24),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 0.48, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: 0, y: size),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func drawRays(into context: CGContext, center: CGPoint, radius: CGFloat, template: Bool) {
        let width = radius * (template ? 0.13 : 0.108)
        context.setLineWidth(width)
        for deg in rayDegrees {
            let angle = deg * .pi / 180
            let dir = CGVector(dx: sin(angle), dy: -cos(angle))
            let t = abs(deg) / 75
            let length = radius * (0.44 - 0.08 * t)
            let inner = radius * 1.09
            let outer = inner + length
            if template {
                context.setStrokeColor(gray: 0, alpha: 1)
            } else {
                context.setStrokeColor(rayColor(t))
            }
            context.move(to: CGPoint(x: center.x + dir.dx * inner, y: center.y + dir.dy * inner))
            context.addLine(to: CGPoint(x: center.x + dir.dx * outer, y: center.y + dir.dy * outer))
            context.strokePath()
        }
    }

    private static func drawSun(into context: CGContext, center: CGPoint, radius: CGFloat, template: Bool) {
        let sun = CGMutablePath()
        sun.addArc(center: center, radius: radius, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        sun.closeSubpath()
        if template {
            context.setFillColor(gray: 0, alpha: 1)
            context.addPath(sun)
            context.fillPath()
            return
        }
        let colors = [
            color(0.93, 0.43, 0.56),
            color(0.98, 0.47, 0.39),
            color(0.96, 0.70, 0.26),
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 0.46, 1]
        ) else { return }
        context.saveGState()
        context.addPath(sun)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x, y: center.y - radius),
            end: CGPoint(x: center.x, y: center.y),
            options: []
        )
        context.restoreGState()
    }

    private static func drawHorizon(into context: CGContext, center: CGPoint, radius: CGFloat, template: Bool) {
        context.setLineWidth(radius * (template ? 0.085 : 0.062))
        if template {
            context.setStrokeColor(gray: 0, alpha: 1)
        } else {
            context.setStrokeColor(metal)
        }
        let half = radius * horizonReach
        context.move(to: CGPoint(x: center.x - half, y: center.y))
        context.addLine(to: CGPoint(x: center.x + half, y: center.y))
        context.strokePath()
    }

    /// Dark blades stop at the horizon. The gold handles continue below it.
    private static func cutBlades(into context: CGContext, size: CGFloat, center: CGPoint, radius: CGFloat, template: Bool) {
        let blades = bladePath(center: center, radius: radius, template: template)
        let aboveHorizon = CGRect(x: -size, y: -size, width: size * 3, height: center.y + radius * 0.08 + size)
        context.saveGState()
        context.clip(to: aboveHorizon)
        if template {
            context.setBlendMode(.destinationOut)
            context.addPath(blades)
            context.fillPath()
        } else {
            context.addPath(blades)
            context.clip()
            drawBackground(into: context, size: size)
        }
        context.restoreGState()
    }

    private static func bladePath(center: CGPoint, radius: CGFloat, template: Bool) -> CGPath {
        let path = CGMutablePath()
        let cross = CGPoint(x: center.x, y: center.y - radius * 0.20)
        let width = radius * (template ? 0.20 : 0.155)
        let up = radius * 0.74
        let down = radius * 0.28
        for sign in [-1, 1] as [CGFloat] {
            let angle = sign * 24 * .pi / 180
            let dir = CGVector(dx: sin(angle), dy: -cos(angle))
            let tip = CGPoint(x: cross.x + dir.dx * up, y: cross.y + dir.dy * up)
            let tail = CGPoint(x: cross.x - dir.dx * down, y: cross.y - dir.dy * down)
            let line = CGMutablePath()
            line.move(to: tail)
            line.addLine(to: tip)
            path.addPath(line.copy(
                strokingWithWidth: width,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 2
            ))
        }
        return path
    }

    private static func drawHandles(into context: CGContext, center: CGPoint, radius: CGFloat, template: Bool) {
        let stroke = radius * (template ? 0.15 : 0.118)
        let ringRadius = radius * (template ? 0.21 : 0.23)
        let apex = CGPoint(x: center.x, y: center.y - radius * 0.055)
        let neck = stroke * 1.35
        if template {
            context.setFillColor(gray: 0, alpha: 1)
        } else {
            context.setFillColor(metal)
        }
        for sign in [-1, 1] as [CGFloat] {
            let ringCenter = CGPoint(
                x: center.x + sign * radius * 0.42,
                y: center.y + radius * 0.38
            )
            let circle = CGPath(
                ellipseIn: CGRect(
                    x: ringCenter.x - ringRadius,
                    y: ringCenter.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                ),
                transform: nil
            )
            context.addPath(circle.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 2))
            let dx = ringCenter.x - apex.x
            let dy = ringCenter.y - apex.y
            let len = hypot(dx, dy)
            let attach = CGPoint(
                x: ringCenter.x - dx / len * ringRadius,
                y: ringCenter.y - dy / len * ringRadius
            )
            let arm = CGMutablePath()
            arm.move(to: apex)
            arm.addLine(to: attach)
            context.addPath(arm.copy(strokingWithWidth: neck, lineCap: .round, lineJoin: .round, miterLimit: 2))
        }
        context.fillPath()
    }

    private static func rayColor(_ t: CGFloat) -> CGColor {
        let pink = (CGFloat(0.90), CGFloat(0.42), CGFloat(0.58))
        let coral = (CGFloat(0.98), CGFloat(0.48), CGFloat(0.40))
        let gold = (CGFloat(0.96), CGFloat(0.64), CGFloat(0.32))
        if t < 0.55 {
            return mix(pink, coral, t / 0.55)
        }
        return mix(coral, gold, (t - 0.55) / 0.45)
    }

    private static let metal = CGColor(srgbRed: 0.96, green: 0.71, blue: 0.25, alpha: 1)

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func mix(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat), _ t: CGFloat) -> CGColor {
        let clamped = min(1, max(0, t))
        return color(
            a.0 + (b.0 - a.0) * clamped,
            a.1 + (b.1 - a.1) * clamped,
            a.2 + (b.2 - a.2) * clamped
        )
    }
}
