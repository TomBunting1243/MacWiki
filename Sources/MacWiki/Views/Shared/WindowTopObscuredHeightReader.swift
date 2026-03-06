import SwiftUI

struct WindowTopObscuredHeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: WindowTopObscuredHeightPreferenceKey.self,
                    value: max(0, proxy.safeAreaInsets.top)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WindowTopObscuredHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
