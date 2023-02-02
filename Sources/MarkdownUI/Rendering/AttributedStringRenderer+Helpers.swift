import UIKit

protocol Parent {
    var inlines: [Inlinable] { get set }
}
extension Parent {
    func rendered(with render: ([Inline]) -> NSAttributedString) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        inlines.forEach { i in
            switch i {
            case .inline(let inline):
                result.append(render([inline]))
            case .render(let render):
                result.append(render)
            }
        }
        return result
    }
}

extension Strong: Parent {
    var inlines: [Inlinable] {
        get { children.map { .inline($0)} }
        set { children = newValue.compactMap { $0.inlineUnwrapped } }
    }
}
extension Emphasis: Parent {
    var inlines: [Inlinable] {
        get { children.map { .inline($0)} }
        set { children = newValue.compactMap { $0.inlineUnwrapped } }
    }

}
extension CommonMark.Link: Parent {
    var inlines: [Inlinable] {
        get { children.map { .inline($0)} }
        set { children = newValue.compactMap { $0.inlineUnwrapped } }
    }
}

enum Inlinable {
    case inline(Inline)
    case render(NSAttributedString)
    
    var inlineUnwrapped: Inline? {
        if case .inline(let inline) = self {
            return inline
        }
        return nil
    }
}


struct InlineStyle: Parent {
    var font: MarkdownStyle.Font?
    var color: UIColor?
    var inlines: [Inlinable]
}

struct InlineHeading: Parent {
    let level: Int
    var color: UIColor?
    var inlines: [Inlinable]
}

struct InlineParagraph: Parent {
    let style: NSParagraphStyle
    var inlines: [Inlinable]
}
struct InlineUnderline: Parent {
    var inlines: [Inlinable]
}

struct InlineTable {
    let columns: Int
    var width: [CGFloat]
    var children: [[NSAttributedString]] = [[]]
    
    enum Alignment {
        case leading
        case center
        case trailing
    }
    
    init(columns: Int) {
        self.columns = columns
        self.width = Array(repeating: 0, count: columns)
    }
    
    mutating func setWidth(_ newWidth: CGFloat, column: Int) {
        let old = width[column]
        width[column] = max(old, newWidth)
    }
    
    var currentColumn: Int {
        let line = children.last
        let column = line?.count ?? 0
        return column % columns
    }
    
    var alignments: [Alignment] {
        guard children.count > 1 else { return [] }
        let alignments = children[1]
        return alignments.map {
            let prefix = $0.string.hasPrefix(":")
            let suffix = $0.string.hasSuffix(":")
            if prefix && suffix {
                return .center
            } else if suffix {
                return .trailing
            } else {
                return .leading
            }
        }
    }
    
    mutating func nextLine() {
        children.append([])
    }
    
    mutating func append(row: NSAttributedString) {
        let column = currentColumn
        setWidth(row.size().width, column: column)
        if column < columns {
            var line = children.removeLast()
            line.append(row)
            children.append(line)
        } else {
            children.append([row])
        }
    }
    
    mutating func append(rows: [NSAttributedString]) {
        guard !rows.isEmpty else { return }
        let column = currentColumn
        rows.enumerated().forEach { idx, row in
            setWidth(row.size().width, column: column + idx)
        }
        
        let line = children.removeLast()
        children.append(line + rows)
    }
}



// MARK: - Extensions
extension String {
    func regex(pattern: String) -> [String] {
        do {
            let string = self as NSString
            let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
            let range = NSRange(location: 0, length: string.length)
            let matches = regex.matches(in: self, range: range)
            return matches.map { string.substring(with: $0.range) }
        } catch {
            return []
        }
    }
    
    func ranges(pattern: String) -> [NSRange] {
        do {
            let string = self as NSString
            let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
            let range = NSRange(location: 0, length: string.length)
            let matches = regex.matches(in: self, range: range)
            return matches.map { $0.range }
        } catch {
            return []
        }
    }
}

