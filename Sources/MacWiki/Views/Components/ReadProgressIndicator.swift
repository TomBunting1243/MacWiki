import SwiftUI

private struct PieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

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
        let unreadProgress = isRead ? 0 : (1 - clamped)

        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            // Keep the progress animation while making unread the stronger state:
            // full tint when untouched, shrinking tint as reading progresses, empty when read.
            if unreadProgress >= 0.999 {
                Circle()
                    .fill(tint)
            } else if unreadProgress > 0.001 {
                PieSlice(progress: unreadProgress)
                    .fill(tint)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.15), value: unreadProgress)
        .animation(.easeInOut(duration: 0.15), value: isRead)
    }
}
