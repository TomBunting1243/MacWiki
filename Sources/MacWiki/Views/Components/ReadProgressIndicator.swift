import SwiftUI

@Animatable
private struct PieSlice: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return path }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle(degrees: -90)
        let endAngle = Angle(degrees: -90 + (360 * clamped))

        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct ReadProgressIndicator: View {
    let progress: Double
    let isRead: Bool
    let tint: Color
    let trackColor: Color
    var size: CGFloat = 8
    var lineWidth: CGFloat = 1

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        let fillProgress = isRead ? 1 : clamped

        ZStack {
            PieSlice(progress: fillProgress)
                .fill(tint)

            Circle()
                .strokeBorder(trackColor, lineWidth: lineWidth)
        }
        .frame(width: size, height: size)
    }
}
