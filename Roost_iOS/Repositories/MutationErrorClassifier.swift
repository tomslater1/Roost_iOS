import Foundation

// MARK: - MutationErrorClassifier
//
// Shared error → `MutationHandlerError` mapping reused by every domain
// handler. Keeps classification consistent across Expenses, Budgets,
// SavingsGoals, etc., without each handler re-implementing the string
// matching against Supabase `PostgrestError` descriptions.

enum MutationErrorClassifier {
    static func classify(_ error: Error, fallback: String) -> MutationHandlerError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return .transient(urlError.localizedDescription)
            default:
                return .transient(urlError.localizedDescription)
            }
        }

        let description = String(describing: error)
        let lower = description.lowercased()
        if lower.contains("401") || lower.contains("unauthorized") || lower.contains("jwt") {
            return .authExpired
        }
        if lower.contains("409") || lower.contains("conflict") {
            return .reconciledByServer(description)
        }
        if lower.contains("400") || lower.contains("403") || lower.contains("404") || lower.contains("422") {
            return .permanent(description)
        }
        _ = fallback
        return .transient(description)
    }

    static func isNotFound(_ error: Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("404") || description.contains("not found") || description.contains("no rows")
    }
}
