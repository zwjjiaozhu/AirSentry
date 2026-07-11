import SwiftUI

struct FloatingArcBandShape: Shape {
    let center: CGPoint
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let startAngle: Double
    let endAngle: Double
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let currentEndAngle = FloatingArcMath.counterClockwiseAngle(
            from: startAngle,
            to: endAngle,
            progress: clampedProgress
        )
        var path = Path()
        guard clampedProgress > 0.001 else { return path }
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(currentEndAngle),
            clockwise: true
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(currentEndAngle),
            endAngle: .degrees(startAngle),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

struct FloatingArcGuideShape: Shape {
    let center: CGPoint
    let radius: CGFloat
    let startAngle: Double
    let endAngle: Double
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let currentEndAngle = FloatingArcMath.counterClockwiseAngle(
            from: startAngle,
            to: endAngle,
            progress: clampedProgress
        )
        var path = Path()
        guard clampedProgress > 0.001 else { return path }
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(currentEndAngle),
            clockwise: true
        )
        return path
    }
}

enum FloatingArcMath {
    static func counterClockwiseAngle(from startAngle: Double, to endAngle: Double, progress: Double) -> Double {
        let clampedProgress = min(max(progress, 0), 1)
        let sweep = positiveModulo(startAngle - endAngle, 360)
        return startAngle - sweep * clampedProgress
    }

    private static func positiveModulo(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
