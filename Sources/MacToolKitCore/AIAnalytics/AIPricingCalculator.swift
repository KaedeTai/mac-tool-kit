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

        // 1. Claude Opus (3.5 / 5)
        if m.contains("opus") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 15.0
            let outCost = (Double(outputTokens + thinkingTokens) / 1_000_000.0) * 75.0
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 1.50
            let cacheWriteCost = (Double(cacheWriteTokens) / 1_000_000.0) * 18.75
            return inCost + outCost + cacheReadCost + cacheWriteCost
        }
        // 2. Claude Sonnet (3.7 / 3.5)
        else if m.contains("sonnet") || (m.contains("claude") && !m.contains("haiku") && !m.contains("fable")) {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 3.00
            let outCost = (Double(outputTokens + thinkingTokens) / 1_000_000.0) * 15.00
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 0.30
            let cacheWriteCost = (Double(cacheWriteTokens) / 1_000_000.0) * 3.75
            return inCost + outCost + cacheReadCost + cacheWriteCost
        }
        // 3. Claude Haiku / Fable
        else if m.contains("haiku") || m.contains("fable") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 0.80
            let outCost = (Double(outputTokens) / 1_000_000.0) * 4.00
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 0.08
            return inCost + outCost + cacheReadCost
        }
        // 4. Gemini 3.7 Flash / Gemini 3.7 Flash High / Thinking (Ultra cost-effective)
        else if m.contains("3.7") || (m.contains("gemini") && m.contains("flash")) {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 0.075
            let outCost = (Double(outputTokens + thinkingTokens) / 1_000_000.0) * 0.30
            return inCost + outCost
        }
        // 5. Gemini 2.5 Pro / 1.5 Pro
        else if m.contains("gemini") && m.contains("pro") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 1.25
            let outCost = (Double(outputTokens) / 1_000_000.0) * 5.00
            return inCost + outCost
        }
        // 6. OpenAI o1 / o3-mini
        else if m.contains("o1") || m.contains("o3") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 1.10
            let outCost = (Double(outputTokens + thinkingTokens) / 1_000_000.0) * 4.40
            return inCost + outCost
        }
        // 7. OpenAI GPT-4o / Codex
        else if m.contains("gpt-4o") || m.contains("codex") {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 2.50
            let outCost = (Double(outputTokens) / 1_000_000.0) * 10.00
            let cacheReadCost = (Double(cacheReadTokens) / 1_000_000.0) * 1.25
            return inCost + outCost + cacheReadCost
        }
        // 8. Local LLM / Ollama / DeepSeek-R1
        else if m.contains("deepseek") || m.contains("llama") || m.contains("qwen") || m.contains("ollama") {
            return 0.0
        }
        // Default fallback (Gemini Flash / Sonnet mid tier)
        else {
            let inCost = (Double(inputTokens) / 1_000_000.0) * 1.00
            let outCost = (Double(outputTokens) / 1_000_000.0) * 3.00
            return inCost + outCost
        }
    }
}
