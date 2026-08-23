import Foundation

public enum FamilyMemberRole: String, Codable, Sendable {
    case parent
    case kid
}

public struct FamilyMember: Codable, Equatable, Identifiable, Sendable {
    public let id: KidID
    public var name: String
    public var role: FamilyMemberRole
    public var gradeOrBirthYear: String?
    public var colorTag: String

    public init(id: KidID, name: String, role: FamilyMemberRole, gradeOrBirthYear: String? = nil, colorTag: String) {
        self.id = id
        self.name = name
        self.role = role
        self.gradeOrBirthYear = gradeOrBirthYear
        self.colorTag = colorTag
    }
}

public protocol FamilyMemberStore: Sendable {
    func save(_ member: FamilyMember) async throws
    func members() async throws -> [FamilyMember]
}

public actor LocalFamilyMemberStore: FamilyMemberStore {
    private let storageURL: URL

    public init(storageURL: URL) { self.storageURL = storageURL }

    public func save(_ member: FamilyMember) async throws {
        var saved = try await members()
        saved.removeAll { $0.id == member.id }
        saved.append(member)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: storageURL, options: .atomic)
    }

    public func members() async throws -> [FamilyMember] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        return try JSONDecoder().decode([FamilyMember].self, from: Data(contentsOf: storageURL))
    }
}
