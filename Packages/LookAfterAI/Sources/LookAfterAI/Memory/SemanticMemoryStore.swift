import Foundation
import NaturalLanguage
import LookAfterCore

/// On-device Semantic Memory Store using Apple's Natural Language framework for vector embeddings.
/// Enables semantic vector search ("AI Memory over life") without third-party dependencies.
public final class SemanticMemoryStore: @unchecked Sendable {
    
    private let embeddingModel: NLEmbedding?
    
    public init() {
        // Load sentence embedding for English
        self.embeddingModel = NLEmbedding.sentenceEmbedding(for: .english)
    }
    
    /// Generate vector embedding for text using NLEmbedding.
    public func generateEmbedding(for text: String) -> [Double]? {
        guard let embedding = embeddingModel else { return nil }
        return embedding.vector(for: text)
    }
    
    /// Calculate cosine similarity between two vector embeddings.
    public func cosineSimilarity(v1: [Double], v2: [Double]) -> Double {
        guard v1.count == v2.count, !v1.isEmpty else { return 0 }
        
        var dotProduct: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        
        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
            normA += v1[i] * v1[i]
            normB += v2[i] * v2[i]
        }
        
        guard normA > 0, normB > 0 else { return 0 }
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
    
    /// Perform semantic vector search over a list of MemoryEntry items.
    public func search(query: String, entries: [MemoryEntry], limit: Int = 5) -> [(entry: MemoryEntry, score: Double)] {
        guard let queryVector = generateEmbedding(for: query) else {
            // Fallback to text matching if embedding fails
            let matches = entries.filter { $0.content.localizedCaseInsensitiveContains(query) }
            return matches.prefix(limit).map { ($0, 1.0) }
        }
        
        var results: [(entry: MemoryEntry, score: Double)] = []
        
        for entry in entries {
            if let vector = entry.embeddingVector {
                let sim = cosineSimilarity(v1: queryVector, v2: vector)
                results.append((entry, sim))
            } else if let entryVector = generateEmbedding(for: entry.content) {
                let sim = cosineSimilarity(v1: queryVector, v2: entryVector)
                results.append((entry, sim))
            }
        }
        
        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
