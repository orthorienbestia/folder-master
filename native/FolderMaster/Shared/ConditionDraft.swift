import Foundation

// Native form state, not a matcher or an engine/persistence schema.
enum ConditionGroupMode: String, CaseIterable, Identifiable {
    case all = "All", any = "Any", none = "None"
    var id: String { rawValue }
}
enum ConditionOperator: String, CaseIterable, Identifiable {
    case isValue = "is", isNot = "is not", contains = "contains", notContains = "does not contain"
    case begins = "begins with", ends = "ends with", glob = "glob", regex = "regex"
    case oneOf = "is one of", notOneOf = "is not one of", empty = "is empty"
    case equals = "equals", less = "less than", greater = "greater than", between = "between inclusive"
    case before = "before", after = "after", onDate = "on calendar date", dateRange = "in date range"
    case older = "older than", newer = "newer than", today = "Today", yesterday = "Yesterday"
    case containsAny = "contains any", containsAll = "contains all", containsNone = "contains none"
    var id: String { rawValue }
}
enum ConditionField: String, CaseIterable, Identifiable {
    case name = "Name", extensionName = "Extension", kind = "Kind", size = "Size", date = "Date"
    case tags = "Finder tags", label = "Finder color label", text = "Text content"
    var id: String { rawValue }
    var operators: [ConditionOperator] {
        switch self {
        case .name: return [.isValue, .isNot, .contains, .notContains, .begins, .ends, .glob, .regex]
        case .extensionName: return [.oneOf, .notOneOf, .empty]
        case .kind: return [.isValue, .isNot]
        case .size: return [.equals, .less, .greater, .between]
        case .date: return [.before, .after, .onDate, .dateRange, .older, .newer, .today, .yesterday]
        case .tags: return [.containsAny, .containsAll, .containsNone, .empty]
        case .label: return [.oneOf, .notOneOf]
        case .text: return [.contains, .notContains, .regex]
        }
    }
    var defaultOperator: ConditionOperator {
        switch self {
        case .name, .text: return .contains
        case .size: return .greater
        case .date: return .older
        default: return operators[0]
        }
    }
}
enum ConditionNameScope: String, CaseIterable { case filename = "Filename with extension", stem = "Stem" }
enum ConditionKind: String, CaseIterable {
    case document = "Document", image = "Image", pdf = "PDF", audio = "Audio", video = "Video", archive = "Archive", other = "Other", custom = "Explicit UTType"
}
enum ConditionSizeUnit: String, CaseIterable {
    case bytes = "bytes", kib = "KiB", mib = "MiB", gib = "GiB"
    var multiplier: UInt64 {
        switch self { case .bytes: return 1; case .kib: return 1024; case .mib: return 1_048_576; case .gib: return 1_073_741_824 }
    }
    func bytes(from text: String) -> UInt64? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let digits = Array(value.utf8.filter { $0 != 46 })
        guard !digits.isEmpty, digits.allSatisfy({ (48...57).contains($0) }) else { return nil }
        // Multiply decimal digits before placing the point. Double would round
        // valid large thresholds or make fractional bytes appear integral.
        var product: [UInt8] = []
        var carry: UInt64 = 0
        for digit in digits.reversed() {
            let next = UInt64(digit - 48) * multiplier + carry
            product.append(UInt8(next % 10)); carry = next / 10
        }
        while carry > 0 { product.append(UInt8(carry % 10)); carry /= 10 }
        let fractionalDigits = parts.count == 2 ? parts[1].utf8.count : 0
        guard product.prefix(fractionalDigits).allSatisfy({ $0 == 0 }) else { return nil }
        let whole = product.dropFirst(fractionalDigits).reversed().map { $0 + 48 }
        return whole.isEmpty ? 0 : UInt64(String(decoding: whole, as: UTF8.self))
    }
}
enum ConditionDateField: String, CaseIterable { case created = "Created", modified = "Modified", opened = "Last opened", added = "Added to folder" }
enum ConditionAgeUnit: String, CaseIterable {
    case minutes = "minutes", hours = "hours", days = "days", weeks = "weeks"
    var seconds: Double { switch self { case .minutes: return 60; case .hours: return 3600; case .days: return 86_400; case .weeks: return 604_800 } }
}
enum ConditionLabel: String, CaseIterable, Hashable {
    case none = "None", gray = "Gray", green = "Green", purple = "Purple", blue = "Blue", yellow = "Yellow", red = "Red", orange = "Orange"
}
enum ConditionDraftIssueCode: String {
    case rootGroup, emptyGroup, groupDepth, predicateLimit, invalidOperator, missingValue, invalidSize, reversedRange, invalidDateRange, pendingTag
}
struct ConditionDraftIssue: Identifiable, Equatable {
    let nodeID: UUID
    let code: ConditionDraftIssueCode
    let message: String
    var id: String { nodeID.uuidString + code.rawValue }
}
struct ConditionPredicateDraft: Equatable {
    var field: ConditionField
    var operation: ConditionOperator
    var text = ""
    var upperText = ""
    var caseSensitive = false
    var nameScope = ConditionNameScope.filename
    var kind = ConditionKind.document
    var sizeUnit = ConditionSizeUnit.mib
    var dateField = ConditionDateField.modified
    var startDate = Date()
    var endDate = Date()
    var ageUnit = ConditionAgeUnit.days
    var tagNames: [String] = []
    var tagEntry = ""
    var labels: Set<ConditionLabel> = []
    var textSource = ContentSource.embeddedOnly

