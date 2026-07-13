#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: dump_performance_metrics.swift <defaults-suite>\n", stderr)
    exit(EXIT_FAILURE)
}

let suiteName = CommandLine.arguments[1]
let trustedPrefix = "com.tombunting.MacWiki.qa."
guard suiteName.hasPrefix(trustedPrefix), suiteName.count > trustedPrefix.count,
      let defaults = UserDefaults(suiteName: suiteName) else {
    fputs("Refusing untrusted or unavailable QA defaults suite.\n", stderr)
    exit(EXIT_FAILURE)
}

let keyPrefix = "com.macwiki.performance-metrics.samples.v2"
let kinds = ["sessionRestore", "search", "sidebarHydration", "readerOpen"]
print("kind,duration_ms,detail")

for kind in kinds {
    let key = "\(keyPrefix).\(kind)"
    guard let data = defaults.data(forKey: key),
          let samples = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        continue
    }
    for sample in samples {
        guard let duration = sample["durationMs"] as? NSNumber else { continue }
        let detail = String(describing: sample["detail"] ?? "")
            .replacingOccurrences(of: "\"", with: "\"\"")
        print("\(kind),\(duration.doubleValue),\"\(detail)\"")
    }
}
