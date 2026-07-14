enum ReaderDocumentAccessibilityStyle {
    static let reduceTransparencyClass = "macwiki-reduce-transparency"
    static let differentiateWithoutColorClass = "macwiki-differentiate-without-color"

    static func updateScript(
        reduceTransparency: Bool,
        differentiateWithoutColor: Bool = false
    ) -> String {
        let reduceTransparencyEnabled = reduceTransparency ? "true" : "false"
        let differentiateWithoutColorEnabled = differentiateWithoutColor ? "true" : "false"
        return """
        (function() {
            const root = document.documentElement;
            if (!root) { return false; }
            root.classList.toggle('\(reduceTransparencyClass)', \(reduceTransparencyEnabled));
            root.classList.toggle('\(differentiateWithoutColorClass)', \(differentiateWithoutColorEnabled));
            return root.classList.contains('\(reduceTransparencyClass)');
        })();
        """
    }
}
