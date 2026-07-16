import Foundation

public enum TextSourceFormat: String, Codable, CaseIterable, Sendable {
    case plainText = "txt"
    case json
    case xml
}

public enum TextSourceParseError: Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge
    case invalidUTF8
    case noItems
    case tooManyItems
    case malformedJSON
    case excessiveNesting
    case invalidStructure
    case malformedXML
    case unsafeXML

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "The file exceeds the 1 MB import limit."
        case .invalidUTF8: return "The file is not valid UTF-8 text."
        case .noItems: return "The file contains no non-empty text items."
        case .tooManyItems: return "The file contains more than 10,000 text items."
        case .malformedJSON: return "The JSON file is malformed."
        case .excessiveNesting: return "The JSON file is nested too deeply."
        case .invalidStructure:
            return "Expected a string array, {\"items\": [strings]}, or <items><item>…</item></items>."
        case .malformedXML: return "The XML file is malformed."
        case .unsafeXML: return "XML DTD and entity declarations are not allowed."
        }
    }
}

public enum TextSourceParser {
    public static let maximumBytes = 1_048_576
    public static let maximumItems = 10_000
    public static let maximumJSONDepth = 64

    public static func parse(data: Data, format: TextSourceFormat) throws -> [String] {
        guard data.count <= maximumBytes else { throw TextSourceParseError.fileTooLarge }
        guard var text = String(data: data, encoding: .utf8) else {
            throw TextSourceParseError.invalidUTF8
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawItems: [String]
        switch format {
        case .plainText:
            rawItems = parsePlainText(text)
        case .json:
            rawItems = try parseJSON(data: data, decoded: text)
        case .xml:
            rawItems = try parseXML(data: data, decoded: text)
        }
        return try finalize(rawItems)
    }

    private static func parsePlainText(_ text: String) -> [String] {
        let cleaned = stripControls(text)
        let lines = cleaned.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let listPattern = #"^\s*(?:[0-9]+[.)]|[-*•])\s+(.*)$"#
        let expression = try? NSRegularExpression(pattern: listPattern)
        let listItems = lines.compactMap { line -> String? in
            guard let expression,
                  let match = expression.firstMatch(
                      in: line,
                      range: NSRange(line.startIndex..., in: line)
                  ),
                  let range = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[range])
        }
        if !lines.isEmpty, listItems.count == lines.count {
            return listItems
        }

        let separated = cleaned.replacingOccurrences(
            of: #"\n[ \t]*\n(?:[ \t]*\n)*"#,
            with: "\u{1F}",
            options: .regularExpression
        ).components(separatedBy: "\u{1F}")
        if separated.filter({ !sanitize($0).isEmpty }).count >= 2 {
            return separated
        }
        return [cleaned]
    }

    private static func parseJSON(data: Data, decoded text: String) throws -> [String] {
        try validateJSONDepth(text)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw TextSourceParseError.malformedJSON
        }
        if let values = object as? [Any] {
            guard values.allSatisfy({ $0 is String }) else {
                throw TextSourceParseError.invalidStructure
            }
            return values.compactMap { $0 as? String }
        }
        if let dictionary = object as? [String: Any],
           dictionary.count == 1,
           let values = dictionary["items"] as? [Any],
           values.allSatisfy({ $0 is String }) {
            return values.compactMap { $0 as? String }
        }
        throw TextSourceParseError.invalidStructure
    }

    private static func validateJSONDepth(_ text: String) throws {
        var depth = 0
        var inString = false
        var escaped = false
        for scalar in text.unicodeScalars {
            if inString {
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                continue
            }
            if scalar == "\"" {
                inString = true
            } else if scalar == "[" || scalar == "{" {
                depth += 1
                if depth > maximumJSONDepth { throw TextSourceParseError.excessiveNesting }
            } else if scalar == "]" || scalar == "}" {
                depth = max(0, depth - 1)
            }
        }
    }

    private static func parseXML(data: Data, decoded text: String) throws -> [String] {
        let upper = text.uppercased()
        guard !upper.contains("<!DOCTYPE"), !upper.contains("<!ENTITY") else {
            throw TextSourceParseError.unsafeXML
        }
        let delegate = TextSourceXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.error == nil else {
            throw delegate.error ?? TextSourceParseError.malformedXML
        }
        guard delegate.completedRoot else { throw TextSourceParseError.invalidStructure }
        return delegate.items
    }

    private static func finalize(_ rawItems: [String]) throws -> [String] {
        let items = rawItems.map(sanitize).filter { !$0.isEmpty }
        guard !items.isEmpty else { throw TextSourceParseError.noItems }
        guard items.count <= maximumItems else { throw TextSourceParseError.tooManyItems }
        return items
    }

    private static func sanitize(_ value: String) -> String {
        stripControls(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripControls(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

private final class TextSourceXMLDelegate: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private var currentItem = ""
    private var sawRoot = false
    private(set) var completedRoot = false
    private(set) var items: [String] = []
    private(set) var error: TextSourceParseError?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard error == nil else { return }
        if stack.isEmpty {
            guard elementName == "items", !sawRoot, attributeDict.isEmpty else {
                error = .invalidStructure
                parser.abortParsing()
                return
            }
            sawRoot = true
        } else if stack == ["items"] {
            guard elementName == "item", attributeDict.isEmpty else {
                error = .invalidStructure
                parser.abortParsing()
                return
            }
            currentItem = ""
        } else {
            error = .invalidStructure
            parser.abortParsing()
            return
        }
        stack.append(elementName)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard error == nil else { return }
        if stack == ["items", "item"] {
            currentItem += string
        } else if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = .invalidStructure
            parser.abortParsing()
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard error == nil, stack.last == elementName else {
            if error == nil { error = .malformedXML }
            parser.abortParsing()
            return
        }
        if stack == ["items", "item"] { items.append(currentItem) }
        stack.removeLast()
        if stack.isEmpty, elementName == "items" { completedRoot = true }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil { error = .malformedXML }
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        error = .unsafeXML
        return nil
    }
}
