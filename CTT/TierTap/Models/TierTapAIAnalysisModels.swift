import Foundation

/// Thematic grouping for AI Analysis questions on the Analytics magic-wand sheet.
enum TierTapAIContext: String, CaseIterable, Identifiable, Codable {
    case winRates
    case playAnalysis
    case tierAnalysis
    case riskOfRuin
    case comps
    case freePlay
    case moodAndProperties

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winRates: return "Win rates"
        case .playAnalysis: return "Play Analysis"
        case .tierAnalysis: return "Tier Analysis"
        case .riskOfRuin: return "Risk of Ruin"
        case .comps: return "Comps"
        case .freePlay: return "Free Play"
        case .moodAndProperties: return "Mood and Properties"
        }
    }

    /// Short description sent to Gemini when generating fresh question ideas.
    var generationTopic: String {
        switch self {
        case .winRates:
            return "win rates, session W/L counts, net results, and ROI-style trends"
        case .playAnalysis:
            return "overall play patterns, session length, pacing, game selection, and habits"
        case .tierAnalysis:
            return "tier points, loyalty programs, properties, and tier-earning efficiency"
        case .riskOfRuin:
            return "volatility, bankroll risk, risk of ruin, swings, and gentle stop/break timing"
        case .comps:
            return "comps, expected value (EV) vs cash net, and how comps change profitability"
        case .freePlay:
            return "logged free play / promotional value and how it relates to sessions"
        case .moodAndProperties:
            return "session mood, tilt, properties, casinos, and rated vs actual bet gaps"
        }
    }
}

/// User-saved custom question generated for a specific context.
struct TierTapAISavedQuestion: Identifiable, Codable, Equatable {
    var id: UUID
    var contextRaw: String
    var title: String
    var instruction: String
    var createdAt: Date

    var context: TierTapAIContext {
        TierTapAIContext(rawValue: contextRaw) ?? .playAnalysis
    }

    init(
        id: UUID = UUID(),
        context: TierTapAIContext,
        title: String,
        instruction: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contextRaw = context.rawValue
        self.title = title
        self.instruction = instruction
        self.createdAt = createdAt
    }
}

/// Draft returned from Gemini before the user saves selected items.
struct TierTapAIGeneratedQuestionDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var instruction: String
    var isSelectedForSave: Bool

    init(id: UUID = UUID(), title: String, instruction: String, isSelectedForSave: Bool = true) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.isSelectedForSave = isSelectedForSave
    }
}
