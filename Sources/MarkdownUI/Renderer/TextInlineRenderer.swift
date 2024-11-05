import SwiftUI

extension Sequence where Element == InlineNode {
  func renderText(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) -> some View {
    var renderer = TextInlineRenderer(
      baseURL: baseURL,
      textStyles: textStyles,
      images: images,
      softBreakMode: softBreakMode,
      attributes: attributes
    )
    renderer.render(self)
    return renderer.result
  }
}

private struct TextInlineRenderer {
  var text = Text("")
  var body: [AnyView] = []

  private let baseURL: URL?
  private let textStyles: InlineTextStyles
  private let images: [String: Image]
  private let softBreakMode: SoftBreak.Mode
  private let attributes: AttributeContainer
  private var shouldSkipNextWhitespace = false

  init(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) {
    self.baseURL = baseURL
    self.textStyles = textStyles
    self.images = images
    self.softBreakMode = softBreakMode
    self.attributes = attributes
  }
    
    // workaround to render text with alignment
    var result: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(body.enumerated()), id: \.offset) { $1 }
            text
        }
    }

  mutating func render<S: Sequence>(_ inlines: S) where S.Element == InlineNode {
    for inline in inlines {
      self.render(inline)
    }
  }

  private mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .html(let node, let children):
      self.renderHTML(node, children: children)
    case .image(let source, _):
      self.renderImage(source)
    default:
      self.defaultRender(inline)
    }
  }

  private mutating func renderText(_ text: String) {
    var text = text

    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }

    self.defaultRender(.text(text))
  }

  private mutating func renderSoftBreak() {
    switch self.softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.defaultRender(.softBreak)
    case .lineBreak:
      self.shouldSkipNextWhitespace = true
      self.defaultRender(.lineBreak)
    }
  }

    private mutating func renderHTML(_ node: String, children: [InlineNode]) {
        
        switch node {
        case "center":
            body.append(AnyView(self.text))
            let inline = InlineNode.html(node, children: children)
            let text = Text(inline.renderAttributedString(
                  baseURL: self.baseURL,
                  textStyles: self.textStyles,
                  softBreakMode: self.softBreakMode,
                  attributes: self.attributes
                )
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            body.append(AnyView(text))
            self.text = Text("")
        default:
            self.defaultRender(.html(node, children: children))
        }
  }

  private mutating func renderImage(_ source: String) {
    if let image = self.images[source] {
      self.text = self.text + Text(image)
    }
  }

  private mutating func defaultRender(_ inline: InlineNode) {
    self.text =
      self.text
      + Text(
        inline.renderAttributedString(
          baseURL: self.baseURL,
          textStyles: self.textStyles,
          softBreakMode: self.softBreakMode,
          attributes: self.attributes
        )
      )
  }
}
