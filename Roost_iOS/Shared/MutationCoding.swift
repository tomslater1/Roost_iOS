//
//  MutationCoding.swift
//  Roost
//
//  Shared JSON coders for `PendingMutation.payloadData`. Used by every
//  MutationHandler in the main app and by the RoostWidgets extension when
//  it enqueues its own mutations (e.g. ToggleShoppingItemIntent).
//
//  Target membership: BOTH `Roost_iOS` and `RoostWidgets`.
//

import Foundation

extension JSONEncoder {
    /// Shared encoder for `PendingMutation.payloadData` across all handlers.
    static let mutation: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    /// Shared decoder for `PendingMutation.payloadData` across all handlers.
    static let mutation: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