public extension CGColor {
    func hexString() -> String {
        let r = components?[0] ?? 0
        let g = components?[1] ?? 0
        let b = components?[2] ?? 0
        return String(format: "%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
     }
}

public extension UIColor {
    
    static func from(html: String) -> UIColor? {
        html.isEmpty ? nil :
        UIColor(name: html) ?? UIColor(rgb: html) ?? UIColor(hexString: html)
    }
        
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    convenience init?(name: String) {
        let allColors = [
            "aliceblue": "#F0F8FFFF",
            "antiquewhite": "#FAEBD7FF",
            "aqua": "#00FFFFFF",
            "aquamarine": "#7FFFD4FF",
            "azure": "#F0FFFFFF",
            "beige": "#F5F5DCFF",
            "bisque": "#FFE4C4FF",
            "black": "#000000FF",
            "blanchedalmond": "#FFEBCDFF",
            "blue": "#0000FFFF",
            "blueviolet": "#8A2BE2FF",
            "brown": "#A52A2AFF",
            "burlywood": "#DEB887FF",
            "cadetblue": "#5F9EA0FF",
            "chartreuse": "#7FFF00FF",
            "chocolate": "#D2691EFF",
            "coral": "#FF7F50FF",
            "cornflowerblue": "#6495EDFF",
            "cornsilk": "#FFF8DCFF",
            "crimson": "#DC143CFF",
            "cyan": "#00FFFFFF",
            "darkblue": "#00008BFF",
            "darkcyan": "#008B8BFF",
            "darkgoldenrod": "#B8860BFF",
            "darkgray": "#A9A9A9FF",
            "darkgrey": "#A9A9A9FF",
            "darkgreen": "#006400FF",
            "darkkhaki": "#BDB76BFF",
            "darkmagenta": "#8B008BFF",
            "darkolivegreen": "#556B2FFF",
            "darkorange": "#FF8C00FF",
            "darkorchid": "#9932CCFF",
            "darkred": "#8B0000FF",
            "darksalmon": "#E9967AFF",
            "darkseagreen": "#8FBC8FFF",
            "darkslateblue": "#483D8BFF",
            "darkslategray": "#2F4F4FFF",
            "darkslategrey": "#2F4F4FFF",
            "darkturquoise": "#00CED1FF",
            "darkviolet": "#9400D3FF",
            "deeppink": "#FF1493FF",
            "deepskyblue": "#00BFFFFF",
            "dimgray": "#696969FF",
            "dimgrey": "#696969FF",
            "dodgerblue": "#1E90FFFF",
            "firebrick": "#B22222FF",
            "floralwhite": "#FFFAF0FF",
            "forestgreen": "#228B22FF",
            "fuchsia": "#FF00FFFF",
            "gainsboro": "#DCDCDCFF",
            "ghostwhite": "#F8F8FFFF",
            "gold": "#FFD700FF",
            "goldenrod": "#DAA520FF",
            "gray": "#808080FF",
            "grey": "#808080FF",
            "green": "#008000FF",
            "greenyellow": "#ADFF2FFF",
            "honeydew": "#F0FFF0FF",
            "hotpink": "#FF69B4FF",
            "indianred": "#CD5C5CFF",
            "indigo": "#4B0082FF",
            "ivory": "#FFFFF0FF",
            "khaki": "#F0E68CFF",
            "lavender": "#E6E6FAFF",
            "lavenderblush": "#FFF0F5FF",
            "lawngreen": "#7CFC00FF",
            "lemonchiffon": "#FFFACDFF",
            "lightblue": "#ADD8E6FF",
            "lightcoral": "#F08080FF",
            "lightcyan": "#E0FFFFFF",
            "lightgoldenrodyellow": "#FAFAD2FF",
            "lightgray": "#D3D3D3FF",
            "lightgrey": "#D3D3D3FF",
            "lightgreen": "#90EE90FF",
            "lightpink": "#FFB6C1FF",
            "lightsalmon": "#FFA07AFF",
            "lightseagreen": "#20B2AAFF",
            "lightskyblue": "#87CEFAFF",
            "lightslategray": "#778899FF",
            "lightslategrey": "#778899FF",
            "lightsteelblue": "#B0C4DEFF",
            "lightyellow": "#FFFFE0FF",
            "lime": "#00FF00FF",
            "limegreen": "#32CD32FF",
            "linen": "#FAF0E6FF",
            "magenta": "#FF00FFFF",
            "maroon": "#800000FF",
            "mediumaquamarine": "#66CDAAFF",
            "mediumblue": "#0000CDFF",
            "mediumorchid": "#BA55D3FF",
            "mediumpurple": "#9370D8FF",
            "mediumseagreen": "#3CB371FF",
            "mediumslateblue": "#7B68EEFF",
            "mediumspringgreen": "#00FA9AFF",
            "mediumturquoise": "#48D1CCFF",
            "mediumvioletred": "#C71585FF",
            "midnightblue": "#191970FF",
            "mintcream": "#F5FFFAFF",
            "mistyrose": "#FFE4E1FF",
            "moccasin": "#FFE4B5FF",
            "navajowhite": "#FFDEADFF",
            "navy": "#000080FF",
            "oldlace": "#FDF5E6FF",
            "olive": "#808000FF",
            "olivedrab": "#6B8E23FF",
            "orange": "#FFA500FF",
            "orangered": "#FF4500FF",
            "orchid": "#DA70D6FF",
            "palegoldenrod": "#EEE8AAFF",
            "palegreen": "#98FB98FF",
            "paleturquoise": "#AFEEEEFF",
            "palevioletred": "#D87093FF",
            "papayawhip": "#FFEFD5FF",
            "peachpuff": "#FFDAB9FF",
            "peru": "#CD853FFF",
            "pink": "#FFC0CBFF",
            "plum": "#DDA0DDFF",
            "powderblue": "#B0E0E6FF",
            "purple": "#800080FF",
            "rebeccapurple": "#663399FF",
            "red": "#FF0000FF",
            "rosybrown": "#BC8F8FFF",
            "royalblue": "#4169E1FF",
            "saddlebrown": "#8B4513FF",
            "salmon": "#FA8072FF",
            "sandybrown": "#F4A460FF",
            "seagreen": "#2E8B57FF",
            "seashell": "#FFF5EEFF",
            "sienna": "#A0522DFF",
            "silver": "#C0C0C0FF",
            "skyblue": "#87CEEBFF",
            "slateblue": "#6A5ACDFF",
            "slategray": "#708090FF",
            "slategrey": "#708090FF",
            "snow": "#FFFAFAFF",
            "springgreen": "#00FF7FFF",
            "steelblue": "#4682B4FF",
            "tan": "#D2B48CFF",
            "teal": "#008080FF",
            "thistle": "#D8BFD8FF",
            "tomato": "#FF6347FF",
            "turquoise": "#40E0D0FF",
            "violet": "#EE82EEFF",
            "wheat": "#F5DEB3FF",
            "white": "#FFFFFFFF",
            "whitesmoke": "#F5F5F5FF",
            "yellow": "#FFFF00FF",
            "yellowgreen": "#9ACD32FF"
        ]

        let cleanedName = name.replacingOccurrences(of: " ", with: "").lowercased()
        if let hexString = allColors[cleanedName] {
            self.init(hexString: hexString)
        } else {
            return nil
        }
    }
    
    convenience init?(rgb: String) {
        // rgb(43, 128, 197)
        guard let value = rgb.regex(pattern: #"(?<=rgb\()[^\)]+"#).first else { return nil }
        let scanner = Scanner(string: value)
        scanner.charactersToBeSkipped = .decimalDigits.inverted
        let r = scanner.scanDouble(representation: .decimal) ?? 0
        let g = scanner.scanDouble(representation: .decimal) ?? 0
        let b = scanner.scanDouble(representation: .decimal) ?? 0
        self.init(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}
