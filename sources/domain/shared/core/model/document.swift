import Foundation

public protocol Document: Sendable {
    static var model: Model<Self> { get }
}

extension Document {
    public var violations: Set<Violation> { Self.model.violations(in: self) }

    public mutating func update<E: Identifiable & Sendable>(
        _ items: WritableKeyPath<Self, [E]>, _ id: UUID,
        _ change: (inout E) throws -> Void
    ) throws where E.ID == UUID {
        guard let i = self[keyPath: items].firstIndex(where: { $0.id == id }) else {
            throw ModelError.notFound(String(localized: .modelNotFound(Korean.object(Self.model.noun(of: E.self)))))
        }
        try change(&self[keyPath: items][i])
    }

    public mutating func remove<E: Identifiable & Sendable>(_ type: E.Type, _ id: UUID) throws where E.ID == UUID {
        try Self.model.remove(ObjectIdentifier(type), id, in: &self)
    }

    public func name(of id: UUID) -> String? {
        Self.model.collections.lazy.compactMap { $0.all(self).first { $0.id == id }?.name }.first
    }

    public func names<E>(_ type: E.Type) -> [(id: UUID, name: String)] {
        Self.model.items(of: ObjectIdentifier(type))?.all(self) ?? []
    }
}
