import Foundation
import Testing

@testable import MacWiki

struct TrendPulseDownsamplerTests {
    @Test func shortSeriesIsPreservedExactly() {
        let input = points(count: 7)

        #expect(TrendPulseDownsampler.points(input, maximumCount: 8) == input)
    }

    @Test func longSeriesKeepsEndpointsOrderAndLimit() throws {
        let input = points(count: 500)
        let output = TrendPulseDownsampler.points(input, maximumCount: 80)

        #expect(output.count <= 80)
        #expect(output.first == input.first)
        #expect(output.last == input.last)
        #expect(zip(output, output.dropFirst()).allSatisfy { $0.id < $1.id })
        #expect(Set(output.map(\.id)).count == output.count)
    }

    @Test func bucketExtremaSurviveWhenCapacityAllows() {
        var input = points(count: 40)
        input[10] = TrendPulsePoint(id: 10, date: input[10].date, views: -500)
        input[11] = TrendPulsePoint(id: 11, date: input[11].date, views: 5_000)

        let output = TrendPulseDownsampler.points(input, maximumCount: 20)

        #expect(output.contains(where: { $0.id == 10 }))
        #expect(output.contains(where: { $0.id == 11 }))
    }

    @Test func keyboardSelectionStartsAtTheAnchorAndMovesOnePoint() {
        let input = points(count: 5)

        #expect(
            TrendPulseSelectionPolicy.selection(
                from: nil,
                anchorID: input[2].id,
                in: input,
                moving: .previous
            ) == input[1].id
        )
        #expect(
            TrendPulseSelectionPolicy.selection(
                from: nil,
                anchorID: input[2].id,
                in: input,
                moving: .next
            ) == input[3].id
        )
    }

    @Test func keyboardSelectionClampsAtEachEndpoint() {
        let input = points(count: 5)

        #expect(
            TrendPulseSelectionPolicy.selection(
                from: input.first?.id,
                anchorID: nil,
                in: input,
                moving: .previous
            ) == input.first?.id
        )
        #expect(
            TrendPulseSelectionPolicy.selection(
                from: input.last?.id,
                anchorID: nil,
                in: input,
                moving: .next
            ) == input.last?.id
        )
    }

    @Test func keyboardSelectionHandlesEmptyAndMissingSelectionState() {
        let input = points(count: 3)

        #expect(
            TrendPulseSelectionPolicy.selection(
                from: nil,
                anchorID: nil,
                in: [],
                moving: .next
            ) == nil
        )
        #expect(
            TrendPulseSelectionPolicy.selection(
                from: 500,
                anchorID: 400,
                in: input,
                moving: .next
            ) == input[1].id
        )
        #expect(
            TrendPulseSelectionPolicy.selection(
                from: 500,
                anchorID: 400,
                in: input,
                moving: .previous
            ) == input[input.count - 2].id
        )
    }

    private func points(count: Int) -> [TrendPulsePoint] {
        (0..<count).map { index in
            TrendPulsePoint(
                id: index,
                date: Date(timeIntervalSinceReferenceDate: TimeInterval(index * 86_400)),
                views: (index * 37) % 113
            )
        }
    }
}
