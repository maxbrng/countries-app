//
//  LoadState.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

/// Where a piece of loaded data currently stands.
///
/// One type for every load in the app, so the screens cannot each invent their own pair of
/// flags. The failure case carries nothing on purpose: the underlying error is written to the
/// log, and a `CocoaError` shown to a user is noise rather than information — what the screen
/// owes them is a sentence they can act on and a way to try again.
nonisolated enum LoadState: Equatable {

    /// Nothing has been requested yet.
    case idle

    /// A load is running.
    case loading

    /// The data is there.
    case ready

    /// The load finished without data.
    case failed
}
