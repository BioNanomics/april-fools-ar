import Foundation
import CoreFoundation

/// Restricted YAML 1.2 / JSON documents. No aliases, tags, implicit dates or duplicate keys.
/// JSON flow values and two-space block collections are the portable field interchange subset.
enum FieldTextCodec {
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
    }
    static let maximumBytes = 2 * 1024 * 1024
    static func parse(_ text: String) throws -> [String: Any] {
        guard text.utf8.count <= maximumBytes else { throw Failure.invalid("Field document exceeds 2 MiB.") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Any
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            var parser = JSONReader(bytes: Array(trimmed.utf8)); value = try parser.read()
        } else {
            var parser = try YAMLReader(text); value = try parser.read()
        }
        guard let object = value as? [String: Any] else { throw Failure.invalid("A field document must be a mapping.") }
        return object
    }
    static func yaml(_ object: [String: Any]) throws -> String { try emit(object, indent: 0) + "\n" }
    static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    private static func scalar(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    private static func emit(_ value: Any, indent: Int) throws -> String {
        guard indent <= 64 else { throw Failure.invalid("Field document nesting exceeds 32 levels.") }
        let pad = String(repeating: " ", count: indent)
        if let map = value as? [String: Any], !map.isEmpty {
            return try map.keys.sorted().map { key in
                let item = map[key]!
                if isCollection(item) { return pad + (try scalar(key)) + ":\n" + (try emit(item, indent: indent + 2)) }
                return pad + (try scalar(key)) + ": " + (try scalar(item))
            }.joined(separator: "\n")
        }
        if let array = value as? [Any], !array.isEmpty {
            return try array.map { item in
                isCollection(item) ? pad + "-\n" + (try emit(item, indent: indent + 2)) : pad + "- " + (try scalar(item))
            }.joined(separator: "\n")
        }
        return pad + (try scalar(value))
    }
    private static func isCollection(_ value: Any) -> Bool {
        if let map = value as? [String: Any] { return !map.isEmpty }
        if let array = value as? [Any] { return !array.isEmpty }
        return false
    }
    private struct JSONReader {
        var bytes: [UInt8]; var index = 0; var nodes = 0
        mutating func whitespace() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
        mutating func read() throws -> Any {
            let result = try value(0); whitespace()
            guard index == bytes.count else { throw Failure.invalid("Unexpected text after JSON value.") }; return result
        }
        mutating func value(_ depth: Int) throws -> Any {
            nodes += 1; whitespace()
            guard depth <= 32, nodes <= 100_000, index < bytes.count else { throw Failure.invalid("Invalid or excessively nested JSON.") }
            let c = bytes[index]
            if c == 34 { return try string() }
            if c == 123 {
                index += 1; whitespace(); var map = [String: Any]()
                if consume(125) { return map }
                while true {
                    whitespace(); guard index < bytes.count, bytes[index] == 34 else { throw Failure.invalid("JSON mapping keys must be strings.") }
                    let key = try string(); guard map[key] == nil else { throw Failure.invalid("Duplicate key: \(key)") }
                    whitespace(); guard consume(58) else { throw Failure.invalid("Expected ':' after JSON key.") }
                    map[key] = try value(depth + 1); whitespace()
                    if consume(125) { return map }; guard consume(44) else { throw Failure.invalid("Expected ',' in JSON mapping.") }
                }
            }
            if c == 91 {
                index += 1; whitespace(); var array = [Any](); if consume(93) { return array }
                while true { array.append(try value(depth + 1)); whitespace(); if consume(93) { return array }; guard consume(44) else { throw Failure.invalid("Expected ',' in JSON sequence.") } }
            }
            let start = index
            while index < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            switch token { case "true": return true; case "false": return false; case "null": return NSNull(); default: break }
            guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                  let number = Double(token), number.isFinite else { throw Failure.invalid("Invalid JSON scalar: \(token.prefix(80))") }
            return NSNumber(value: number)
        }
        mutating func consume(_ c: UInt8) -> Bool { if index < bytes.count && bytes[index] == c { index += 1; return true }; return false }
        mutating func string() throws -> String {
            let start = index; index += 1; var escaped = false
            while index < bytes.count {
                let c = bytes[index]; index += 1
                if c == 34 && !escaped {
                    let data = Data(bytes[start..<index])
                    guard let s = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { throw Failure.invalid("Invalid JSON string.") }
                    return s
                }
                if c == 92 && !escaped { escaped = true } else { escaped = false }
            }
            throw Failure.invalid("Unterminated JSON string.")
        }
    }
    private struct YAMLReader {
        struct Line { let indent: Int; let text: String; let number: Int }
        var lines = [Line](); var index = 0; var nodes = 0
        init(_ text: String) throws {
            for (i, source) in text.components(separatedBy: .newlines).enumerated() {
                guard !source.contains("\t") else { throw Failure.invalid("Line \(i+1): tabs are not allowed.") }
                let clean = Self.comment(source).trimmingCharacters(in: .whitespaces)
                if clean.isEmpty { continue }
                if clean == "---" && lines.isEmpty { continue }
                guard clean != "---", clean != "..." else { throw Failure.invalid("Only one YAML document is allowed.") }
                let indent = source.prefix(while: { $0 == " " }).count
                guard indent % 2 == 0, indent <= 64 else { throw Failure.invalid("Line \(i+1): use two-space indentation.") }
                lines.append(Line(indent: indent, text: clean, number: i+1))
            }
        }
        static func comment(_ s: String) -> String {
            var quoted = false, escaped = false
            for i in s.indices {
                let c = s[i]
                if c == "\"" && !escaped { quoted.toggle() }
                if c == "#", !quoted, (i == s.startIndex || s[s.index(before: i)].isWhitespace) { return String(s[..<i]) }
                if c == "\\" && !escaped { escaped = true } else { escaped = false }
            }
            return s
        }
        mutating func read() throws -> Any {
            guard !lines.isEmpty, lines[0].indent == 0 else { throw Failure.invalid("Empty or indented YAML root.") }
            let result = try block(0, depth: 0)
            guard index == lines.count else { throw Failure.invalid("Line \(lines[index].number): unexpected indentation.") }; return result
        }
        func pair(_ s: String) -> (String, String)? {
            var quoted = false, escaped = false
            for i in s.indices {
                let c = s[i]
                if c == "\"" && !escaped { quoted.toggle() }
                if c == ":", !quoted {
                    let next = s.index(after: i)
                    if next == s.endIndex || s[next].isWhitespace { return (String(s[..<i]), String(s[next...]).trimmingCharacters(in: .whitespaces)) }
                }
                if c == "\\" && !escaped { escaped = true } else { escaped = false }
            }; return nil
        }
        mutating func scalarValue(_ text: String) throws -> Any {
            guard !text.isEmpty, !text.hasPrefix("&"), !text.hasPrefix("*"), !text.hasPrefix("!"), text != "<<",
                  text != "|", text != ">", ![".nan", ".inf", "-.inf", "+.inf"].contains(text.lowercased()) else { throw Failure.invalid("Unsupported YAML scalar, tag or alias.") }
            if text.hasPrefix("\"") || text.hasPrefix("[") || text.hasPrefix("{") || ["true","false","null"].contains(text) || text.range(of: #"^-?[0-9]"#, options: .regularExpression) != nil {
                var parser = JSONReader(bytes: Array(text.utf8)); return try parser.read()
            }
            guard !text.hasPrefix("'") else { throw Failure.invalid("Use JSON double-quoted strings in field YAML.") }
            return text
        }
        mutating func key(_ text: String) throws -> String {
            let raw = text.trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("\"") { guard let s = try scalarValue(raw) as? String else { throw Failure.invalid("Invalid mapping key.") }; return s }
            guard raw.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil, raw != "<<" else { throw Failure.invalid("Mapping keys must be strings; quote this key: \(raw)") }; return raw
        }
        mutating func entry(_ pair: (String, String), into map: inout [String: Any], indent: Int, depth: Int) throws {
            let k = try key(pair.0); guard map[k] == nil else { throw Failure.invalid("Duplicate YAML key: \(k)") }
            if pair.1.isEmpty {
                guard index < lines.count, lines[index].indent == indent + 2 else { throw Failure.invalid("Missing value for \(k); write null explicitly.") }
                map[k] = try block(indent + 2, depth: depth + 1)
            } else { map[k] = try scalarValue(pair.1) }
        }
        mutating func block(_ indent: Int, depth: Int) throws -> Any {
            nodes += 1; guard depth <= 32, nodes <= 100_000 else { throw Failure.invalid("YAML nesting/collection limit exceeded.") }
            let sequence = lines[index].text == "-" || lines[index].text.hasPrefix("- ")
            if sequence {
                var output = [Any]()
                while index < lines.count && lines[index].indent == indent {
                    let row = lines[index]; guard row.text == "-" || row.text.hasPrefix("- ") else { throw Failure.invalid("Line \(row.number): mixed sequence/mapping.") }
                    index += 1; let rest = String(row.text.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if rest.isEmpty {
                        guard index < lines.count, lines[index].indent == indent + 2 else { throw Failure.invalid("Missing sequence value.") }
                        output.append(try block(indent + 2, depth: depth + 1))
                    } else if let first = pair(rest) {
                        var map = [String: Any](); try entry(first, into: &map, indent: indent + 2, depth: depth + 1)
                        while index < lines.count && lines[index].indent == indent + 2 {
                            guard let p = pair(lines[index].text) else { throw Failure.invalid("Expected sequence mapping entry.") }
                            index += 1; try entry(p, into: &map, indent: indent + 2, depth: depth + 1)
                        }; output.append(map)
                    } else { output.append(try scalarValue(rest)) }
                }; return output
            }
            var output = [String: Any]()
            while index < lines.count && lines[index].indent == indent {
                let row = lines[index]; guard let p = pair(row.text) else { throw Failure.invalid("Line \(row.number): expected key: value.") }
                index += 1; try entry(p, into: &output, indent: indent, depth: depth)
            }; return output
        }
    }
}
