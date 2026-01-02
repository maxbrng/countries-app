//
//  CountryRepository.swift
//  Countries
//
//  Created by Max Breuning on 01.01.26.
//


import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Countries", category: "CountryRepository")

// minimal logging for repository

protocol CountryRepositoryProtocol: Sendable {
    @MainActor func fetchAll(search: String?, filter: CountryStatusFilter, sortAscending: Bool) throws -> [Country]
    @MainActor func stats() throws -> (visited: Int, wishlist: Int, total: Int)
    @MainActor func getStatus(iso2: String) throws -> CountryStatus?
    @MainActor func setStatus(iso2: String, status: CountryStatus) throws
    @MainActor func toggleVisited(for iso2: String) throws
    @MainActor func toggleWishlist(for iso2: String) throws
}

enum CountryStatusFilter: Sendable, CaseIterable, Identifiable {
    case all
    case visited
    case wishlist

    var id: String { String(describing: self) }
    var title: String {
        switch self {
        case .all: return "All"
        case .visited: return "Visited"
        case .wishlist: return "Wishlist"
        }
    }
}

@MainActor
final class CountryRepository: CountryRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func fetchAll(search: String?, filter: CountryStatusFilter, sortAscending: Bool = true) throws -> [Country] {
        let visitedRaw = CountryStatus.visited.rawValue
        let wishlistRaw = CountryStatus.wishlist.rawValue
        var predicate: Predicate<Country> = #Predicate { _ in true }
        switch filter {
        case .all:
            break
        case .visited:
            let p = #Predicate<Country> { $0.statusRaw == visitedRaw }
            predicate = and(predicate, p)
        case .wishlist:
            let p = #Predicate<Country> { $0.statusRaw == wishlistRaw }
            predicate = and(predicate, p)
        }

        let sort = [SortDescriptor(\Country.name, order: sortAscending ? .forward : .reverse)]
        let fetch = FetchDescriptor<Country>(predicate: predicate, sortBy: sort)
        var results = try context.fetch(fetch)
        if let search, !search.isEmpty {
            results = results.filter { c in
                c.name.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
                c.iso2.range(of: search, options: [.caseInsensitive]) != nil
            }
        }
        return results
    }

    func stats() throws -> (visited: Int, wishlist: Int, total: Int) {
        let visitedRaw = CountryStatus.visited.rawValue
        let wishlistRaw = CountryStatus.wishlist.rawValue
        let total = try context.fetchCount(FetchDescriptor<Country>())
        let visited = try context.fetchCount(FetchDescriptor<Country>(predicate: #Predicate { $0.statusRaw == visitedRaw }))
        let wishlist = try context.fetchCount(FetchDescriptor<Country>(predicate: #Predicate { $0.statusRaw == wishlistRaw }))
        logger.info("Stats summary: visited=\(visited, privacy: .public) wishlist=\(wishlist, privacy: .public) total=\(total, privacy: .public) [stats() @ \(#fileID):\(#line)]")
        return (visited, wishlist, total)
    }

    func getStatus(iso2: String) throws -> CountryStatus? {
        let code = iso2.uppercased()
        let fetch = FetchDescriptor<Country>(predicate: #Predicate { $0.iso2 == code })
        guard let c = try context.fetch(fetch).first else { return nil }
        return c.status
    }

    func setStatus(iso2: String, status: CountryStatus) throws {
        let code = iso2.uppercased()
        let fetch = FetchDescriptor<Country>(predicate: #Predicate { $0.iso2 == code })
        guard let c = try context.fetch(fetch).first else { return }
        c.status = status
        try context.save()
    }

    func toggleVisited(for iso2: String) throws {
        let current = try getStatus(iso2: iso2) ?? .none
        let newStatus: CountryStatus = (current == .visited) ? .none : .visited
        try setStatus(iso2: iso2, status: newStatus)
    }

    func toggleWishlist(for iso2: String) throws {
        let current = try getStatus(iso2: iso2) ?? .none
        let newStatus: CountryStatus = (current == .wishlist) ? .none : .wishlist
        try setStatus(iso2: iso2, status: newStatus)
    }
}

private func and<T>(_ a: Predicate<T>, _ b: Predicate<T>) -> Predicate<T> { #Predicate { a.evaluate($0) && b.evaluate($0) } }

