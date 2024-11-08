import Foundation
import SwiftUI

extension InlineNode {
    func renderAttributedString(
        baseURL: URL?,
        textStyles: InlineTextStyles,
        softBreakMode: SoftBreak.Mode,
        attributes: AttributeContainer
    ) -> AttributedString {
        var renderer = AttributedStringInlineRenderer(
            baseURL: baseURL,
            textStyles: textStyles,
            softBreakMode: softBreakMode,
            attributes: attributes
        )
        renderer.render(self)
        return renderer.result.resolvingFonts()
    }
}

private struct AttributedStringInlineRenderer {
    var result = AttributedString()
    
    private let baseURL: URL?
    private let textStyles: InlineTextStyles
    private let softBreakMode: SoftBreak.Mode
    private var attributes: AttributeContainer
    private var shouldSkipNextWhitespace = false
    
    init(
        baseURL: URL?,
        textStyles: InlineTextStyles,
        softBreakMode: SoftBreak.Mode,
        attributes: AttributeContainer
    ) {
        self.baseURL = baseURL
        self.textStyles = textStyles
        self.softBreakMode = softBreakMode
        self.attributes = attributes
    }
    
    mutating func render(_ inline: InlineNode) {
        switch inline {
        case .text(let content):
            self.renderText(content)
        case .softBreak:
            self.renderSoftBreak()
        case .lineBreak:
            self.renderLineBreak()
        case .code(let content):
            self.renderCode(content)
        case .html(let content, let children):
            self.renderHTML(content, children: children)
        case .emphasis(let children):
            self.renderEmphasis(children: children)
        case .strong(let children):
            self.renderStrong(children: children)
        case .strikethrough(let children):
            self.renderStrikethrough(children: children)
        case .link(let destination, let children):
            self.renderLink(destination: destination, children: children)
        case .image(let source, let children):
            self.renderImage(source: source, children: children)
        case .underline(let children):
            self.renderUnderline(children: children)
        case .subscript(let children):
            self.renderSubscript(children: children)
        case .superscript(let children):
            self.renderSuperscript(children: children)
        case .style(let style, let children):
            self.renderStyle(style: style, children: children)
        }
    }
    
    private mutating func renderText(_ text: String) {
        var text = text
        
        if self.shouldSkipNextWhitespace {
            self.shouldSkipNextWhitespace = false
            text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
        }
        
        self.result += .init(text, attributes: self.attributes)
    }
    
    private mutating func renderSoftBreak() {
        switch softBreakMode {
        case .space where self.shouldSkipNextWhitespace:
            self.shouldSkipNextWhitespace = false
        case .space:
            self.result += .init(" ", attributes: self.attributes)
        case .lineBreak:
            self.renderLineBreak()
        }
    }
    
    private mutating func renderLineBreak() {
        self.result += .init("\n", attributes: self.attributes)
    }
    
    private mutating func renderCode(_ code: String) {
        self.result += .init(code, attributes: self.textStyles.code.mergingAttributes(self.attributes))
    }
    
    
    private mutating func renderHTML(_ node: String, children: [InlineNode]) {
        let savedAttributes = self.attributes
        for child in children {
            self.render(child)
        }
        self.attributes = savedAttributes
    }
    
//    private mutating func renderHTML(_ html: String) {
//        let tag = HTMLTag(html)
//        
//        switch tag?.name.lowercased() {
//        case "br":
//            self.renderLineBreak()
//            self.shouldSkipNextWhitespace = true
//        default:
//            self.renderText(html)
//        }
//    }
    
    private mutating func renderEmphasis(children: [InlineNode]) {
        let savedAttributes = self.attributes
        self.attributes = self.textStyles.emphasis.mergingAttributes(self.attributes)
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
    
    private mutating func renderStrong(children: [InlineNode]) {
        let savedAttributes = self.attributes
        self.attributes = self.textStyles.strong.mergingAttributes(self.attributes)
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
    
    private mutating func renderStrikethrough(children: [InlineNode]) {
        let savedAttributes = self.attributes
        self.attributes = self.textStyles.strikethrough.mergingAttributes(self.attributes)
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
    
    private mutating func renderUnderline(children: [InlineNode]) {
        let savedAttributes = self.attributes
        self.attributes = self.textStyles.underline.mergingAttributes(self.attributes)
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
    
    private mutating func renderSubscript(children: [InlineNode]) {
        let savedAttributes = self.attributes
        
        self.attributes.subscript()
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
    
    private mutating func renderSuperscript(children: [InlineNode]) {
        let savedAttributes = self.attributes
        
        self.attributes.superscript()
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
    
    private mutating func renderLink(destination: String, children: [InlineNode]) {
        let savedAttributes = self.attributes
        self.attributes = self.textStyles.link.mergingAttributes(self.attributes)
        self.attributes.link = URL(string: destination, relativeTo: self.baseURL)
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
    
    private mutating func renderImage(source: String, children: [InlineNode]) {
        // AttributedString does not support images
    }
    
    private mutating func renderStyle(style: InlineStyle, children: [InlineNode]) {
        let savedAttributes = self.attributes
        
        if let font = style.font {
            attributes.fontProperties?.family = .custom(font)
        }
        
        if let html = style.size {
            
            var relative: RelativeSize?
            
            if let scale = Double.from(html: html) {
                self.attributes.fontProperties?.scale = scale
            } else if let percent = html.firstMatch(of: #"\d+(?=%)"#), let scale = Double(percent) {
                self.attributes.fontProperties?.scale = scale / 100
            } else if let pixels = html.firstMatch(of: #"\d+(?=px)"#), let size = Double(pixels) {
                self.attributes.fontProperties?.size = size
            } else if let rem = html.firstMatch(of: #"(\d*[.])?\d+(?=rem)"#), let value = Double(rem) {
                relative = .rem(value)
            } else if let em = html.firstMatch(of: #"(\d*[.])?\d+(?=em)"#), let value = Double(em) {
                relative = .em(value)
            } else if let ex = html.firstMatch(of: #"(\d*[.])?\d+(?=ex)"#), let value = Double(ex) {
                print(value)
                //relative = .ex(value)
            }
            
            if let size = relative?.points(relativeTo: attributes.fontProperties) {
                attributes.fontProperties?.size = size
            } else if let scale = Double(html) {
                attributes.fontProperties?.scale = scale / 3
            }
        }
        
        if let html = style.foregroundColor, let color = Color.from(html: html) {
            attributes.foregroundColor = color
        }
        
        if let html = style.backgroundColor, let color = Color.from(html: html) {
            attributes.backgroundColor = color
        }
        
        /* Not supported yet
         if let alignment = style.alignment {
         let p = NSMutableParagraphStyle()
         p.alignment = alignment
         attributes.paragraphStyle = p
         }*/
        
        for child in children {
            self.render(child)
        }
        
        self.attributes = savedAttributes
    }
}

extension TextStyle {
    fileprivate func mergingAttributes(_ attributes: AttributeContainer) -> AttributeContainer {
        var newAttributes = attributes
        self._collectAttributes(in: &newAttributes)
        return newAttributes
    }
}

extension AttributeContainer {
    mutating func `subscript`() {
        script(.em(-0.25), size: .em(0.7))
    }
    
    mutating func superscript() {
        script(.em(0.5), size: .em(0.7))
    }
    
    mutating func script(_ baselineOffset: RelativeSize, size: RelativeSize) {
        self.baselineOffset = baselineOffset.points(relativeTo: self.fontProperties)
        var properties = self.fontProperties
        properties?.size = size.points(relativeTo: self.fontProperties)
        self.fontProperties = properties
    }
}
