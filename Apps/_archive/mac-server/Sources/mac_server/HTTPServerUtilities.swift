import Foundation
import ServerProtocol

enum HTTPServerUtilities {
    static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 422: return "Unprocessable Content"
        case 503: return "Service Unavailable"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }

    static func tmuxSessionName(for sessionID: String) -> String {
        let filtered = sessionID.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "_"
        }
        return "devys_\(String(filtered))"
    }

    static func normalizedTerminalDimensions(cols: Int, rows: Int) -> (cols: Int, rows: Int)? {
        guard cols > 0, rows > 0 else { return nil }
        return (
            cols: min(max(cols, 20), 400),
            rows: min(max(rows, 5), 200)
        )
    }

    static func isTerminalNamespaceEvent(_ type: StreamEventEnvelope.EventType) -> Bool {
        type.rawValue.hasPrefix("terminal.")
    }

    static func commandExists(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", command]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func shellEscape(_ input: String) -> String {
        if input.isEmpty {
            return "''"
        }
        if input.range(of: #"[^A-Za-z0-9_./-]"#, options: .regularExpression) == nil {
            return input
        }
        return "'" + input.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func parseTmuxControlOutputLine(_ line: String) -> Data? {
        if line.hasPrefix("%output ") {
            let payload = payloadFromControlLine(line, expectedPrefixComponents: 2) ?? ""
            return decodeTmuxControlEscapedPayload(payload)
        }
        if line.hasPrefix("%extended-output ") {
            let payload = payloadFromControlLine(line, expectedPrefixComponents: 3) ?? ""
            return decodeTmuxControlEscapedPayload(payload)
        }
        return nil
    }

    static func payloadFromControlLine(_ line: String, expectedPrefixComponents: Int) -> String? {
        var spaceCount = 0
        for (index, character) in line.enumerated() where character == " " {
            spaceCount += 1
            if spaceCount == expectedPrefixComponents {
                let payloadStart = line.index(line.startIndex, offsetBy: index + 1)
                return String(line[payloadStart...])
            }
        }

        return spaceCount == expectedPrefixComponents - 1 ? "" : nil
    }

    static func decodeTmuxControlEscapedPayload(_ payload: String) -> Data {
        var output = Data()
        var index = payload.startIndex

        while index < payload.endIndex {
            let character = payload[index]
            if character == "\\" {
                index = decodeEscapedCharacter(in: payload, at: index, output: &output)
                continue
            }

            appendLiteralCharacter(character, output: &output)
            index = payload.index(after: index)
        }

        return output
    }

    static func extractExitMarkers(from chunk: Data, carry: Data) -> (display: Data, exitCodes: [Int], carry: Data) {
        let markerPrefix = Data("__DEVYS_EXIT__".utf8)
        var input = Data()
        input.append(carry)
        input.append(chunk)

        var display = Data()
        var exitCodes: [Int] = []
        var cursor = input.startIndex

        while cursor < input.endIndex {
            guard let markerRange = input.range(of: markerPrefix, in: cursor..<input.endIndex) else {
                let tail = Data(input[cursor..<input.endIndex])
                let split = splitTrailingMarkerPrefixCarry(tail, markerPrefix: markerPrefix)
                display.append(split.emit)
                return (display, exitCodes, split.carry)
            }

            let markerStart = markerRange.lowerBound
            display.append(input[cursor..<markerStart])

            var index = markerRange.upperBound
            var sign = 1
            if index < input.endIndex, input[index] == UInt8(ascii: "-") {
                sign = -1
                index = input.index(after: index)
            }

            let digitsStart = index
            while index < input.endIndex, input[index].isASCIIDigit {
                index = input.index(after: index)
            }

            if digitsStart == index {
                display.append(input[markerStart])
                cursor = input.index(after: markerStart)
                continue
            }

            guard input.distance(from: index, to: input.endIndex) >= 2 else {
                return (display, exitCodes, Data(input[markerStart..<input.endIndex]))
            }

            let firstUnderscore = input[index]
            let secondUnderscore = input[input.index(after: index)]
            guard firstUnderscore == UInt8(ascii: "_"), secondUnderscore == UInt8(ascii: "_") else {
                display.append(input[markerStart])
                cursor = input.index(after: markerStart)
                continue
            }

            let digits = Data(input[digitsStart..<index])
            if let digitsText = String(data: digits, encoding: .utf8), let code = Int(digitsText) {
                exitCodes.append(sign == -1 ? -code : code)
            } else {
                display.append(input[markerStart])
            }
            cursor = input.index(index, offsetBy: 2)
        }

        return (display, exitCodes, Data())
    }

    static func splitTrailingMarkerPrefixCarry(_ data: Data, markerPrefix: Data) -> (emit: Data, carry: Data) {
        let upperBound = min(data.count, markerPrefix.count - 1)
        guard upperBound > 0 else { return (data, Data()) }

        for length in stride(from: upperBound, through: 1, by: -1) {
            let suffix = data.suffix(length)
            let prefix = markerPrefix.prefix(length)
            if suffix.elementsEqual(prefix) {
                let emitEnd = data.index(data.endIndex, offsetBy: -length)
                return (Data(data[..<emitEnd]), Data(suffix))
            }
        }
        return (data, Data())
    }

    static func parseRequest(from buffer: Data) -> RequestParseResult {
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return .needMoreData
        }
        guard let requestHeader = requestHeaderText(from: buffer, headerRange: headerRange) else {
            return .invalid
        }
        guard let requestLine = requestHeader.lines.first else {
            return .invalid
        }
        guard let parsedRequestLine = parseRequestLine(requestLine) else {
            return .invalid
        }

        let headers = parseHeaders(requestHeader.lines.dropFirst())
        guard let contentLength = contentLength(from: headers) else {
            return .invalid
        }
        guard let body = parseBody(from: buffer, headerRange: headerRange, contentLength: contentLength) else {
            return .needMoreData
        }

        let path = parsedPath(rawPath: parsedRequestLine.rawPath)
        let query = parsedQuery(rawPath: parsedRequestLine.rawPath)
        return .request(
            HTTPRequest(
                method: parsedRequestLine.method,
                path: path,
                query: query,
                headers: headers,
                body: body
            )
        )
    }
}

