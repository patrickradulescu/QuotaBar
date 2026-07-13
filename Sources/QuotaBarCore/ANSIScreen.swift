import Foundation

/// A small, deterministic terminal screen used only to read Claude Code's
/// documented `/usage` screen. It intentionally supports the ANSI cursor and
/// erase operations emitted by that screen, not a full terminal protocol.
public final class ANSIScreen {
    private enum State {
        case normal
        case escape
        case csi
        case osc
        case oscEscape
        case charset
    }

    public let columns: Int
    public let rows: Int

    private var cells: [[UInt8]]
    private var row = 0
    private var column = 0
    private var savedRow = 0
    private var savedColumn = 0
    private var state: State = .normal
    private var csiBytes: [UInt8] = []

    public init(columns: Int = 100, rows: Int = 32) {
        self.columns = columns
        self.rows = rows
        cells = Array(
            repeating: Array(repeating: 0x20, count: columns),
            count: rows
        )
    }

    public func feed(_ data: Data) {
        data.forEach(process)
    }

    public var renderedText: String {
        cells
            .map { row in
                String(bytes: row, encoding: .ascii)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
            }
            .joined(separator: "\n")
    }

    private func process(_ byte: UInt8) {
        switch state {
        case .normal:
            processNormal(byte)
        case .escape:
            processEscape(byte)
        case .csi:
            processCSI(byte)
        case .osc:
            if byte == 0x07 {
                state = .normal
            } else if byte == 0x1B {
                state = .oscEscape
            }
        case .oscEscape:
            state = byte == 0x5C ? .normal : .osc
        case .charset:
            state = .normal
        }
    }

    private func processNormal(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            state = .escape
        case 0x0D:
            column = 0
        case 0x0A:
            moveDown()
        case 0x08:
            column = max(0, column - 1)
        case 0x20...0x7E:
            put(byte)
        case 0x80...0xBF:
            // UTF-8 continuation byte: the lead byte already occupied one cell.
            break
        case 0xC0...0xFF:
            // The usage labels and values are ASCII. Preserve terminal geometry
            // for symbols without retaining or parsing decorative Unicode.
            put(0x20)
        default:
            break
        }
    }

    private func processEscape(_ byte: UInt8) {
        switch byte {
        case 0x5B: // [
            csiBytes.removeAll(keepingCapacity: true)
            state = .csi
        case 0x5D: // ]
            state = .osc
        case 0x37: // 7
            savedRow = row
            savedColumn = column
            state = .normal
        case 0x38: // 8
            row = savedRow
            column = savedColumn
            state = .normal
        case 0x28, 0x29: // character set selection
            state = .charset
        default:
            state = .normal
        }
    }

    private func processCSI(_ byte: UInt8) {
        guard (0x40...0x7E).contains(byte) else {
            // A malformed child stream must not grow this buffer without bound.
            guard csiBytes.count < 128 else {
                csiBytes.removeAll(keepingCapacity: true)
                state = .normal
                return
            }
            csiBytes.append(byte)
            return
        }

        let command = Character(UnicodeScalar(byte))
        let parameters = parsedParameters()
        applyCSI(command, parameters: parameters)
        csiBytes.removeAll(keepingCapacity: true)
        state = .normal
    }

    private func parsedParameters() -> [Int] {
        let source = String(bytes: csiBytes, encoding: .ascii) ?? ""
        let cleaned = source.filter { $0.isNumber || $0 == ";" || $0 == "-" }
        guard !cleaned.isEmpty else { return [] }
        return cleaned.split(separator: ";", omittingEmptySubsequences: false).map {
            Int($0) ?? 0
        }
    }

    private func applyCSI(_ command: Character, parameters: [Int]) {
        let first = parameters.first ?? 0
        switch command {
        case "A": row = max(0, row - max(first, 1))
        case "B": row = min(rows - 1, row + max(first, 1))
        case "C": column = min(columns - 1, column + max(first, 1))
        case "D": column = max(0, column - max(first, 1))
        case "E":
            row = min(rows - 1, row + max(first, 1))
            column = 0
        case "F":
            row = max(0, row - max(first, 1))
            column = 0
        case "G": column = clamp((first == 0 ? 1 : first) - 1, upper: columns - 1)
        case "d": row = clamp((first == 0 ? 1 : first) - 1, upper: rows - 1)
        case "H", "f":
            let targetRow = (parameters.indices.contains(0) ? parameters[0] : 1)
            let targetColumn = (parameters.indices.contains(1) ? parameters[1] : 1)
            row = clamp((targetRow == 0 ? 1 : targetRow) - 1, upper: rows - 1)
            column = clamp((targetColumn == 0 ? 1 : targetColumn) - 1, upper: columns - 1)
        case "J":
            if first == 2 || first == 3 {
                clearScreen()
            }
        case "K": clearLine(mode: first)
        case "s":
            savedRow = row
            savedColumn = column
        case "u":
            row = savedRow
            column = savedColumn
        default:
            break
        }
    }

    private func put(_ byte: UInt8) {
        guard rows > 0, columns > 0 else { return }
        cells[row][column] = byte
        column += 1
        if column >= columns {
            column = 0
            moveDown()
        }
    }

    private func moveDown() {
        row += 1
        if row >= rows {
            cells.removeFirst()
            cells.append(Array(repeating: 0x20, count: columns))
            row = rows - 1
        }
    }

    private func clearScreen() {
        cells = Array(
            repeating: Array(repeating: 0x20, count: columns),
            count: rows
        )
        row = 0
        column = 0
    }

    private func clearLine(mode: Int) {
        switch mode {
        case 1:
            guard column >= 0 else { return }
            for index in 0...min(column, columns - 1) {
                cells[row][index] = 0x20
            }
        case 2:
            cells[row] = Array(repeating: 0x20, count: columns)
        default:
            guard column < columns else { return }
            for index in column..<columns {
                cells[row][index] = 0x20
            }
        }
    }

    private func clamp(_ value: Int, upper: Int) -> Int {
        min(max(value, 0), upper)
    }
}
