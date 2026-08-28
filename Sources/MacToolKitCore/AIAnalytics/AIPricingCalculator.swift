import Foundation

public struct AIPricingCalculator: Sendable {
    public static let shared = AIPricingCalculator()

    public init() {}

    public func calculateCostUSD(
        model: String,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64 = 0,
        cacheWriteTokens: Int64 = 0,
        thinkingTokens: Int64 = 0
    ) -> Double {
        let m = model.lowercased()

        // 1. Claude Opus
        if m.contains("opus") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 15.0
            let outCost = (Double(outputTokens + thinkingTokens) / 1_000_000.0) * 75.0
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 1.50
            let cacheWriteCost = (Double(cacheWriteTokens) / 1_000_000.0) * 18.75
            return inCost + outCost + cacheReadCost + cacheWriteCost
        }
        // 2. Claude Sonnet (3.7 / 3.5)
        else if m.contains("sonnet") || m.contains("claude") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 3.00
            let outCost = (Double(outputTokens + thinkingTokens) / 1_000_000.0) * 15.00
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 0.30
            let cacheWriteCost = (Double(cacheWriteTokens) / 1_000_000.0) * 3.75
            return inCost + outCost + cacheReadCost + cacheWriteCost
        }
        // 3. Claude Haiku
        else if m.contains("haiku") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 0.80
            let outCost = (Double(outputTokens) / 1_000_000.0) * 4.00
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 0.08
            return inCost + outCost + cacheReadCost
        }
        // 4. Gemini Pro
        else if m.contains("gemini") && m.contains("pro") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 1.25
            let outCost = (Double(outputTokens) / 1_000_000.0) * 5.00
            return inCost + outCost
        }
        // 5. Gemini Flash
        else if m.contains("gemini") && m.contains("flash") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 0.075
            let outCost = (Double(outputTokens) / 1_000_000.0) * 0.30
            return inCost + outCost
        }
        // 6. GPT-4o
        else if m.contains("gpt-4o") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 2.50
            let outCost = (Double(outputTokens) / 1_000_000.0) * 10.00
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 1.25
            return inCost + outCost + cacheReadCost
        }
        // 7. Local LLM / Ollama
        else if m.contains("deepseek") || m.contains("llama") || m.contains("qwen") || m.contains("ollama") {
            return 0.0 // Free local inference
        }
        // Default fallback (Sonnet-tier estimate)
        else {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 3.00
            let outCost = (Double(outputTokens) / 1_000_000.0) * 15.00
            return inCost + outCost
        }
    }
}