private extension HTTPServerUtilities {
    struct ParsedRequestHeader {
        let lines: [String]
    }

    struct ParsedRequestLine {
        let method: String
        let rawPath: String
    }

    static func appendLiteralCharacter(_ character: Character, output: inout Data) {
        if let scalar = character.unicodeScalars.first, scalar.value <= 0xFF {
            output.append(UInt8(scalar.value))
        } else {
            output.append(contentsOf: String(character).utf8)
        }
    }

    static func decodeEscapedCharacter(
        in payload: String,
        at slashIndex: String.Index,
        output: inout Data
    ) -> String.Index {
        let escapedIndex = payload.index(after: slashIndex)
        guard escapedIndex < payload.endIndex else {
            output.append(0x5C)
            return payload.endIndex
        }

        let escaped = payload[escapedIndex]
        switch escaped {
        case "n":
            output.append(0x0A)
            return payload.index(after: escapedIndex)
        case "r":
            output.append(0x0D)
            return payload.index(after: escapedIndex)
        case "t":
            output.append(0x09)
            return payload.index(after: escapedIndex)
        case "\\":
            output.append(0x5C)
            return payload.index(after: escapedIndex)
        default:
            return decodeCustomEscape(
                escaped,
                payload: payload,
                escapedIndex: escapedIndex,
                output: &output
            )
        }
    }

    static func decodeCustomEscape(
        _ escaped: Character,
        payload: String,
        escapedIndex: String.Index,
        output: inout Data
    ) -> String.Index {
        guard escaped.isNumber else {
            output.append(contentsOf: String(escaped).utf8)
            return payload.index(after: escapedIndex)
        }

        var octal = ""
        var octalIndex = escapedIndex
        var consumed = 0
        while octalIndex < payload.endIndex, consumed < 3 {
            let current = payload[octalIndex]
            guard current >= "0", current <= "7" else { break }
            octal.append(current)
            consumed += 1
            octalIndex = payload.index(after: octalIndex)
        }

        if let value = UInt8(octal, radix: 8) {
            output.append(value)
            return octalIndex
        }

        output.append(contentsOf: String(escaped).utf8)
        return payload.index(after: escapedIndex)
    }

    static func requestHeaderText(from buffer: Data, headerRange: Range<Data.Index>) -> ParsedRequestHeader? {
        guard let headerText = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        return ParsedRequestHeader(lines: lines)
    }

    static func parseRequestLine(_ line: String) -> ParsedRequestLine? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return ParsedRequestLine(
            method: String(parts[0]).uppercased(),
            rawPath: String(parts[1])
        )
    }

    static func parseHeaders(_ lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        return headers
    }

    static func contentLength(from headers: [String: String]) -> Int? {
        guard let rawContentLength = headers["content-length"] else {
            return 0
        }
        guard let parsed = Int(rawContentLength), parsed >= 0 else {
            return nil
        }
        return parsed
    }

    static func parseBody(
        from buffer: Data,
        headerRange: Range<Data.Index>,
        contentLength: Int
    ) -> Data? {
        let bodyStart = headerRange.upperBound
        guard buffer.count >= bodyStart + contentLength else {
            return nil
        }
        return Data(buffer[bodyStart..<(bodyStart + contentLength)])
    }

    static func parsedPath(rawPath: String) -> String {
        let components = URLComponents(string: "http://localhost\(rawPath)")
        return components?.path
            ?? rawPath.split(separator: "?", maxSplits: 1).first.map(String.init)
            ?? rawPath
    }

    static func parsedQuery(rawPath: String) -> [String: String] {
        let components = URLComponents(string: "http://localhost\(rawPath)")
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return query
    }
}
