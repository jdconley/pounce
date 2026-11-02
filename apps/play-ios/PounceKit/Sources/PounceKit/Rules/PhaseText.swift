extension Rules {
    /// Phase `index` (0 = phase 1) in plain words, as the spec lists them (§4): "2 sets of 3",
    /// "1 set of 3 + 1 run of 4", "7 cards of one coat". Built from `phases`, so the words
    /// follow the rules. Empty past the last phase.
    public static func describe(phase index: Int) -> String {
        guard phases.indices.contains(index) else { return "" }
        // Like requirements side by side count together: [set 3, set 3] is "2 sets of 3".
        var counted: [(req: Requirement, count: Int)] = []
        for req in phases[index] {
            if counted.last?.req == req {
                counted[counted.count - 1].count += 1
            } else {
                counted.append((req, 1))
            }
        }
        return counted.map { describe($0.req, count: $0.count) }.joined(separator: " + ")
    }

    private static func describe(_ req: Requirement, count: Int) -> String {
        switch req.kind {
        case .set: "\(count) \(count == 1 ? "set" : "sets") of \(req.size)"
        case .run: "\(count) \(count == 1 ? "run" : "runs") of \(req.size)"
        case .coat: count == 1 ? "\(req.size) cards of one coat" : "\(count) groups of \(req.size) cards of one coat"
        }
    }
}
