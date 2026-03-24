import Foundation

struct PmsetAudioAssertionParser {
    func extractAudioOutputPIDs(from output: String) -> [Int32] {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let createdForPIDRegex = try? NSRegularExpression(pattern: #"Created for PID:\s*(\d+)"#)
        let owningPIDRegex = try? NSRegularExpression(pattern: #"pid\s+(\d+)\([^)]+\):"#)

        var pids: [Int32] = []

        for index in lines.indices {
            let line = lines[index]
            let normalizedLine = line.lowercased()

            if normalizedLine.contains("resources: audio-out") {
                let contextStart = max(lines.startIndex, index - 2)
                let context = Array(lines[contextStart...index]).reversed()

                for contextLine in context {
                    if let pid = firstMatch(in: contextLine, regex: createdForPIDRegex) {
                        pids.append(pid)
                        break
                    }
                }
            }

            if normalizedLine.contains(#"named: "audio-playing""#)
                || normalizedLine.contains("media playback")
            {
                if let pid = firstMatch(in: line, regex: owningPIDRegex) {
                    pids.append(pid)
                }
            }
        }

        var seen = Set<Int32>()
        return pids.filter { seen.insert($0).inserted }
    }

    private func firstMatch(in line: String, regex: NSRegularExpression?) -> Int32? {
        guard let regex,
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        return Int32(line[range])
    }
}
