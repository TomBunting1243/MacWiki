import Foundation

enum ExperimentFlag: String, CaseIterable {
    case wikiHopPOCEnabled = "experiments.wikiHopPOCEnabled"
    
    var key: String { rawValue }
    
    static let defaults: [String: Bool] = [
        ExperimentFlag.wikiHopPOCEnabled.key: false
    ]
}