    init(field: ConditionField = .name, operation: ConditionOperator? = nil, text: String = "") {
        self.field = field; self.operation = operation ?? field.defaultOperator; self.text = text
    }
    var normalizedExtensions: [String] {
        text.split(separator: ",", omittingEmptySubsequences: false).map {
            var value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix(".") { value.removeFirst() }
            return value.lowercased()
        }
    }
    func issues(nodeID: UUID) -> [ConditionDraftIssue] {
        func issue(_ code: ConditionDraftIssueCode, _ message: String) -> [ConditionDraftIssue] {
            [ConditionDraftIssue(nodeID: nodeID, code: code, message: message)]
        }
        guard field.operators.contains(operation) else { return issue(.invalidOperator, "Choose an operator supported by this field.") }
        switch field {
        case .name, .text:
            return text.isEmpty ? issue(.missingValue, "Enter a value. Literal spaces are allowed.") : []
        case .extensionName:
            if operation == .empty { return [] }
            let valid = normalizedExtensions.allSatisfy { !$0.isEmpty && !$0.contains(".") && !$0.contains("/") && !$0.contains("\0") }
            return valid ? [] : issue(.missingValue, "Enter final extensions separated by commas, such as pdf, gz. Empty items and paths are invalid.")
        case .kind:
            return kind == .custom && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? issue(.missingValue, "Enter a UTType identifier.") : []
        case .size:
            guard let lower = sizeUnit.bytes(from: text) else { return issue(.invalidSize, "Enter a nonnegative decimal size that converts to whole bytes without overflow.") }
            if operation == .between {
                guard let upper = sizeUnit.bytes(from: upperText) else { return issue(.invalidSize, "Enter an upper size that converts to whole bytes without overflow.") }
                if lower > upper { return issue(.reversedRange, "The lower size must not exceed the upper size.") }
            }
            return []
        case .date:
            if operation == .today || operation == .yesterday { return [] }
            if operation == .older || operation == .newer {
                guard let amount = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), amount.isFinite, amount >= 0, (amount * ageUnit.seconds).isFinite else {
                    return issue(.missingValue, "Enter a finite, nonnegative elapsed amount.")
                }
                return []
            }
            guard startDate.timeIntervalSinceReferenceDate.isFinite else { return issue(.invalidDateRange, "Choose a valid date.") }
            if operation == .dateRange && (!endDate.timeIntervalSinceReferenceDate.isFinite || startDate > endDate) {
                return issue(.invalidDateRange, "The start date must not be after the end date.")
            }
            return []
        case .tags:
            if operation == .empty { return [] }
            if !tagEntry.isEmpty { return issue(.pendingTag, "Add or clear the typed tag before saving.") }
            return tagNames.isEmpty || tagNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ? issue(.missingValue, "Add at least one tag name.") : []
        case .label:
            return labels.isEmpty ? issue(.missingValue, "Select at least one label; None is an explicit choice.") : []
        }
    }
}
indirect enum ConditionDraftContent: Equatable {
    case predicate(ConditionPredicateDraft)
    case group(ConditionGroupMode, [ConditionDraftNode])
}
struct ConditionDraftNode: Identifiable, Equatable {
    var id = UUID()
    var content: ConditionDraftContent
    static func predicate(_ value: ConditionPredicateDraft = .init()) -> Self { Self(content: .predicate(value)) }
    static func group(_ mode: ConditionGroupMode = .all, children: [Self] = []) -> Self { Self(content: .group(mode, children)) }
    var children: [Self] { if case .group(_, let children) = content { return children }; return [] }
    var predicateValue: ConditionPredicateDraft? { if case .predicate(let value) = content { return value }; return nil }
    var predicateCount: Int { if predicateValue != nil { return 1 }; return children.reduce(0) { $0 + $1.predicateCount } }
    var allIDs: Set<UUID> { children.reduce(into: [id]) { $0.formUnion($1.allIDs) } }
    func node(_ id: UUID) -> Self? { if self.id == id { return self }; return children.lazy.compactMap { $0.node(id) }.first }
    func groupLevel(_ id: UUID) -> Int? {
        guard case .group = content else { return nil }
        if self.id == id { return 1 }
        for child in children { if let level = child.groupLevel(id) { return level + 1 } }
        return nil
    }
    var validationIssues: [ConditionDraftIssue] {
        var result: [ConditionDraftIssue] = []
        if predicateValue != nil { result.append(.init(nodeID: id, code: .rootGroup, message: "Conditions must start with an All, Any or None group.")) }
        if predicateCount > 50 { result.append(.init(nodeID: id, code: .predicateLimit, message: "Use at most 50 conditions.")) }
        func visit(_ node: Self, level: Int) {
            switch node.content {
            case .predicate(let value): result += value.issues(nodeID: node.id)
            case .group(_, let rows):
                if level > 3 { result.append(.init(nodeID: node.id, code: .groupDepth, message: "Use at most three group levels.")) }
                if rows.isEmpty { result.append(.init(nodeID: node.id, code: .emptyGroup, message: "Add a condition or group; empty groups cannot be saved.")) }
                for child in rows { visit(child, level: child.predicateValue == nil ? level + 1 : level) }
            }
        }
        visit(self, level: 1)
        return result
    }
    @discardableResult mutating func update(_ id: UUID, _ edit: (inout Self) -> Void) -> Bool {
        if self.id == id { edit(&self); return true }
        guard case .group(let mode, var rows) = content else { return false }
        for index in rows.indices {
            if rows[index].update(id, edit) { content = .group(mode, rows); return true }
        }
        return false
    }
    @discardableResult mutating func remove(_ id: UUID) -> Bool {
        guard self.id != id, case .group(let mode, var rows) = content else { return false }
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows.remove(at: index); content = .group(mode, rows); return true
        }
        for index in rows.indices {
            if rows[index].remove(id) { content = .group(mode, rows); return true }
        }
        return false
    }
    @discardableResult mutating func move(_ id: UUID, by offset: Int) -> Bool {
        guard offset == -1 || offset == 1, case .group(let mode, var rows) = content else { return false }
        if let index = rows.firstIndex(where: { $0.id == id }) {
            let target = index + offset
            guard rows.indices.contains(target) else { return false }
            rows.swapAt(index, target); content = .group(mode, rows); return true
        }
        for index in rows.indices {
            if rows[index].move(id, by: offset) { content = .group(mode, rows); return true }
        }
        return false
    }
    mutating func addPredicate(to groupID: UUID) -> UUID? {
        guard predicateCount < 50, groupLevel(groupID) != nil else { return nil }
        let child = Self.predicate()
        update(groupID) { node in
            if case .group(let mode, var rows) = node.content { rows.append(child); node.content = .group(mode, rows) }
        }
        return child.id
    }
    mutating func addGroup(to groupID: UUID) -> UUID? {
        guard predicateCount < 50, let level = groupLevel(groupID), level < 3 else { return nil }
        let child = Self.group(children: [.predicate()])
        update(groupID) { node in
            if case .group(let mode, var rows) = node.content { rows.append(child); node.content = .group(mode, rows) }
        }
        return child.id
    }
    func siblings(of id: UUID) -> [Self] {
        if children.contains(where: { $0.id == id }) { return children }
        for child in children { let found = child.siblings(of: id); if !found.isEmpty { return found } }
        return []
    }
    func focusAfterRemoving(_ id: UUID) -> UUID? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            if index + 1 < children.count { return children[index + 1].id }
            if index > 0 { return children[index - 1].id }
            return self.id
        }
        return children.lazy.compactMap { $0.focusAfterRemoving(id) }.first
    }
    func renewedIdentity() -> Self {
        var copy = self; copy.id = UUID()
        if case .group(let mode, let rows) = content { copy.content = .group(mode, rows.map { $0.renewedIdentity() }) }
        return copy
    }
}
