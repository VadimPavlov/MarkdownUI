import CommonMark
import SwiftUI

struct AttributedStringRenderer {
  struct State {
    var font: MarkdownStyle.Font
    var foregroundColor: SwiftUI.Color
    var paragraphSpacing: CGFloat
    var headIndent: CGFloat = 0
    var tailIndent: CGFloat = 0
    var tabStops: [NSTextTab] = []
    var paragraphEdits: [ParagraphEdit] = []

    mutating func setListMarker(_ listMarker: ListMarker?) {
      // Replace any previous list marker by two indents
      paragraphEdits = paragraphEdits.map { edit in
        guard case .listMarker = edit else { return edit }
        return .firstLineIndent(2)
      }
      guard let listMarker = listMarker else { return }
      paragraphEdits.append(.listMarker(listMarker, font: font))
    }

    mutating func addFirstLineIndent(_ count: Int = 1) {
      paragraphEdits.append(.firstLineIndent(count))
    }
  }

  enum ParagraphEdit {
    case firstLineIndent(Int)
    case listMarker(ListMarker, font: MarkdownStyle.Font)
  }

  enum ListMarker {
    case disc
    case decimal(Int)
  }

  let environment: Environment

  func renderDocument(_ document: Document) -> NSAttributedString {
    return renderBlocks(
      document.blocks,
      state: .init(
        font: environment.style.font,
        foregroundColor: environment.style.foregroundColor,
        paragraphSpacing: environment.style.measurements.paragraphSpacing
      )
    )
  }
}

extension AttributedStringRenderer {
  private func renderBlocks(_ blocks: [Block], state: State) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()

    for (offset, block) in blocks.enumerated() {
      result.append(
        renderBlock(block, hasSuccessor: offset < blocks.count - 1, state: state)
      )
    }

