import Foundation

/// One record in a word list: an ordered list of named string cells. The cell
/// order defines the column order in the encoded file.
public struct WordListRow: Sendable, Equatable {
    public struct Cell: Sendable, Equatable {
        public let key: String
        public let value: String
        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public let cells: [Cell]

    public init(cells: [Cell]) {
        self.cells = cells
    }

    public init(_ pairs: [(String, String)]) {
        self.cells = pairs.map { Cell(key: $0.0, value: $0.1) }
    }
}
