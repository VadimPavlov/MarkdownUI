import Foundation
import UIKit

enum InlineNode: Hashable {
  case text(String)
  case softBreak
  case lineBreak
  case code(String)
  case html(String, children: [InlineNode])
  case emphasis(children: [InlineNode])
  case strong(children: [InlineNode])
  case strikethrough(children: [InlineNode])
  case underline(children: [InlineNode])
  case `subscript`([InlineNode])
  case superscript([InlineNode])
  case link(destination: String, children: [InlineNode])
  case image(source: String, children: [InlineNode])
  case style(InlineStyle, children: [InlineNode])
}

extension InlineNode {
  var children: [InlineNode] {
    get {
      switch self {
      case .emphasis(let children):
        return children
      case .strong(let children):
        return children
      case .strikethrough(let children):
        return children
      case .underline(let children):
          return children
      case .subscript(let children):
          return children
      case .superscript(let children):
          return children
      case .link(_, let children):
        return children
      case .image(_, let children):
        return children
      case .html(_, let children):
          return children
      case .style(_, let children):
          return children
      default:
        return []
      }
    }

    set {
      switch self {
      case .emphasis:
        self = .emphasis(children: newValue)
      case .strong:
        self = .strong(children: newValue)
      case .strikethrough:
        self = .strikethrough(children: newValue)
      case .link(let destination, _):
        self = .link(destination: destination, children: newValue)
      case .image(let source, _):
        self = .image(source: source, children: newValue)
      default:
        break
      }
    }
  }
}

struct InlineStyle: Hashable {
    var font: String?
    var size: String?
    var alignment: NSTextAlignment?
    var foregroundColor: String?
    var backgroundColor: String?
}
