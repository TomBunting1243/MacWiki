enum ReaderDocumentAccessibilityStyle {
    static let reduceTransparencyClass = "macwiki-reduce-transparency"

    static func updateScript(reduceTransparency: Bool) -> String {
        let enabled = reduceTransparency ? "true" : "false"
        return """
        (function() {
            const root = document.documentElement;
            if (!root) { return false; }
            root.classList.toggle('\(reduceTransparencyClass)', \(enabled));
            return root.classList.contains('\(reduceTransparencyClass)');
        })();
        """
    }
}
