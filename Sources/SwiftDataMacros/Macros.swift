import OpenAppleMacrosBase

package var all: [Macro.Type] {
    [
        PersistentModelMacro.self,
        PersistedPropertyMacro.self,
        TransientPropertyMacro.self,
        AttributePropertyMacro.self,
        RelationshipPropertyMacro.self,
    ]
}
