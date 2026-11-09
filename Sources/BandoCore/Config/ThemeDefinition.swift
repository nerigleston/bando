import Foundation

/// Tema da interface e do terminal.
public struct ThemeDefinition: Sendable, Equatable, Identifiable {
    public enum Appearance: String, Codable, Sendable { case light, dark }

    public var id: String
    public var name: String
    public var appearance: Appearance
    public var accent: RGB
    public var background: RGB
    public var foreground: RGB
    public var cursor: RGB
    public var selection: RGB
    /// 16 cores ANSI: 8 normais e 8 claras.
    public var ansi: [RGB]

    public init(id: String, name: String, appearance: Appearance, accent: RGB, background: RGB,
                foreground: RGB, cursor: RGB, selection: RGB, ansi: [RGB]) {
        self.id = id; self.name = name; self.appearance = appearance; self.accent = accent
        self.background = background; self.foreground = foreground; self.cursor = cursor
        self.selection = selection; self.ansi = ansi
    }

    /// Arquivo do logo que combina com o tema (preto no claro, branco no escuro).
    public var logoResource: String {
        appearance == .dark ? "bando-completo-branco" : "bando-completo-preto"
    }
}

/// Cor em hexadecimal (#RRGGBB).
public struct RGB: Sendable, Equatable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = UInt8((v >> 16) & 0xFF); g = UInt8((v >> 8) & 0xFF); b = UInt8(v & 0xFF)
    }

    public var description: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// Componentes de 0 a 1.
    public var unit: (Double, Double, Double) { (Double(r) / 255, Double(g) / 255, Double(b) / 255) }
}

struct ThemeEntry: Codable, Sendable {
    var name: String?
    var appearance: ThemeDefinition.Appearance?
    var accent: String?
    var background: String?
    var foreground: String?
    var cursor: String?
    var selection: String?
    var ansi: [String]?
    var enabled: Bool?
    /// Tema usado como base para os campos que faltam.
    var base: String?

    func merged(with o: ThemeEntry) -> ThemeEntry {
        ThemeEntry(
            name: o.name ?? name, appearance: o.appearance ?? appearance, accent: o.accent ?? accent,
            background: o.background ?? background, foreground: o.foreground ?? foreground,
            cursor: o.cursor ?? cursor, selection: o.selection ?? selection, ansi: o.ansi ?? ansi,
            enabled: o.enabled ?? enabled, base: o.base ?? base
        )
    }

    func resolved(id: String) throws -> ThemeDefinition {
        let section = "themes.\(id)"
        func color(_ field: String, _ value: String?) throws -> RGB {
            guard let value else { throw ConfigError.missingField(section: section, field: field) }
            guard let c = RGB(hex: value) else {
                throw ConfigError.invalidValue(section: section, field: field, detail: "cor inválida \(value); use #RRGGBB")
            }
            return c
        }
        guard let appearance else { throw ConfigError.missingField(section: section, field: "appearance") }
        let bg = try color("background", background)
        let fg = try color("foreground", foreground)
        guard let ansi, ansi.count == 16 else {
            throw ConfigError.invalidValue(section: section, field: "ansi", detail: "precisa de 16 cores")
        }
        return ThemeDefinition(
            id: id, name: name ?? id, appearance: appearance,
            accent: try accent.map { try color("accent", $0) } ?? fg,
            background: bg, foreground: fg,
            cursor: try cursor.map { try color("cursor", $0) } ?? fg,
            selection: try selection.map { try color("selection", $0) } ?? fg,
            ansi: try ansi.enumerated().map { try color("ansi[\($0.offset)]", $0.element) }
        )
    }
}

struct ThemesFile: Codable {
    var themes: [String: ThemeEntry]?
}
