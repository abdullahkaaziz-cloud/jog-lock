//
//  Websites.swift
//  JogLockCore
//
//  Websites typed in by name, for the ones Screen Time's picker doesn't
//  list. iOS's web filter blocks them in Safari and other browsers. From
//  Tilawah Key's TypedWebsite (K10).
//

import Foundation

public enum TypedWebsite {
    /// Websites chosen in the picker and typed in, together. iOS's web filter
    /// blocks at most 50 and was reported to stop blocking altogether past
    /// 49, so this stays well under it.
    public static let limit = 40

    public enum Problem: Error, Equatable, Sendable {
        case notAWebsite
        case alreadyBlocked(String)
        case tooMany
    }

    /// The domain iOS's web filter takes, which covers its subdomains too:
    /// "https://www.Instagram.com/explore" → "instagram.com". A name in
    /// another script becomes its ASCII form ("xn--…"). Nil for anything
    /// that isn't a website's address.
    public static func domain(from typed: String) -> String? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              var host = URLComponents(string: text.contains("://") ? text : "https://" + text)?.encodedHost
        else {
            return nil
        }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, host.count <= 253, let last = labels.last,
              labels.allSatisfy({ label in
                  (1...63).contains(label.count) && !label.hasPrefix("-") && !label.hasSuffix("-")
                      && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
              }),
              last.hasPrefix("xn--") || (last.count >= 2 && last.allSatisfy(\.isLetter))
        else {
            return nil
        }
        return host
    }

    /// The domain to add for what was typed, with `websites` already typed
    /// in and `picked` websites chosen in the picker; or why it can't be.
    public static func adding(_ text: String, to websites: [String], picked: Int = 0) -> Result<String, Problem> {
        guard let domain = domain(from: text) else { return .failure(.notAWebsite) }
        if websites.contains(domain) { return .failure(.alreadyBlocked(domain)) }
        if websites.count + picked >= limit { return .failure(.tooMany) }
        return .success(domain)
    }

    /// Whether `new` keeps every website in `old`. While the apps are
    /// locked, websites can only be added.
    public static func adds(_ new: [String], to old: [String]) -> Bool {
        Set(new).isSuperset(of: old)
    }

    /// The saved websites as iOS gets them: each in its domain form, once,
    /// at most `limit`. One that no longer reads as a website is left out,
    /// rather than stopping the whole lock.
    public static func cleaned(_ websites: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for site in websites {
            guard result.count < limit, let domain = domain(from: site), seen.insert(domain).inserted else { continue }
            result.append(domain)
        }
        return result
    }
}
