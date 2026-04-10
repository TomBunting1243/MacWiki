import Foundation

enum WebViewMessageRouter {
    struct LinkClickPayload {
        let urlString: String
        let openInNewTab: Bool
        let activateNewTab: Bool
        let optionClick: Bool
    }

    enum RoutedMessage {
        case linkClicked(LinkClickPayload)
        case linkRightClicked([String: Any])
        case linkHoverChanged([String: Any])
        case textSelected([String: Any])
        case selectionCleared
        case textSelectionContextRequested([String: Any])
        case scrollChanged([String: Any])
        case scrollPerfSnapshot([String: Any])
        case scrollRestoreReady([String: Any])
        case highlightShortcut(String)
        case highlightClicked(String)
        case highlightResult([String: Any])
        case highlightRightClicked([String: Any])
        case referenceClicked(String)
    }

    static func route(name: String, body: Any) -> RoutedMessage? {
        switch name {
        case "linkClicked":
            guard let payload = linkClickPayload(from: body) else { return nil }
            return .linkClicked(payload)

        case "linkRightClicked":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .linkRightClicked(data)

        case "linkHoverChanged":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .linkHoverChanged(data)

        case "textSelected":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .textSelected(data)

        case "selectionCleared":
            return .selectionCleared

        case "textSelectionContextRequested":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .textSelectionContextRequested(data)

        case "scrollChanged":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .scrollChanged(data)

        case "scrollPerfSnapshot":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .scrollPerfSnapshot(data)

        case "scrollRestoreReady":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .scrollRestoreReady(data)

        case "highlightShortcut":
            guard let data = dictionaryBody(from: body),
                  let text = data["text"] as? String else { return nil }
            return .highlightShortcut(text)

        case "highlightClicked":
            guard let data = dictionaryBody(from: body),
                  let idString = data["id"] as? String else { return nil }
            return .highlightClicked(idString)

        case "highlightResult":
            guard let data = dictionaryBody(from: body),
                  data["total"] as? Int != nil,
                  data["success"] as? Int != nil else { return nil }
            return .highlightResult(data)

        case "highlightRightClicked":
            guard let data = dictionaryBody(from: body) else { return nil }
            return .highlightRightClicked(data)

        case "referenceClicked":
            guard let data = dictionaryBody(from: body),
                  let referenceId = data["referenceId"] as? String else { return nil }
            return .referenceClicked(referenceId)

        default:
            return nil
        }
    }

    private static func linkClickPayload(from body: Any) -> LinkClickPayload? {
        if let urlString = body as? String {
            return LinkClickPayload(
                urlString: urlString,
                openInNewTab: false,
                activateNewTab: true,
                optionClick: false
            )
        }

        guard let data = dictionaryBody(from: body),
              let urlString = data["url"] as? String else {
            return nil
        }

        let optionClick = data["altKey"] as? Bool ?? false
        let commandClick = (data["metaKey"] as? Bool ?? false) && !optionClick
        return LinkClickPayload(
            urlString: urlString,
            openInNewTab: commandClick,
            activateNewTab: !commandClick,
            optionClick: optionClick
        )
    }

    private static func dictionaryBody(from body: Any) -> [String: Any]? {
        body as? [String: Any]
    }
}
