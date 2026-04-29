import Observation
import Foundation

@MainActor
@Observable
final class HazelViewModel {

    // MARK: - Persisted toggles

    var shoppingEnabled: Bool {
        didSet { UserDefaults.standard.set(shoppingEnabled, forKey: Keys.shopping) }
    }

    var expensesEnabled: Bool {
        didSet { UserDefaults.standard.set(expensesEnabled, forKey: Keys.expenses) }
    }

    var choresEnabled: Bool {
        didSet { UserDefaults.standard.set(choresEnabled, forKey: Keys.chores) }
    }

    var budgetEnabled: Bool {
        didSet { UserDefaults.standard.set(budgetEnabled, forKey: Keys.budget) }
    }

    var insightsEnabled: Bool {
        didSet { UserDefaults.standard.set(insightsEnabled, forKey: Keys.insights) }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        shoppingEnabled  = defaults.object(forKey: Keys.shopping)  as? Bool ?? true
        expensesEnabled  = defaults.object(forKey: Keys.expenses)  as? Bool ?? true
        choresEnabled    = defaults.object(forKey: Keys.chores)    as? Bool ?? true
        budgetEnabled    = defaults.object(forKey: Keys.budget)    as? Bool ?? true
        insightsEnabled  = defaults.object(forKey: Keys.insights)  as? Bool ?? true
    }

    // MARK: - Computed

    var activeCount: Int {
        [shoppingEnabled, expensesEnabled, choresEnabled, budgetEnabled, insightsEnabled].filter { $0 }.count
    }

    var statusLabel: String {
        if activeCount == 0 { return "Paused" }
        return "Active in \(activeCount) area\(activeCount == 1 ? "" : "s")"
    }

    var isActive: Bool { activeCount > 0 }

    // MARK: - Examples

    struct FeatureExample: Identifiable {
        let id = UUID()
        let area: String
        let before: String
        let after: String
    }

    let examples: [FeatureExample] = [
        FeatureExample(
            area: "Shopping",
            before: "\"milk, eggs, bread\"",
            after: "Dairy: Milk, Eggs · Bakery: Bread"
        ),
        FeatureExample(
            area: "Expenses",
            before: "\"Tesco £42.50\"",
            after: "Groceries · £42.50 · Shared equally"
        ),
        FeatureExample(
            area: "Chores",
            before: "\"Clean the bathroom\"",
            after: "Clean Bathroom · Weekly · Bathroom"
        ),
        FeatureExample(
            area: "Budget",
            before: "Uncategorised expenses",
            after: "Auto-suggested categories and limits"
        ),
    ]

    // MARK: - Keys

    private enum Keys {
        static let shopping  = "hazel.shopping"
        static let expenses  = "hazel.expenses"
        static let chores    = "hazel.chores"
        static let budget    = "hazel.budget"
        static let insights  = "hazel.insights"
    }
}
