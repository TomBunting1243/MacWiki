import Testing

@MainActor
@Suite(.serialized)
struct ReaderDocumentVisibilityTests {
    @Test func onlyWikimediaPCSContainersOverrideCollapsedVisibility() async throws {
        let harness = ReaderWebKitHarness()
        try await harness.loadHTML(Self.visibilityFixture)

        let pcsContainerClasses = [
            "pcs-section-block",
            "pcs-collapse-block",
            "pcs-section-content"
        ]
        for containerClass in pcsContainerClasses {
            for collapsedState in ["hidden", "class"] {
                let id = "\(containerClass)-\(collapsedState)"
                #expect(try await display(of: id, in: harness) == "block")
                #expect(try await visibility(of: id, in: harness) == "visible")
            }
        }

        #expect(try await display(of: "generic-section", in: harness) == "none")
        #expect(try await display(of: "generic-hidden", in: harness) == "none")
        #expect(try await display(of: "generic-pcs-hidden", in: harness) == "none")
        #expect(try await visibility(of: "generic-pcs-hidden", in: harness) == "hidden")
        #expect(try await display(of: "generic-collapsed", in: harness) == "none")
    }

    private func display(
        of elementID: String,
        in harness: ReaderWebKitHarness
    ) async throws -> String {
        try await harness.evaluateString(
            "window.getComputedStyle(document.querySelector('#\(elementID)')).display"
        )
    }

    private func visibility(
        of elementID: String,
        in harness: ReaderWebKitHarness
    ) async throws -> String {
        try await harness.evaluateString(
            "window.getComputedStyle(document.querySelector('#\(elementID)')).visibility"
        )
    }

    private static let visibilityFixture = """
    <!doctype html>
    <html>
      <head>
        <style>
          .collapsed { display: none; }
          .pcs-hidden { display: none; visibility: hidden; }
        </style>
      </head>
      <body>
        <section id="generic-section" hidden>Generic semantic section</section>
        <div id="generic-hidden" hidden>Generic hidden content</div>
        <div id="generic-pcs-hidden" class="pcs-hidden">Generic PCS-named state</div>
        <div id="generic-collapsed" class="collapsed">Authored collapsed content</div>
        <div id="pcs-section-block-hidden" class="pcs-section-block" hidden>PCS section hidden</div>
        <div id="pcs-section-block-class" class="pcs-section-block pcs-hidden">PCS section class</div>
        <div id="pcs-collapse-block-hidden" class="pcs-collapse-block" hidden>PCS collapse hidden</div>
        <div id="pcs-collapse-block-class" class="pcs-collapse-block pcs-hidden">PCS collapse class</div>
        <div id="pcs-section-content-hidden" class="pcs-section-content" hidden>PCS content hidden</div>
        <div id="pcs-section-content-class" class="pcs-section-content pcs-hidden">PCS content class</div>
      </body>
    </html>
    """
}
