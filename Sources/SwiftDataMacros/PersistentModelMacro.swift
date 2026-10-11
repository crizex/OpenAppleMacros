import OpenAppleMacrosBase

// Mirrors the expansion of Apple's SwiftData @Model (dumped from Xcode 26.6 with -dump-macro-expansions).
// The schema SwiftData derives from schemaMetadata must match Apple's exactly, or existing stores fail to open.
struct PersistentModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let type = declaration.as(ClassDeclSyntax.self)?.name.trimmed.text else {
            throw MacroError("@Model can only be applied to a class")
        }
        let isFinal = declaration.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
        let properties = declaration.persistedProperties
        let metadata = properties.map { property in
            let defaultValue = property.binding.initializer?.value.trimmed.description ?? "nil"
            let metadata = property.schemaMetadata ?? "nil"
            return "    SwiftData.Schema.PropertyMetadata(name: \"\(property.name)\", keypath: \\\(type).\(property.name), "
                + "defaultValue: \(defaultValue), metadata: \(metadata))"
        }.joined(separator: ",\n")
        let initializers = properties.map { "  _\($0.name) = _SwiftDataNoType()\n" }.joined()

        return [
            """
            @Transient
            private var _$backingData: any SwiftData.BackingData<\(raw: type)> = \(raw: type).createBackingData()
            """,
            """
            public var persistentBackingData: any SwiftData.BackingData<\(raw: type)> {
                get {
                    return _$backingData
                }
                set {
                    _$backingData = newValue
                }
            }
            """,
            """
            class var schemaMetadata: [SwiftData.Schema.PropertyMetadata] {
              return [
            \(raw: metadata)
              ]
            }
            """,
            """
            \(raw: isFinal ? "" : "required ")init(backingData: any SwiftData.BackingData<\(raw: type)>) {
            \(raw: initializers)  self.persistentBackingData = backingData
            }
            """,
            "@Transient private let _$observationRegistrar = Observation.ObservationRegistrar()",
            """
            internal nonisolated func access<_M>(
                keyPath: KeyPath<\(raw: type), _M>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            """,
            """
            internal nonisolated func withMutation<_M, _MR>(
              keyPath: KeyPath<\(raw: type), _M>,
              _ mutation: () throws -> _MR
            ) rethrows -> _MR {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            """,
            "struct _SwiftDataNoType {\n}",
        ]
    }

    static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let variable = member.as(VariableDeclSyntax.self), variable.persistedProperty != nil else { return [] }
        return ["@_PersistedProperty"]
    }

    static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let type = type.trimmed
        let message = "PersistentModels are not Sendable, consider utilizing a ModelActor or use \(type)'s persistentModelID instead"
        return [
            try ExtensionDeclSyntax("extension \(type): nonisolated SwiftData.PersistentModel {\n}"),
            try ExtensionDeclSyntax("extension \(type): nonisolated Observation.Observable {\n}"),
            try ExtensionDeclSyntax("""
            @available(swift, deprecated: 5.9, message: "\(raw: message)")
            @available(*, unavailable, message: "\(raw: message)")
            extension \(type): Sendable {
            }
            """),
        ]
    }
}

struct PersistedPropertyMacro: AccessorMacro, PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let name = declaration.as(VariableDeclSyntax.self)?.persistedProperty?.name else { return [] }
        return [
            """
            @storageRestrictions(accesses: _$backingData, initializes: _\(raw: name))
            init(initialValue) {
                _$backingData.setValue(forKey: \\.\(raw: name), to: initialValue)
                _\(raw: name) = _SwiftDataNoType()
            }
            """,
            """
            get {
                _$observationRegistrar.access(self, keyPath: \\.\(raw: name))
                return self.getValue(forKey: \\.\(raw: name))
            }
            """,
            """
            set {
                _$observationRegistrar.withMutation(of: self, keyPath: \\.\(raw: name)) {
                    self.setValue(forKey: \\.\(raw: name), to: newValue)
                }
            }
            """,
        ]
    }

    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let property = declaration.as(VariableDeclSyntax.self)?.persistedProperty else { return [] }
        let initializer = property.binding.initializer == nil ? "" : " = _SwiftDataNoType()"
        // Apple keeps the optionality of the property on the placeholder
        let optional = property.binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) == true ? "?" : ""
        return ["@Transient\nprivate var _\(raw: property.name): _SwiftDataNoType\(raw: optional)\(raw: initializer)"]
    }
}

// Marker macros: @Model reads them while expanding, they add nothing themselves.
struct TransientPropertyMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

struct AttributePropertyMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

struct RelationshipPropertyMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

struct PersistedProperty {
    let name: String
    let binding: PatternBindingSyntax
    let variable: VariableDeclSyntax

    /// `metadata:` argument of PropertyMetadata, from @Attribute(...) or @Relationship(...).
    var schemaMetadata: String? {
        for case .attribute(let attribute) in variable.attributes {
            let kind = attribute.attributeName.trimmed.description
            guard kind == "Attribute" || kind == "Relationship" else { continue }
            let arguments = attribute.arguments?.trimmed.description ?? ""
            return "SwiftData.Schema.\(kind)(\(arguments))"
        }
        return nil
    }
}

extension VariableDeclSyntax {
    /// Stored instance properties that SwiftData persists; nil for computed, static, lazy or @Transient ones.
    var persistedProperty: PersistedProperty? {
        guard bindingSpecifier.tokenKind == .keyword(.var),
              bindings.count == 1,
              let binding = bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmed.text,
              binding.accessorBlock == nil,
              !modifiers.contains(where: { [.keyword(.static), .keyword(.class), .keyword(.lazy)].contains($0.name.tokenKind) }),
              !attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmed.description == "Transient" })
        else { return nil }
        return PersistedProperty(name: name, binding: binding, variable: self)
    }
}

extension DeclGroupSyntax {
    var persistedProperties: [PersistedProperty] {
        memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self)?.persistedProperty }
    }
}
