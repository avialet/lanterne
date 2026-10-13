/// Numero de generation des travaux en arriere-plan (reconstruction de l'index) : seul le resultat de la
/// derniere demande est accepte, une seule fois ; un resultat ancien arrive en retard est ignore.
public struct Generation: Sendable, Equatable {
    public private(set) var requested = 0
    public private(set) var accepted = 0

    public init() {}

    /// Nouvelle demande : son numero.
    public mutating func next() -> Int {
        requested += 1
        return requested
    }

    /// Vrai si `ticket` est la derniere demande et n'a pas encore ete acceptee.
    public mutating func accept(_ ticket: Int) -> Bool {
        guard ticket == requested, ticket > accepted else { return false }
        accepted = ticket
        return true
    }
}
