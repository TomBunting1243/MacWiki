import CoreGraphics
import Testing

@testable import MacWiki

@Test func validAutosavedWindowFrameIsPreserved() {
    let visibleFrames = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    let frameString = "120 140 1000 720 0 0 1440 900 "

    #expect(
        WindowFrameSanitizer.isSerializedFrameObviouslyInvalid(
            frameString,
            availableFrames: visibleFrames
        ) == false
    )
}

@Test func farOffscreenAutosavedWindowFrameIsDiscarded() {
    let visibleFrames = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    let frameString = "5200 4100 1000 720 0 0 1440 900 "

    #expect(
        WindowFrameSanitizer.isSerializedFrameObviouslyInvalid(
            frameString,
            availableFrames: visibleFrames
        ) == true
    )
}

@Test func malformedAutosavedWindowFrameIsDiscarded() {
    #expect(
        WindowFrameSanitizer.isSerializedFrameObviouslyInvalid(
            "not a real frame",
            availableFrames: []
        ) == true
    )
}
