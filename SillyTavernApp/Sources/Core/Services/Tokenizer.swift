import Foundation

// MARK: - Tokenizer Protocol

/// Protocol for token counting implementations.
protocol Tokenizer: Sendable {
    /// Count the number of tokens in the given text.
    func countTokens(_ text: String) -> Int

    /// The name of this tokenizer.
    var name: String { get }
}

// MARK: - Estimate Tokenizer

/// A tokenizer that estimates token count based on common patterns.
/// More accurate than simple character division, works without external dependencies.
struct EstimateTokenizer: Tokenizer {
    let name = "Estimate"

    /// Tokens per character ratio varies by content type.
    /// - English text: ~0.25 tokens per character (4 chars per token)
    /// - Code: ~0.35 tokens per character (less compression)
    /// - Non-ASCII: ~0.5-1.0 tokens per character
    func countTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var tokenCount = 0.0

        // Process text in chunks for mixed content
        let words = text.components(separatedBy: .whitespacesAndNewlines)

        for word in words {
            tokenCount += estimateWordTokens(word)
        }

        // Add tokens for whitespace/newlines (usually 1 token each)
        let whitespaceCount = text.filter { $0.isWhitespace || $0.isNewline }.count
        tokenCount += Double(whitespaceCount) * 0.5

        return max(1, Int(tokenCount.rounded()))
    }

    private func estimateWordTokens(_ word: String) -> Double {
        guard !word.isEmpty else { return 0 }

        // Special tokens (common subwords)
        let specialTokens = ["'s", "'t", "'re", "'ve", "'m", "'ll", "'d",
                            "ing", "tion", "ness", "ment", "able", "ible"]

        var count = 0.0
        var remaining = word.lowercased()

        // Count special subwords
        for token in specialTokens {
            if remaining.contains(token) {
                count += 1
                remaining = remaining.replacingOccurrences(of: token, with: "")
            }
        }

        // Estimate remaining based on character types
        for char in remaining {
            if char.isASCII {
                if char.isLetter {
                    count += 0.25  // ~4 chars per token for ASCII letters
                } else if char.isNumber {
                    count += 0.5   // Numbers often get their own tokens
                } else if char.isPunctuation {
                    count += 0.75  // Punctuation is often separate
                }
            } else {
                // Non-ASCII characters (CJK, emoji, etc.) often = 1+ tokens
                count += 1.5
            }
        }

        return max(0.5, count)  // Every word is at least half a token
    }
}

// MARK: - Model-Specific Tokenizers

/// Tokenizer with model-specific adjustments.
struct ModelTokenizer: Tokenizer {
    let modelFamily: ModelFamily
    let baseTokenizer: EstimateTokenizer

    var name: String {
        "Estimate (\(modelFamily.rawValue))"
    }

    enum ModelFamily: String, Sendable {
        case gpt4 = "GPT-4"
        case gpt35 = "GPT-3.5"
        case claude = "Claude"
        case llama = "LLaMA"
        case unknown = "Unknown"

        /// Adjustment multiplier for this model family.
        var multiplier: Double {
            switch self {
            case .gpt4, .gpt35:
                return 1.0  // cl100k_base baseline
            case .claude:
                return 0.95 // Claude's tokenizer is slightly more efficient
            case .llama:
                return 1.1  // LLaMA tends to use more tokens
            case .unknown:
                return 1.05 // Slightly conservative default
            }
        }
    }

    init(model: String) {
        self.baseTokenizer = EstimateTokenizer()

        // Detect model family from model name
        let lowerModel = model.lowercased()
        if lowerModel.contains("gpt-4") || lowerModel.contains("gpt4") {
            self.modelFamily = .gpt4
        } else if lowerModel.contains("gpt-3") || lowerModel.contains("gpt3") || lowerModel.contains("turbo") {
            self.modelFamily = .gpt35
        } else if lowerModel.contains("claude") {
            self.modelFamily = .claude
        } else if lowerModel.contains("llama") || lowerModel.contains("vicuna") || lowerModel.contains("alpaca") {
            self.modelFamily = .llama
        } else {
            self.modelFamily = .unknown
        }
    }

    func countTokens(_ text: String) -> Int {
        let baseCount = baseTokenizer.countTokens(text)
        return Int((Double(baseCount) * modelFamily.multiplier).rounded())
    }
}

// MARK: - Token Counter Utility

/// Utility for token counting across the app.
enum TokenCounter {
    /// Default tokenizer using estimation.
    static let defaultTokenizer: any Tokenizer = EstimateTokenizer()

    /// Create a tokenizer for a specific model.
    static func tokenizer(for model: String) -> any Tokenizer {
        ModelTokenizer(model: model)
    }

    /// Quick token count using default tokenizer.
    static func count(_ text: String) -> Int {
        defaultTokenizer.countTokens(text)
    }

    /// Format token count for display.
    static func format(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
