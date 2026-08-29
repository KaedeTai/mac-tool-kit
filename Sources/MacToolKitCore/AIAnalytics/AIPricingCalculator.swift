import Foundation

/// Calculates a standard-rate API-equivalent comparison from provider-reported
/// token buckets. It never represents an invoice, subscription charge, credit
/// deduction, fast-mode surcharge, long-context multiplier, or tool-call fee.
public struct AIPricingCalculator: Sendable {
    public static let shared = AIPricingCalculator()
    public static let rateCardDate = "2026-08-28"

    private enum InputSemantics: Sendable {
        case cacheSeparate
        case cachedInputIsSubset
    }

    private struct Rate: Sendable {
        let input: Double
        let cachedInput: Double
        let cacheWrite5m: Double
        let cacheWrite1h: Double
        let output: Double
        let inputSemantics: InputSemantics
        let sourceName: String
    }

    public init() {}

    public func calculateCostUSD(
        model: String,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64 = 0,
        cacheWriteTokens: Int64 = 0,
        cacheWrite1hTokens: Int64 = 0,
        thinkingTokens: Int64 = 0
    ) -> Double? {
        guard let rate = rate(for: model) else { return nil }
        guard inputTokens >= 0,
              outputTokens >= 0,
              cacheReadTokens >= 0,
              cacheWriteTokens >= 0,
              cacheWrite1hTokens >= 0,
              thinkingTokens >= 0 else { return nil }

        // Reasoning/thinking is reported as an output subset by the providers
        // we support, so it must not be charged a second time here.
        _ = thinkingTokens
        let billableInput: Int64
        switch rate.inputSemantics {
        case .cacheSeparate:
            billableInput = inputTokens
        case .cachedInputIsSubset:
            let categorizedInput = cacheReadTokens + cacheWriteTokens + cacheWrite1hTokens
            guard categorizedInput <= inputTokens else { return nil }
            billableInput = inputTokens - categorizedInput
        }

        return (
            Double(billableInput) * rate.input
                + Double(cacheReadTokens) * rate.cachedInput
                + Double(cacheWriteTokens) * rate.cacheWrite5m
                + Double(cacheWrite1hTokens) * rate.cacheWrite1h
                + Double(outputTokens) * rate.output
        ) / 1_000_000.0
    }

    public func sourceDescription(for model: String) -> String? {
        guard let rate = rate(for: model) else { return nil }
        return "\(rate.sourceName) base standard token rates captured \(Self.rateCardDate); API-equivalent estimate, not billing or subscription spend; per-request long-context, fast-mode, regional, batch, and tool fees require provider fields"
    }

    private func rate(for model: String) -> Rate? {
        let model = model.lowercased()

        // OpenAI ChatGPT Work / Codex and API standard token rates. OpenAI's
        // cached-input count is a subset of input_tokens.
        if model.contains("gpt-5.6-sol") {
            return openAIRate(input: 4, cached: 0.4, output: 20)
        }
        if model.contains("gpt-5.6-terra") {
            return openAIRate(input: 2, cached: 0.2, output: 12)
        }
        if model.contains("gpt-5.6-luna") {
            return openAIRate(input: 0.2, cached: 0.02, output: 1.2)
        }
        if model.contains("gpt-5.5") {
            return openAIRate(input: 5, cached: 0.5, output: 30)
        }
        if model.contains("gpt-5.4-mini") {
            return openAIRate(input: 0.75, cached: 0.075, output: 4.5)
        }
        if model.contains("gpt-5.4") || model == "codex-auto-review" {
            return openAIRate(input: 2.5, cached: 0.25, output: 15)
        }
        if model.contains("gpt-5.3-codex") {
            return openAIRate(input: 1.75, cached: 0.175, output: 14)
        }
        if model.contains("gpt-5.2") {
            return openAIRate(input: 1.75, cached: 0.175, output: 14)
        }
        if model == "gpt-5" || model.hasPrefix("gpt-5-2025-") {
            return openAIRate(input: 1.25, cached: 0.125, output: 10)
        }

        // Anthropic standard API rates. Claude reports base input, cache read,
        // and cache creation as separate buckets.
        if containsVersion(model, family: "haiku", versions: ["4-5", "4.5"]) {
            return claudeRate(input: 1, output: 5)
        }
        if containsVersion(model, family: "haiku", versions: ["3-5", "3.5"]) {
            return claudeRate(input: 0.8, output: 4)
        }
        if model.contains("fable-5") || model.contains("fable 5")
            || model.contains("mythos-5") || model.contains("mythos 5") {
            return claudeRate(input: 10, output: 50)
        }
        if model.contains("sonnet-5") || model.contains("sonnet 5") {
            return claudeRate(input: 2, output: 10)
        }
        if containsVersion(model, family: "sonnet", versions: ["4-6", "4.6", "4-5", "4.5", "4-0", "4.0", "4", "3-7", "3.7", "3-5", "3.5"]) {
            return claudeRate(input: 3, output: 15)
        }
        if model.contains("opus-5") || model.contains("opus 5")
            || containsVersion(model, family: "opus", versions: ["4-8", "4.8", "4-7", "4.7", "4-6", "4.6", "4-5", "4.5"]) {
            return claudeRate(input: 5, output: 25)
        }
        if containsVersion(model, family: "opus", versions: ["4-1", "4.1", "4-0", "4.0", "4", "3"]) {
            return claudeRate(input: 15, output: 75)
        }

        if model.contains("deepseek") || model.contains("llama") || model.contains("qwen") || model.contains("ollama") {
            return Rate(
                input: 0, cachedInput: 0, cacheWrite5m: 0, cacheWrite1h: 0,
                output: 0, inputSemantics: .cacheSeparate,
                sourceName: "Local model with no provider token charge"
            )
        }

        // Never assign an arbitrary fallback rate to an unknown model.
        return nil
    }

    private func openAIRate(input: Double, cached: Double, output: Double) -> Rate {
        Rate(
            input: input,
            cachedInput: cached,
            cacheWrite5m: input * 1.25,
            cacheWrite1h: 0,
            output: output,
            inputSemantics: .cachedInputIsSubset,
            sourceName: "Official OpenAI ChatGPT Work/Codex rate card"
        )
    }

    private func claudeRate(input: Double, output: Double) -> Rate {
        Rate(
            input: input,
            cachedInput: input * 0.1,
            cacheWrite5m: input * 1.25,
            cacheWrite1h: input * 2,
            output: output,
            inputSemantics: .cacheSeparate,
            sourceName: "Official Anthropic API pricing"
        )
    }

    private func containsVersion(_ model: String, family: String, versions: [String]) -> Bool {
        guard model.contains(family) else { return false }
        return versions.contains { version in
            model.contains("\(family)-\(version)")
                || model.contains("\(version)-\(family)")
                || model.contains("\(family) \(version)")
        }
    }
}
