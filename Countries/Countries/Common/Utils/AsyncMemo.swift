//
//  AsyncMemo.swift
//  Countries
//
//  Created by Max Breuning on 28.09.26.
//

import Foundation

/// Remembers the result of an expensive build per key, and never runs the same build twice.
///
/// Three caches in the map stack wanted exactly this and each wrote it out again: the decoded
/// GeoJSON collections, the flat map's built paths, and the globe's polygons. The bookkeeping
/// is the part that is easy to get subtly wrong - a second caller arriving mid-build has to
/// await the first one rather than start another, and a failed build has to leave nothing
/// behind - so it lives in one place now and the caches say only what they build.
///
/// - Note: Builds run in a detached task, not on this actor. Running them here would serialise
///   them behind the bookkeeping and block every other caller for the length of a build.
actor AsyncMemo<Key: Hashable & Sendable, Value: Sendable> {

    // MARK: - State

    /// Results of completed builds, kept until ``discardAll()``.
    private var stored: [Key: Value] = [:]

    /// Builds currently running, used to de-duplicate overlapping requests.
    private var inFlight: [Key: Task<Value, Error>] = [:]

    // MARK: - Access

    /// Returns the value for `key`, building it once if it is not there yet.
    ///
    /// - Parameters:
    ///   - key: What the value is remembered under.
    ///   - build: Produces the value. Runs at most once per key, off this actor, and only when
    ///     no result and no in-flight build exist.
    /// - Returns: The remembered value, the one an in-flight build is about to produce, or the
    ///   freshly built one.
    /// - Throws: Whatever `build` throws. A failed build is not remembered, so the next caller
    ///   tries again.
    func value(for key: Key,
               build: @Sendable @escaping () async throws -> Value) async throws -> Value {

        if let value = stored[key] { return value }
        if let task = inFlight[key] { return try await task.value }

        let task = Task.detached(priority: .userInitiated) { try await build() }
        inFlight[key] = task

        defer { inFlight[key] = nil }

        let value = try await task.value
        stored[key] = value

        return value
    }

    /// Drops every remembered result. Builds already running are left alone: they have a caller
    /// waiting, and their result is remembered when they finish.
    func discardAll() {
        stored.removeAll()
    }
}
