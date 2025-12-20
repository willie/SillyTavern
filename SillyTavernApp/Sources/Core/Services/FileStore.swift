import Foundation

// MARK: - File Store

/// Handles file operations for characters, chats, and world info.
/// Supports PNG metadata extraction for character cards.
@MainActor
final class FileStore {
    private let fileManager = FileManager.default

    // MARK: - Directory Paths

    /// Base directory for app data
    var baseDirectory: URL {
        // Use App Group container for potential sharing
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.sillytavern") {
            return container
        }

        // Fallback to documents directory
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SillyTavern")
    }

    var charactersDirectory: URL { baseDirectory.appendingPathComponent("characters") }
    var chatsDirectory: URL { baseDirectory.appendingPathComponent("chats") }
    var worldInfoDirectory: URL { baseDirectory.appendingPathComponent("worlds") }
    var groupsDirectory: URL { baseDirectory.appendingPathComponent("groups") }
    var settingsFile: URL { baseDirectory.appendingPathComponent("settings.json") }

    // MARK: - Initialization

    init() {
        ensureDirectoriesExist()
    }

    private func ensureDirectoriesExist() {
        let directories = [charactersDirectory, chatsDirectory, worldInfoDirectory, groupsDirectory]
        for dir in directories {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Character Operations

    /// Load all characters from disk
    func loadCharacters() async throws -> [CharacterCard] {
        let files = try fileManager.contentsOfDirectory(at: charactersDirectory, includingPropertiesForKeys: nil)
        var characters: [CharacterCard] = []

        for file in files {
            if let character = try? await loadCharacter(from: file) {
                characters.append(character)
            }
        }

        return characters.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Load a character from a file (PNG or JSON)
    func loadCharacter(from url: URL) async throws -> CharacterCard {
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
    private func loadCharacterFromPNG(_ url: URL) async throws -> CharacterCard {
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
    private func loadCharacterFromJSON(_ url: URL) throws -> CharacterCard {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return CharacterCard(from: json, url: url)
    }

    /// Save a character to disk
    func saveCharacter(_ character: CharacterCard) throws {
        let url = character.fileURL ?? charactersDirectory.appendingPathComponent("\(character.name).json")
        let data = try character.toData(prettyPrinted: true)
        try data.write(to: url)
    }

    /// Import a character from an external URL (file picker, share sheet, etc.)
    func importCharacter(from url: URL) async throws -> CharacterCard {
        let character = try await loadCharacter(from: url)

        // Copy to our characters directory
        let destinationName = sanitizeFilename(character.name)
        let ext = url.pathExtension.lowercased()
        let destination = charactersDirectory.appendingPathComponent("\(destinationName).\(ext)")

        // Ensure unique filename
        let uniqueDestination = ensureUniqueFilename(destination)

        try fileManager.copyItem(at: url, to: uniqueDestination)

        // Update character's file URL
        character.fileURL = uniqueDestination
        return character
    }

    /// Delete a character
    func deleteCharacter(_ character: CharacterCard) throws {
        guard let url = character.fileURL else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - World Info Operations

    /// Load all world info books
    func loadWorldInfoBooks() async throws -> [WorldInfoBook] {
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: worldInfoDirectory, withIntermediateDirectories: true)

        let files = try fileManager.contentsOfDirectory(at: worldInfoDirectory, includingPropertiesForKeys: nil)
        var books: [WorldInfoBook] = []

        for file in files where file.pathExtension.lowercased() == "json" {
            if let book = try? loadWorldInfoBook(from: file) {
                books.append(book)
            }
        }

        return books.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Load a world info book from JSON
    private func loadWorldInfoBook(from url: URL) throws -> WorldInfoBook {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let book = WorldInfoBook(from: json)
        book.fileURL = url
        return book
    }

    /// Save a world info book to disk
    func saveWorldInfoBook(_ book: WorldInfoBook) async throws {
        let filename = sanitizeFilename(book.name.isEmpty ? "Untitled" : book.name) + ".json"
        let url = book.fileURL ?? worldInfoDirectory.appendingPathComponent(filename)

        let jsonValue = book.toJSON()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard case .object(let dict) = jsonValue else {
            throw FileStoreError.invalidData
        }

        let data = try encoder.encode(dict)
        try data.write(to: url)
        book.fileURL = url
    }

    /// Delete a world info book from disk
    func deleteWorldInfoBook(_ book: WorldInfoBook) async throws {
        guard let url = book.fileURL else { return }
        try fileManager.removeItem(at: url)
    }

    /// Import a world info book from an external URL
    func importWorldInfoBook(from url: URL) async throws -> WorldInfoBook {
        let book = try loadWorldInfoBook(from: url)

        // Copy to our worlds directory
        let filename = sanitizeFilename(book.name.isEmpty ? "Imported" : book.name)
        let destination = worldInfoDirectory.appendingPathComponent("\(filename).json")
        let uniqueDestination = ensureUniqueFilename(destination)

        try fileManager.copyItem(at: url, to: uniqueDestination)
        book.fileURL = uniqueDestination

        return book
    }

    // MARK: - Group Operations

    /// Load all groups from disk
    func loadGroups() async throws -> [CharacterGroup] {
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: groupsDirectory, withIntermediateDirectories: true)

        let files = try fileManager.contentsOfDirectory(at: groupsDirectory, includingPropertiesForKeys: nil)
        var groups: [CharacterGroup] = []

        for file in files where file.pathExtension.lowercased() == "json" {
            if let group = try? loadGroup(from: file) {
                groups.append(group)
            }
        }

        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Load a group from JSON file
    private func loadGroup(from url: URL) throws -> CharacterGroup {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return CharacterGroup(fromJSON: json, url: url)
    }

    /// Save a group to disk
    func saveGroup(_ group: CharacterGroup) async throws {
        let filename = sanitizeFilename(group.name.isEmpty ? "Untitled" : group.name) + ".json"
        let url = group.fileURL ?? groupsDirectory.appendingPathComponent(filename)

        let data = try group.toData(prettyPrinted: true)
        try data.write(to: url)
        group.fileURL = url
    }

    /// Delete a group from disk
    func deleteGroup(_ group: CharacterGroup) async throws {
        guard let url = group.fileURL else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - Helpers

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    private func ensureUniqueFilename(_ url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newURL = url
        while fileManager.fileExists(atPath: newURL.path) {
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
        }
    }
}
