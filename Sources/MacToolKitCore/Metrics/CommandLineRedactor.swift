import Foundation

public enum CommandLineRedactor {
    public static func redact(_ command: String) -> String {
        var result = command
        let replacements: [(String, String)] = [
            (#"(?i)(--(?:api[-_]?key|token|secret|password|authorization)(?:=|\s+))([^\s]+)"#, "$1[REDACTED]"),
            (#"(?i)\b([A-Z0-9_]*(?:TOKEN|KEY|SECRET|PASSWORD)[A-Z0-9_]*=)([^\s]+)"#, "$1[REDACTED]"),
            (#"(?i)(Bearer\s+)([^\s]+)"#, "$1[REDACTED]"),
            (#"([A-Za-z][A-Za-z0-9+.-]*://)[^/@\s:]+:[^/@\s]+@"#, "$1[REDACTED]@")
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }
}
