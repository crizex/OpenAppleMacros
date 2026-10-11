import SwiftSyntax
import SwiftSyntaxMacros

/// `@Query` as expanded by Xcode 26.6: a `private(set)` SwiftData.Query peer initialized with the
/// macro arguments, and a getter forwarding to its wrappedValue. Xcode writes SwiftData.Query, which only resolves
/// through the cross-import overlay on Darwin; the macro is declared in _SwiftData_SwiftUI, so that name always does.
struct QueryMacro: AccessorMacro, PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let name = binding(of: declaration)?.name else { return [] }
        return ["get {\n    _\(raw: name).wrappedValue\n}"]
    }

    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let (name, type) = binding(of: declaration), let type else { return [] }
        let args = node.arguments?.as(LabeledExprListSyntax.self)?.trimmedDescription ?? ""
        return ["private(set) var _\(raw: name): _SwiftData_SwiftUI.Query<\(raw: type).Element, \(raw: type)> = .init(\(raw: args))"]
    }

    private static func binding(of declaration: some DeclSyntaxProtocol) -> (name: String, type: String?)? {
        guard let binding = declaration.as(VariableDeclSyntax.self)?.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        return (name, binding.typeAnnotation?.type.trimmedDescription)
    }
}