    return result
  }

  private func renderBlock(
    _ block: Block,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    switch block {
    case .blockQuote(let blockQuote):
      return renderBlockQuote(blockQuote, hasSuccessor: hasSuccessor, state: state)
    case .bulletList(let bulletList):
      return renderBulletList(bulletList, hasSuccessor: hasSuccessor, state: state)
    case .orderedList(let orderedList):
      return renderOrderedList(orderedList, hasSuccessor: hasSuccessor, state: state)
    case .code(let codeBlock):
      return renderCodeBlock(codeBlock, hasSuccessor: hasSuccessor, state: state)
    case .html(let htmlBlock):
      return renderHTMLBlock(htmlBlock, hasSuccessor: hasSuccessor, state: state)
    case .paragraph(let paragraph):
      return renderParagraph(paragraph, hasSuccessor: hasSuccessor, state: state)
    case .heading(let heading):
      return renderHeading(heading, hasSuccessor: hasSuccessor, state: state)
    case .thematicBreak:
      return renderThematicBreak(hasSuccessor: hasSuccessor, state: state)
    }
  }

  private func renderBlockQuote(
    _ blockQuote: BlockQuote,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    var state = state
    state.font = state.font.italic()
    state.headIndent += environment.style.measurements.headIndentStep
    state.tailIndent += environment.style.measurements.tailIndentStep
    state.tabStops.append(
      .init(textAlignment: .natural, location: state.headIndent)
    )
    state.addFirstLineIndent()

    for (offset, item) in blockQuote.items.enumerated() {
      result.append(
        renderBlock(item, hasSuccessor: offset < blockQuote.items.count - 1, state: state)
      )
    }

    if hasSuccessor {
      result.append(string: .paragraphSeparator)
    }

    return result
  }

  private func renderBulletList(
    _ bulletList: BulletList,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    var itemState = state
    itemState.paragraphSpacing =
      bulletList.tight ? 0 : environment.style.measurements.paragraphSpacing
    itemState.headIndent += environment.style.measurements.headIndentStep
    itemState.tabStops.append(
      contentsOf: [
        .init(
          textAlignment: .trailing(environment.baseWritingDirection),
          location: itemState.headIndent - environment.style.measurements.listMarkerSpacing
        ),
        .init(textAlignment: .natural, location: itemState.headIndent),
      ]
    )
    itemState.setListMarker(nil)

    for (offset, item) in bulletList.items.enumerated() {
      result.append(
        renderListItem(
          item,
          listMarker: .disc,
          parentParagraphSpacing: state.paragraphSpacing,
          hasSuccessor: offset < bulletList.items.count - 1,
          state: itemState
        )
      )
    }

    if hasSuccessor {
      result.append(string: .paragraphSeparator)
    }

    return result
  }

  private func renderOrderedList(
    _ orderedList: OrderedList,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // Measure the width of the highest list number in em units and use it
    // as the head indent step if higher than the style's head indent step.
    let highestNumber = orderedList.start + orderedList.items.count - 1
    let headIndentStep = max(
      environment.style.measurements.headIndentStep,
      NSAttributedString(
        string: "\(highestNumber).",
        attributes: [
          .font: state.font.monospacedDigit().resolve(sizeCategory: environment.sizeCategory)
        ]
      ).em() + environment.style.measurements.listMarkerSpacing
    )

    var itemState = state
    itemState.paragraphSpacing =
      orderedList.tight ? 0 : environment.style.measurements.paragraphSpacing
    itemState.headIndent += headIndentStep
    itemState.tabStops.append(
      contentsOf: [
        .init(
          textAlignment: .trailing(environment.baseWritingDirection),
          location: itemState.headIndent - environment.style.measurements.listMarkerSpacing
        ),
        .init(textAlignment: .natural, location: itemState.headIndent),
      ]
    )
    itemState.setListMarker(nil)

    for (offset, item) in orderedList.items.enumerated() {
      result.append(
        renderListItem(
          item,
          listMarker: .decimal(offset + orderedList.start),
          parentParagraphSpacing: state.paragraphSpacing,
          hasSuccessor: offset < orderedList.items.count - 1,
          state: itemState
        )
      )
    }

    if hasSuccessor {
      result.append(string: .paragraphSeparator)
    }

    return result
  }

  private func renderListItem(
    _ listItem: ListItem,
    listMarker: ListMarker,
    parentParagraphSpacing: CGFloat,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    for (offset, block) in listItem.blocks.enumerated() {
      var blockState = state

      if offset == 0 {
        // The first block should have the list marker
        blockState.setListMarker(listMarker)
      } else {
        blockState.addFirstLineIndent(2)
      }

      if !hasSuccessor, offset == listItem.blocks.count - 1 {
        // Use the appropriate paragraph spacing after the list
        blockState.paragraphSpacing = max(parentParagraphSpacing, state.paragraphSpacing)
      }

      result.append(
        renderBlock(
          block,
          hasSuccessor: offset < listItem.blocks.count - 1,
          state: blockState
        )
      )
    }

    if hasSuccessor {
      result.append(string: .paragraphSeparator)
    }

    return result
  }

  private func renderCodeBlock(
    _ codeBlock: CodeBlock,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    var state = state
    state.font = state.font.scale(environment.style.measurements.codeFontScale).monospaced()
    state.headIndent += environment.style.measurements.headIndentStep
    state.tabStops.append(
      .init(textAlignment: .natural, location: state.headIndent)
    )
    state.addFirstLineIndent()

    var code = codeBlock.code.replacingOccurrences(of: "\n", with: String.lineSeparator)
    // Remove the last line separator
    code.removeLast()

    return renderParagraph(.init(text: [.text(code)]), hasSuccessor: hasSuccessor, state: state)
  }

  private func renderHTMLBlock(
    _ htmlBlock: HTMLBlock,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    var html = htmlBlock.html.replacingOccurrences(of: "\n", with: String.lineSeparator)
    // Remove the last line separator
    html.removeLast()

    // Render HTML blocks as html inline paragraphs
      return renderParagraph(.init(text: [.html(.init(html))]), hasSuccessor: hasSuccessor, state: state)
  }

  private func renderParagraph(
    _ paragraph: Paragraph,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    let result = renderParagraphEdits(state: state)
    result.append(renderInlines(paragraph.text, state: state))

    result.addAttribute(
      .paragraphStyle, value: paragraphStyle(state: state), range: NSRange(0..<result.length)
    )

    if hasSuccessor {
      result.append(string: .paragraphSeparator)
    }

    return result
  }

  private func renderHeading(
    _ heading: Heading,
    hasSuccessor: Bool,
    state: State
  ) -> NSAttributedString {
    let result = renderParagraphEdits(state: state)

    var inlineState = state
    inlineState.font = inlineState.font.bold().scale(
      environment.style.measurements.headingScales[heading.level - 1]
    )

    result.append(renderInlines(heading.text, state: inlineState))

    // The paragraph spacing is relative to the parent font
    var paragraphState = state
    paragraphState.paragraphSpacing = environment.style.measurements.headingSpacing

    result.addAttribute(
      .paragraphStyle,
      value: paragraphStyle(state: paragraphState),
      range: NSRange(0..<result.length)
    )

    if hasSuccessor {
      result.append(string: .paragraphSeparator)
    }

    return result
  }

  private func renderThematicBreak(hasSuccessor: Bool, state: State) -> NSAttributedString {
    let result = renderParagraphEdits(state: state)

    result.append(
      .init(
        string: .nbsp,
        attributes: [
          .font: state.font.resolve(sizeCategory: environment.sizeCategory),
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .strikethroughColor: PlatformColor.separator,
        ]
      )
    )

    result.addAttribute(
      .paragraphStyle,
      value: paragraphStyle(state: state),
      range: NSRange(0..<result.length)
    )

    if hasSuccessor {
      result.append(string: .paragraphSeparator)
    }

    return result
  }

  private func renderParagraphEdits(state: State) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()

    for paragraphEdit in state.paragraphEdits {
      switch paragraphEdit {
      case .firstLineIndent(let count):
        result.append(
          renderText(.init(repeating: "\t", count: count), state: state)
        )
      case .listMarker(let listMarker, let font):
        switch listMarker {
        case .disc:
          var state = state
          state.font = font
          result.append(renderText("\t•\t", state: state))
        case .decimal(let value):
          var state = state
          state.font = font.monospacedDigit()
          result.append(renderText("\t\(value).\t", state: state))
        }
      }
    }

    return result
  }

    struct FontInline {
        let color: UIColor
        var children: [Inline]
    }
    
  private func renderInlines(_ inlines: [Inline], state: State) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()

    var strong: Strong?
    var emphasis: Emphasis?
    var underline: [Inline]?
    var font: FontInline?
      
      func append(inline: Inline) {
          if strong != nil {
              strong?.children.append(inline)
          } else if emphasis != nil {
              emphasis?.children.append(inline)
          } else if font != nil {
              font?.children.append(inline)
          } else if underline != nil {
              underline?.append(inline)
          } else {
              result.append(renderInline(inline, state: state))
          }
      }
      
    for inline in inlines {
        if case .text(let text) = inline {
            switch text {
            case "**": strong = Strong(children: [])
            case "** ": strong = Strong(children: [])
            case " **":
                strong.map {
                    result.append(renderStrong($0, state: state))
                    strong = nil
                }
            default:
                append(inline: inline)
            }
        }
        else if case .html(let innerHTML) = inline {
            switch innerHTML.html {
            case "<i>": emphasis = Emphasis(children: [])
            case "</i>":
                emphasis.map {
                    result.append(renderEmphasis($0, state: state))
                    emphasis = nil
                }

            case "<b>": strong = Strong(children: [])
            case "</b>":
                strong.map {
                    result.append(renderStrong($0, state: state))
                    strong = nil
                }
            case "<u>": underline = []
            case "</u>":
                underline.map {
                    let inlines = renderInlines($0, state: state)
                    let string = NSMutableAttributedString(attributedString: inlines)
                    let range = NSRange(location: 0, length: string.length)
                    string.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    result.append(string)
                    underline = nil
                }
            case "</font>":
                font.map {
                    var state = state
                    state.foregroundColor = Color($0.color)
                    result.append(renderInlines($0.children, state: state))
                    font = nil
                }
                
            default:
                if innerHTML.html.hasPrefix("<font") {
                    let colorName = innerHTML.html.regex(pattern: #"(?<=color=\")[^"]+"#).first ?? ""
                    let color = UIColor(name: colorName) ?? UIColor(hexString: colorName)
                    font = color.map { FontInline(color: $0, children: []) }
                } else {
                    
                    result.append(renderInline(inline, state: state))
                }
            }
        } else {
            append(inline: inline)
        }
    }

    return result
  }

  private func renderInline(_ inline: Inline, state: State) -> NSAttributedString {
    switch inline {
    case .text(let text):
      return renderText(text, state: state)
    case .softBreak:
      return renderSoftBreak(state: state)
    case .lineBreak:
      return renderLineBreak(state: state)
    case .code(let inlineCode):
      return renderInlineCode(inlineCode, state: state)
    case .html(let inlineHTML):
      return renderInlineHTML(inlineHTML, state: state)
    case .emphasis(let emphasis):
      return renderEmphasis(emphasis, state: state)
    case .strong(let strong):
      return renderStrong(strong, state: state)
    case .link(let link):
      return renderLink(link, state: state)
    case .image(let image):
      return renderImage(image, state: state)
    }
  }

  private func renderText(_ text: String, state: State) -> NSAttributedString {
    NSAttributedString(
      string: text,
      attributes: [
        .font: state.font.resolve(sizeCategory: environment.sizeCategory),
        .foregroundColor: PlatformColor(state.foregroundColor),
      ]
    )
  }
    
  private func renderSoftBreak(state: State) -> NSAttributedString {
    renderText(" ", state: state)
  }

  private func renderLineBreak(state: State) -> NSAttributedString {
    renderText(.lineSeparator, state: state)
  }

  private func renderInlineCode(_ inlineCode: InlineCode, state: State) -> NSAttributedString {
    var state = state
    state.font = state.font.scale(environment.style.measurements.codeFontScale).monospaced()
    return renderText(inlineCode.code, state: state)
  }

  private func renderInlineHTML(_ inlineHTML: InlineHTML, state: State) -> NSAttributedString {
      let html = inlineHTML.html
      
      func renderValue(_ value: String) -> NSAttributedString {
          if let document = try? Document(markdown: value) {
              return renderDocument(document)
          } else {
              return renderText(value, state: state)
          }
      }
      
      if html == "<br>" || html == "<br/>" {
          return renderText(String.lineSeparator, state: state)
      } else if html.hasPrefix("<br>") {
          let value = html.components(separatedBy: "<br>").last ?? ""
          return renderValue(value)
      } else if html.hasPrefix("<ul>") {
          let value = html.regex(pattern: #"(?<=<ul>).+?(?=</ul>)"#).first ?? ""
          let listItems = value.regex(pattern: #"(?<=<li>).+?(?=</li>)"#)
//          let texts = listItems.map { Paragraph(text: [.text($0)]) }
//          let items = texts.map { ListItem(blocks: [.paragraph($0)]) }
//          let list = BulletList(items: items, tight: true)
//          return renderBulletList(list, hasSuccessor: true, state: state)
          
          let result = NSMutableAttributedString()
          listItems.forEach { item in
              result.append(renderText("• \(item)\n", state: state))
          }
          return result
      } else if html.hasPrefix("<h3>") {
          let value = html.regex(pattern: #"(?<=<h3>).+?(?=</h3>)"#).first ?? ""
          return renderHeading(.init(text: [.text(value)], level: 3), hasSuccessor: false, state: state)
      } else if html.hasPrefix("<i>") {
          let value = html.regex(pattern: #"(?<=<i>).+?(?=</i>)"#).first ?? ""
          let doc = try? Document(markdown: value)
          if case .paragraph(let p) = doc?.blocks.first {
              return renderEmphasis(Emphasis(children: p.text), state: state)
          } else {
              return renderEmphasis(Emphasis(value), state: state)
          }
      } else if html.hasPrefix("<span") && inlineHTML.html.contains("style=") {
          let icon = html.regex(pattern: #"(?<=class=\")[^"]+"#).first
          let fontName = html.regex(pattern: "(?<=font-family:)[^;]+").first
          let fontSize = html.regex(pattern: "(?<=font-size:)\\d+").first
          
          let stateFont = state.font.resolve(sizeCategory: environment.sizeCategory)
          let size = fontSize.flatMap { Int($0).map { CGFloat($0)}} ?? stateFont.pointSize
          let font = fontName.flatMap { UIFont(name: $0, size: size) } ?? stateFont
          return NSAttributedString(string: icon ?? "",
                                    attributes: [.font: font, .foregroundColor: PlatformColor(state.foregroundColor)])
      } else if html == "</span>" {
          return NSAttributedString(string: "")
      } else if html.contains("<img") {
          let src = html.regex(pattern: #"(?<=src=)[^> ]+"#).first?.replacingOccurrences(of: "\"", with: "")
          let alt = html.regex(pattern: #"(?<=alt=\")[^"]+"#).first
          let width = html.regex(pattern: "(?<=width=)\\d+").first
          let height = html.regex(pattern: "(?<=height=)\\d+").first
          let url: URL? = src.flatMap {
              var c = URLComponents(string: $0)
              c?.queryItems = [.init(name: "width", value: width), .init(name: "height", value: height)]
              return c?.url
          }
          
          let image = Image(url: url, alt: alt, title: nil)
          let result = NSMutableAttributedString(attributedString: renderImage(image, state: state))
          if let value = inlineHTML.html.components(separatedBy: ">").last, !value.isEmpty {
              return renderValue(value)
          }
          return result
      } else {
          return renderText(inlineHTML.html, state: state)
      }
  }

  private func renderEmphasis(_ emphasis: Emphasis, state: State) -> NSAttributedString {
    var state = state
    state.font = state.font.italic()
    return renderInlines(emphasis.children, state: state)
  }

  private func renderStrong(_ strong: Strong, state: State) -> NSAttributedString {
    var state = state
    state.font = state.font.bold()
    return renderInlines(strong.children, state: state)
  }

  private func renderLink(_ link: CommonMark.Link, state: State) -> NSAttributedString {
    let result = renderInlines(link.children, state: state)
    let absoluteURL =
      link.url
      .map(\.relativeString)
      .flatMap { URL(string: $0, relativeTo: environment.baseURL) }
      .map(\.absoluteURL)
    if let url = absoluteURL {
      result.addAttribute(.link, value: url, range: NSRange(0..<result.length))
    }
    #if os(macOS)
      if let title = link.title {
        result.addAttribute(.toolTip, value: title, range: NSRange(0..<result.length))
      }
    #endif

    return result
  }

  private func renderImage(_ image: CommonMark.Image, state: State) -> NSAttributedString {
    image.url
      .map(\.relativeString)
      .flatMap { URL(string: $0, relativeTo: environment.baseURL) }
      .map(\.absoluteURL)
      .map {
        NSAttributedString(markdownImageURL: $0)
      } ?? NSAttributedString()
  }

  private func paragraphStyle(state: State) -> NSParagraphStyle {
    let pointSize = state.font.resolve(sizeCategory: environment.sizeCategory).pointSize
    let result = NSMutableParagraphStyle()
    result.setParagraphStyle(.default)
    result.baseWritingDirection = environment.baseWritingDirection
    result.alignment = environment.alignment
    result.lineSpacing = environment.lineSpacing
    result.paragraphSpacing = round(pointSize * state.paragraphSpacing)
    result.headIndent = round(pointSize * state.headIndent)
    result.tailIndent = round(pointSize * state.tailIndent)
    result.tabStops = state.tabStops.map {
      NSTextTab(
        textAlignment: $0.alignment,
        location: round(pointSize * $0.location),
        options: $0.options
      )
    }
    return result
  }
}

extension String {
  fileprivate static let lineSeparator = "\u{2028}"
  fileprivate static let paragraphSeparator = "\u{2029}"
  fileprivate static let nbsp = "\u{00A0}"
}

extension NSMutableAttributedString {
  fileprivate func append(string: String) {
    self.append(
      .init(
        string: string,
        attributes: self.length > 0
          ? self.attributes(at: self.length - 1, effectiveRange: nil)
          : nil
      )
    )
  }
}

extension NSAttributedString {
  /// Returns the width of the string in `em` units.
  fileprivate func em() -> CGFloat {
    guard let font = attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
    else {
      fatalError("Font attribute not found!")
    }
    return size().width / font.pointSize
  }
}

extension NSTextAlignment {
  fileprivate static func trailing(_ writingDirection: NSWritingDirection) -> NSTextAlignment {
    switch writingDirection {
    case .rightToLeft:
      return .left
    default:
      return .right
    }
  }
}

// MARK: - PlatformColor

#if os(macOS)
  private typealias PlatformColor = NSColor

  extension NSColor {
    fileprivate static var separator: NSColor { .separatorColor }
  }
#elseif os(iOS) || os(tvOS)
  private typealias PlatformColor = UIColor
#endif

// MARK: - Helpers
public extension String {
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
}

extension UIColor {
    public convenience init?(hexString: String) {
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

    public convenience init?(name: String) {
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
}
