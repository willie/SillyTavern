import Foundation

// MARK: - File Store

/// Handles file operations for characters, chats, and world info.
/// Supports PNG metadata extraction for character cards.
///
/// Note: FileStore methods are nonisolated to run I/O off the main thread.
/// Callers are responsible for updating @Observable objects with returned values.
final class FileStore: Sendable {

    // MARK: - Directory Paths

    /// Base directory for app data
    var baseDirectory: URL {
        let fm = FileManager.default
        // Use App Group container for potential sharing
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.sillytavern") {
            return container
        }

        // Fallback to documents directory
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SillyTavern")
    }

    var charactersDirectory: URL { baseDirectory.appendingPathComponent("characters") }
    var chatsDirectory: URL { baseDirectory.appendingPathComponent("chats") }
    var groupChatsDirectory: URL { baseDirectory.appendingPathComponent("group chats") }
    var worldInfoDirectory: URL { baseDirectory.appendingPathComponent("worlds") }
    var groupsDirectory: URL { baseDirectory.appendingPathComponent("groups") }
    var settingsFile: URL { baseDirectory.appendingPathComponent("settings.json") }

    // MARK: - Initialization

    init() {
        ensureDirectoriesExist()
    }

    private func ensureDirectoriesExist() {
        let fm = FileManager.default
        let directories = [charactersDirectory, chatsDirectory, groupChatsDirectory, worldInfoDirectory, groupsDirectory]
        for dir in directories {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Character Operations

    /// Load all characters from disk
    nonisolated func loadCharacters() async throws -> [CharacterCard] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: charactersDirectory, includingPropertiesForKeys: nil)
        var characters: [CharacterCard] = []

        for file in files {
            if let character = try? await loadCharacter(from: file) {
                characters.append(character)
            }
        }

        return characters.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Load a character from a file (PNG or JSON)
    nonisolated func loadCharacter(from url: URL) async throws -> CharacterCard {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "png":
            return try await loadCharacterFromPNG(url)
        case "json":
            return try loadCharacterFromJSON(url)
        default:
            throw FileStoreError.unsupportedFormat(ext)
        }
    }

    /// Load character from PNG with embedded metadata
    nonisolated private func loadCharacterFromPNG(_ url: URL) async throws -> CharacterCard {
        let data = try Data(contentsOf: url)
        let jsonString = try PNGMetadataReader.extractCharacterData(from: data)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw FileStoreError.invalidData
        }

        let json = try JSONDecoder().decode([String: JSONValue].self, from: jsonData)
        let character = CharacterCard(from: json, url: url)
        return character
    }

    /// Load character from JSON file
    nonisolated private func loadCharacterFromJSON(_ url: URL) throws -> CharacterCard {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return CharacterCard(from: json, url: url)
    }

    /// Save character data to disk
    /// - Parameters:
    ///   - data: The encoded character data
    ///   - name: Character name for filename
    ///   - existingURL: Existing file URL if updating
    /// - Returns: The URL where the file was saved
    nonisolated func saveCharacter(data: Data, name: String, existingURL: URL?) throws -> URL {
        let url = existingURL ?? charactersDirectory.appendingPathComponent("\(name).json")
        try data.write(to: url)
        return url
    }

    /// Import a character from an external URL (file picker, share sheet, etc.)
    /// - Returns: Tuple of (character, destination URL)
    nonisolated func importCharacter(from url: URL) async throws -> (CharacterCard, URL) {
        let fm = FileManager.default
        let character = try await loadCharacter(from: url)

        // Copy to our characters directory
        let destinationName = sanitizeFilename(character.name)
        let ext = url.pathExtension.lowercased()
        let destination = charactersDirectory.appendingPathComponent("\(destinationName).\(ext)")

        // Ensure unique filename
        let uniqueDestination = ensureUniqueFilename(destination)

        try fm.copyItem(at: url, to: uniqueDestination)

        return (character, uniqueDestination)
    }

    /// Delete a character file
    nonisolated func deleteCharacter(at url: URL) throws {
        let fm = FileManager.default
        try fm.removeItem(at: url)
    }

    // MARK: - World Info Operations

    /// Load all world info books
    nonisolated func loadWorldInfoBooks() async throws -> [WorldInfoBook] {
        let fm = FileManager.default
        // Create directory if it doesn't exist
        try? fm.createDirectory(at: worldInfoDirectory, withIntermediateDirectories: true)

        let files = try fm.contentsOfDirectory(at: worldInfoDirectory, includingPropertiesForKeys: nil)
        var books: [WorldInfoBook] = []

        for file in files where file.pathExtension.lowercased() == "json" {
            if let book = try? loadWorldInfoBook(from: file) {
                books.append(book)
            }
        }

        return books.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Load a world info book from JSON
    nonisolated private func loadWorldInfoBook(from url: URL) throws -> WorldInfoBook {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let book = WorldInfoBook(from: json)
        book.fileURL = url
        return book
    }

    /// Save world info book data to disk
    /// - Parameters:
    ///   - data: The encoded book data
    ///   - name: Book name for filename
    ///   - existingURL: Existing file URL if updating
    /// - Returns: The URL where the file was saved
    nonisolated func saveWorldInfoBook(data: Data, name: String, existingURL: URL?) throws -> URL {
        let filename = sanitizeFilename(name.isEmpty ? "Untitled" : name) + ".json"
        let url = existingURL ?? worldInfoDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    /// Delete a world info book file
    nonisolated func deleteWorldInfoBook(at url: URL) throws {
        let fm = FileManager.default
        try fm.removeItem(at: url)
    }

    /// Import a world info book from an external URL
    /// - Returns: Tuple of (book, destination URL)
    nonisolated func importWorldInfoBook(from url: URL) async throws -> (WorldInfoBook, URL) {
        let fm = FileManager.default
        let book = try loadWorldInfoBook(from: url)

        // Copy to our worlds directory
        let filename = sanitizeFilename(book.name.isEmpty ? "Imported" : book.name)
        let destination = worldInfoDirectory.appendingPathComponent("\(filename).json")
        let uniqueDestination = ensureUniqueFilename(destination)

        try fm.copyItem(at: url, to: uniqueDestination)

        return (book, uniqueDestination)
    }

    // MARK: - Group Operations

    /// Load all groups from disk
    nonisolated func loadGroups() async throws -> [CharacterGroup] {
        let fm = FileManager.default
        // Create directory if it doesn't exist
        try? fm.createDirectory(at: groupsDirectory, withIntermediateDirectories: true)

        let files = try fm.contentsOfDirectory(at: groupsDirectory, includingPropertiesForKeys: nil)
        var groups: [CharacterGroup] = []

        for file in files where file.pathExtension.lowercased() == "json" {
            if let group = try? loadGroup(from: file) {
                groups.append(group)
            }
        }

        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Load a group from JSON file
    nonisolated private func loadGroup(from url: URL) throws -> CharacterGroup {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return CharacterGroup(fromJSON: json, url: url)
    }

    /// Save group data to disk
    /// - Parameters:
    ///   - data: The encoded group data
    ///   - id: Group ID for filename (SillyTavern uses <id>.json)
    ///   - existingURL: Existing file URL if updating
    /// - Returns: The URL where the file was saved
    nonisolated func saveGroup(data: Data, id: String, existingURL: URL?) throws -> URL {
        // SillyTavern stores groups as <id>.json (see groups.js)
        let filename = sanitizeFilename(id) + ".json"
        let url = existingURL ?? groupsDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    /// Delete a group file
    nonisolated func deleteGroup(at url: URL) throws {
        let fm = FileManager.default
        try fm.removeItem(at: url)
    }

    // MARK: - Helpers

    nonisolated private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    nonisolated private func ensureUniqueFilename(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newURL = url
        while fm.fileExists(atPath: newURL.path) {
            counter += 1
            newURL = directory.appendingPathComponent("\(name)_\(counter).\(ext)")
        }
        return newURL
    }
}

// MARK: - PNG Metadata Reader

/// Extracts character metadata from PNG files.
/// PNG files can embed character data in tEXt chunks with keywords 'chara' or 'ccv3'.
enum PNGMetadataReader {

    /// PNG file signature (8 bytes)
    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    /// Extract character data from PNG file data
    static func extractCharacterData(from data: Data) throws -> String {
        // Verify PNG signature
        guard data.count >= 8 else {
            throw FileStoreError.invalidPNG
        }

        let signature = [UInt8](data.prefix(8))
        guard signature == pngSignature else {
            throw FileStoreError.invalidPNG
        }

        // Parse chunks looking for tEXt
        var offset = 8
        var textChunks: [(keyword: String, text: String)] = []

        while offset + 8 < data.count {
            // Read chunk length (4 bytes, big-endian)
            let length = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            })

            // Read chunk type (4 bytes ASCII)
            let typeData = data.subdata(in: (offset + 4)..<(offset + 8))
            let type = String(data: typeData, encoding: .ascii) ?? ""

            offset += 8

            // Check for IEND (end of file)
            if type == "IEND" {
                break
            }

            // Process tEXt chunks
            if type == "tEXt" && length > 0 {
                let chunkData = data.subdata(in: offset..<(offset + length))
                if let parsed = parseTextChunk(chunkData) {
                    textChunks.append(parsed)
                }
            }

            // Move to next chunk (data + CRC)
            offset += length + 4
        }

        // Look for ccv3 first (takes precedence)
        if let ccv3 = textChunks.first(where: { $0.keyword.lowercased() == "ccv3" }) {
            return try decodeBase64(ccv3.text)
        }

        // Fall back to chara
        if let chara = textChunks.first(where: { $0.keyword.lowercased() == "chara" }) {
            return try decodeBase64(chara.text)
        }

        throw FileStoreError.noCharacterData
    }

    /// Parse a tEXt chunk into keyword and text
    private static func parseTextChunk(_ data: Data) -> (keyword: String, text: String)? {
        // tEXt format: keyword (null-terminated) + text
        guard let nullIndex = data.firstIndex(of: 0) else { return nil }

        let keywordData = data.prefix(upTo: nullIndex)
        let textData = data.suffix(from: data.index(after: nullIndex))

        guard let keyword = String(data: keywordData, encoding: .isoLatin1),
              let text = String(data: textData, encoding: .isoLatin1) else {
            return nil
        }

        return (keyword, text)
    }

    /// Decode base64 text to UTF-8 string
    private static func decodeBase64(_ text: String) throws -> String {
        guard let data = Data(base64Encoded: text),
              let decoded = String(data: data, encoding: .utf8) else {
            throw FileStoreError.invalidBase64
        }
        return decoded
    }

    /// Write character data to PNG
    static func writeCharacterData(_ data: Data, characterJSON: String) throws -> Data {
        // Verify PNG signature
        guard data.count >= 8 else {
            throw FileStoreError.invalidPNG
        }

        let signature = [UInt8](data.prefix(8))
        guard signature == pngSignature else {
            throw FileStoreError.invalidPNG
        }

        // Parse existing chunks, removing old chara/ccv3 chunks
        var chunks: [(type: String, data: Data)] = []
        var offset = 8

        while offset + 8 < data.count {
            let length = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            })

            let typeData = data.subdata(in: (offset + 4)..<(offset + 8))
            let type = String(data: typeData, encoding: .ascii) ?? ""

            offset += 8

            let chunkData = length > 0 ? data.subdata(in: offset..<(offset + length)) : Data()
            offset += length + 4  // Skip data and CRC

            // Skip old character data chunks
            if type == "tEXt" {
                if let parsed = parseTextChunk(chunkData) {
                    let keyword = parsed.keyword.lowercased()
                    if keyword == "chara" || keyword == "ccv3" {
                        continue
                    }
                }
            }

            chunks.append((type, chunkData))
        }

        // Encode new character data
        let base64Data = Data(characterJSON.utf8).base64EncodedString()

        // Create new tEXt chunk for 'chara'
        let charaChunk = createTextChunk(keyword: "chara", text: base64Data)

        // Insert before IEND
        if let iendIndex = chunks.firstIndex(where: { $0.type == "IEND" }) {
            chunks.insert(("tEXt", charaChunk), at: iendIndex)
        } else {
            chunks.append(("tEXt", charaChunk))
        }

        // Rebuild PNG
        return rebuildPNG(chunks: chunks)
    }

    /// Create a tEXt chunk data
    private static func createTextChunk(keyword: String, text: String) -> Data {
        var data = Data()
        data.append(contentsOf: keyword.utf8)
        data.append(0)  // Null separator
        data.append(contentsOf: text.utf8)
        return data
    }

    /// Rebuild PNG from chunks
    private static func rebuildPNG(chunks: [(type: String, data: Data)]) -> Data {
        var result = Data(pngSignature)

        for (type, chunkData) in chunks {
            // Length (4 bytes, big-endian)
            var length = UInt32(chunkData.count).bigEndian
            result.append(Data(bytes: &length, count: 4))

            // Type (4 bytes ASCII)
            result.append(contentsOf: type.utf8.prefix(4))

            // Data
            result.append(chunkData)

            // CRC (4 bytes) - CRC of type + data
            var crcData = Data()
            crcData.append(contentsOf: type.utf8.prefix(4))
            crcData.append(chunkData)
            let crc = calculateCRC32(crcData)
            var crcBE = crc.bigEndian
            result.append(Data(bytes: &crcBE, count: 4))
        }

        return result
    }

    /// Calculate CRC32 for PNG chunk
    private static func calculateCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF

        // CRC32 table
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }

        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }

        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Errors

enum FileStoreError: Error, LocalizedError {
    case unsupportedFormat(String)
    case invalidPNG
    case invalidData
    case invalidBase64
    case noCharacterData
    case fileNotFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file format: \(ext)"
        case .invalidPNG:
            return "Invalid PNG file"
        case .invalidData:
            return "Invalid character data"
        case .invalidBase64:
            return "Invalid base64 encoding"
        case .noCharacterData:
            return "No character data found in image"
        case .fileNotFound:
            return "File not found"
        case .encodingFailed:
            return "Failed to encode data"
        }
    }
}
