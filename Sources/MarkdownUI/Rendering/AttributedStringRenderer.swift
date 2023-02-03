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
    
    private func renderInlineListItems(
        _ list: InlineListItems,
        hasSuccessor: Bool,
        state: State
    ) -> NSAttributedString {
        
        var itemState = state
        itemState.paragraphSpacing = 0
        //bulletList.tight ? 0 : environment.style.measurements.paragraphSpacing
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
        itemState.setListMarker(.disc)
        
        let result = list.rendered { self.renderInlines($0, state: itemState) }

//        for (offset, item) in bulletList.items.enumerated() {
//            result.append(
//                renderListItem(
//                    item,
//                    listMarker: .disc,
//                    parentParagraphSpacing: state.paragraphSpacing,
//                    hasSuccessor: offset < bulletList.items.count - 1,
//                    state: itemState
//                )
//            )
//        }
//
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
        let text: [Inline]
        if let doc = try? Document(markdown: "Paragraph" + html),
           case .paragraph(let p) = doc.blocks.first {
            text = Array(p.text.dropFirst())
        } else {
            text = [.html(.init(html))]
        }
        return renderParagraph(.init(text: text), hasSuccessor: hasSuccessor, state: state)
    }
    
    private func renderParagraph(
        _ paragraph: Paragraph,
        hasSuccessor: Bool,
        state: State
    ) -> NSAttributedString {
        let result = renderParagraphEdits(state: state)
        result.append(renderInlines(paragraph.text, state: state))
        if result.length > 0 && result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) == nil {
            let range = NSRange(0..<result.length)
            result.addAttribute(.paragraphStyle, value: paragraphStyle(state: state), range: range)
        }
        
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
    
    private func renderInlineHeading(
        _ heading: InlineHeading,
        hasSuccessor: Bool,
        state: State
    ) -> NSAttributedString {
        let result = renderParagraphEdits(state: state)
        
        var inlineState = state
        inlineState.font = inlineState.font.bold().scale(
            environment.style.measurements.headingScales[heading.level - 1]
        )
        
        result.append(heading.rendered { renderInlines($0, state: inlineState)})
        
        // The paragraph spacing is relative to the parent font
        var paragraphState = state
        paragraphState.paragraphSpacing = environment.style.measurements.headingSpacing
        
        let range = NSRange(0..<result.length)
        result.addAttribute(.paragraphStyle, value: paragraphStyle(state: paragraphState), range: range)
        if let color = heading.color {
            result.addAttribute(.foregroundColor, value: color, range: range)
        }
        
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
    
    private func renderInlines(_ inlines: [Inline], state: State) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        
        var parents: [Parent] = []
        var inlineTable: InlineTable?
        var inlineRow = NSMutableAttributedString()
        
        func append(inline: Inline) {
            if parents.isEmpty {
                if inlineTable == nil {
                    let render = renderInline(inline, state: state)
                    result.append(render)
                } else if inline == .lineBreak || inline == .softBreak {
                    inlineTable?.nextLine()
                } else {
                    let render = renderInlines([inline], state: state)
                    inlineRow.append(render)
                }
            } else {
                parents.indices.last.map {
                    parents[$0].inlines.append(.inline(inline))
                }
            }
        }
        
        func render<P: Parent>(string: (P) -> NSAttributedString) {
            if let p = parents.removeLast() as? P {
                let rendered = string(p)
                if parents.isEmpty {
                    result.append(rendered)
                } else {
                    parents.indices.last.map {
                        parents[$0].inlines.append(.render(rendered))
                    }
                }
            } else {
                fatalError("REMOVED WRONG THING")
            }
        }
                
        func renderInlineFont() {
            if let style = parents.last as? InlineStyle {
                let rendered = NSMutableAttributedString(attributedString: style.rendered { renderInlines($0, state: state) })
                let range = NSRange(0..<rendered.length)
                if let color = style.color {
                    rendered.addAttribute(.foregroundColor, value: color, range: range)
                }
                if let font = style.font {
                    let platformFont = font.resolve(sizeCategory: environment.sizeCategory)
                    rendered.addAttribute(.font, value: platformFont, range: range)
                }

                parents.removeLast()
                if parents.isEmpty {
                    if inlineTable == nil {
                        result.append(rendered)
                    } else {
                        inlineRow.append(rendered)
                    }
                } else {
                    parents.indices.last.map {
                        parents[$0].inlines.append(.render(rendered))
                    }
                }
            } else if !parents.isEmpty {
                fatalError("Last is not a style")
            }
        }
        
        func inlineStyle() -> InlineStyle? {
            for p in parents.reversed() {
                if let style = p as? InlineStyle {
                    return style
                }
            }
            return nil
        }
        
        for inline in inlines {
            if case .text(let text) = inline {
                // check for table
                lazy var tableValues = text
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: String.tableSeparator)
                
                if text.hasPrefix(.tableSeparator) && text.hasSuffix(.tableSeparator) && inlineTable == nil {
                    let columns = tableValues.count - 2
                    inlineTable = InlineTable(columns: columns)
                }
            
                if inlineTable != nil, let range = text.range(of: String.tableSeparator), !range.isEmpty  {
                    let alignments = inlineTable?.alignments ?? []
                    let column = inlineTable?.currentColumn ?? 0
                    var values = tableValues.filter { !$0.isEmpty }
                    
                    // check if we have unclosed <span>, apply it to a first element (until column)
                    
                    if parents.last is InlineStyle {
                        let first = values.removeFirst()
                        parents.indices.last.map {
                            parents[$0].inlines.append(.inline(.text(first)))
                        }
                        renderInlineFont()
                    }
                    
                    // check if we append to a complex table cell
                    if !inlineRow.string.isEmpty {
                        inlineTable?.append(row: inlineRow)
                        inlineRow = NSMutableAttributedString()
                    }
                    
                    let rows = values.enumerated().map { idx, value -> NSAttributedString in
                        let position = idx + column
                        let alignment = position < alignments.count ? alignments[position] : .leading
                        let text = alignment == .center ? value : value.trimmingCharacters(in: .whitespaces)
                        return renderText(text, state: state)
                    }
                    inlineTable?.append(rows: rows)
                } else {
                    append(inline: inline)
                }
            }
            else if case .html(let innerHTML) = inline {
                switch innerHTML.html {
                case "<u>":
                    parents.append(InlineUnderline(inlines: []))
                case "</u>":
                    render { (underline: InlineUnderline) in
                        let rendered = underline.rendered { renderInlines($0, state: state) }
                        let range = NSRange(0..<rendered.length)
                        rendered.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                        return rendered
                    }
                case "<center>":
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    let paragraph = InlineParagraph(style: style, inlines: [])
                    parents.append(paragraph)
                case "</center>":
                    render { (paragraph: InlineParagraph) in
                        let rendered = paragraph.rendered { renderInlines($0, state: state)}
                        let range = NSRange(0..<rendered.length)
                        rendered.addAttribute(.paragraphStyle, value: paragraph.style, range: range)
                        return rendered
                    }
                case "</a>":
                    render { renderLink($0, state: state) }
                case "</font>", "</span>":
                    renderInlineFont()
                default:
                    let html = innerHTML.html
                    
                    if let h = html.regex(pattern: #"(?<=<h)\d"#).first, let level = Int(h) {
                        // opening heading
                        let style = html.regex(pattern: #"(?<=style=)[^>]+"#).first ?? ""
                        let colorName = style.regex(pattern: #"(?<=color:)[^;]+"#).first ?? ""
                        let color = UIColor.from(html: colorName)
                        let heading = InlineHeading(level: level, color: color, inlines: [])
                        parents.append(heading)
                    } else if html.regex(pattern: #"</h\d>"#).first != nil {
                        // close heading
                        render { renderInlineHeading($0, hasSuccessor: false, state: state) }
                    } else if html.hasPrefix("<font") {
                        let colorName = html.regex(pattern: #"(?<=color=\")[^"]+"#).first ?? ""
                        if let color = UIColor.from(html: colorName) {
                            let style = InlineStyle(color: color, inlines: [])
                            parents.append(style)
                        }
                    } else if html.hasPrefix("<span") {
                        
                        let colorName = html.regex(pattern: #"(?<=color:)[^;]+"#).first ?? ""
                        let fontName = html.regex(pattern: "(?<=font-family:)[^;]+").first
                        let fontSize = html.regex(pattern: "(?<=font-size:)\\d+").first
                        
                        let color = UIColor.from(html: colorName)
                        
                        let font: MarkdownStyle.Font?
                        let stateFont = inlineStyle()?.font ?? state.font
                        let pointSize = stateFont.resolve(sizeCategory: environment.sizeCategory).pointSize
                        let size = fontSize.flatMap { Int($0).map { CGFloat($0)}}
                        
                        if let name = fontName, let size = size {
                            font = MarkdownStyle.Font.custom(name, size: size)
                        } else if let name = fontName {
                            font = MarkdownStyle.Font.custom(name, size: pointSize)
                        } else if let size = size {
                            let scale = size / pointSize
                            font = state.font.scale(scale)
                        } else {
                            font = nil
                        }
                        let style = InlineStyle(font: font, color: color, inlines: [])
                        parents.append(style)
                    } else if html.hasPrefix("<a ") {
                        let href = html.regex(pattern: #"(?<=href=")[^"]+"#).first ?? ""
                        let url = URL(string: href)
                        parents.append(Link(children: [], url: url))
                    } else {
                        append(inline: .html(innerHTML))
                    }
                }
            } else {
                append(inline: inline)
            }
        }
        
        // there might be no closing </span>, so we check here
        renderInlineFont()
        
        if let table = inlineTable {
            result.append(renderInlineTable(table, state: state))
        }
        return result
    }
    
    private func renderInlineTable(_ table: InlineTable, state: State) -> NSAttributedString {
        let font = state.font.resolve(sizeCategory: environment.sizeCategory)
        let space = String.thinSpace.size(withAttributes: [.font: font]).width
        
        let result = NSMutableAttributedString()
        let alignments = table.alignments
        table.children.enumerated().forEach { line, child in
            if line == 1 { return } // alignment
            child.enumerated().forEach { idx, row in
                guard table.width.count > idx else { return }
                let maxWidth = table.width[idx]
                let width = row.size().width
                let count = (maxWidth - width) / space
                
                let alignment = alignments[idx]
                switch alignment {
                case .center:
                    let half = Int((count / 2).rounded())
                    let spaces = String(repeating: String.thinSpace, count: half)
                    let padding = NSAttributedString(string: spaces, attributes: [.font: font])
                    result.append(padding)
                    result.append(row)
                    result.append(padding)
                case .leading:
                    let spaces = String(repeating: String.thinSpace, count: Int(count.rounded()))
                    let padding = NSAttributedString(string: spaces, attributes: [.font: font])
                    result.append(row)
                    result.append(padding)
                case .trailing:
                    let spaces = String(repeating: String.thinSpace, count: Int(count.rounded()))
                    let padding = NSAttributedString(string: spaces, attributes: [.font: font])
                    result.append(padding)
                    result.append(row)
                }
                result.append(string: " ") // spacing between columns
            }
            result.append(renderLineBreak(state: state))
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
        
        return NSAttributedString(
                string: inlineCode.code,
                attributes: [
                    .font: state.font.resolve(sizeCategory: environment.sizeCategory),
                    .foregroundColor: PlatformColor(hexString: "c7254e")!,
                    .backgroundColor: PlatformColor(hexString: "f9f2f4")!
                ]
        )
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
        
        func regex(from: String = html, for tag: String) -> [String] {
            from.regex(pattern: "(?<=<\(tag)>).+?(?=</\(tag)>)")
        }
        
        if html == "<br>" || html == "<br/>" || html == "</br>" {
            return renderText(String.lineSeparator, state: state)
        } else if html.hasPrefix("<br>") {
            let value = html.components(separatedBy: "<br>").last ?? ""
            return renderValue(value)
        } else if html == "<hr/>" {
            return renderThematicBreak(hasSuccessor: false, state: state)
        } else if html == "</p>" {
            return renderLineBreak(state: state)
        } else if html == "<ul>" || html == "</ul>" || html == "</li>" {
            // <li></li> tags are transofrmed into bullet list
            return renderText("", state: state)
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
        } else if html.hasPrefix("</") {
            // ignore any inpropertly closed tag
            print("INGORING TAG: \(html)")
            return NSAttributedString(string: "")
        } else {
            assert(!html.hasPrefix("<"), "Unhandled html tag\n\(html)")
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
    
    private func paragraphStyle(state: State) -> NSMutableParagraphStyle {
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
    
    fileprivate static let tableSeparator = "|"
    fileprivate static let thinSpace = " "
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
