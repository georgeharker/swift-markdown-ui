import SwiftUI

/// Parse `markdown` and delineate it into storable ``MarkdownEntity`` values.
///
/// PURE + off-main safe: parsing is cmark, prose styling uses value-type
/// `TextStyle` DSL, and no SwiftUI `Environment` is touched. Flowable blocks
/// (paragraph, heading) coalesce into `.prose(AttributedString)`; codeBlock /
/// table / thematicBreak become data entities; lists / blockquote / html fall
/// to `.raw` plaintext in v1 (styled block walkers come next).
public func markdownEntities(_ markdown: String, style: MarkdownProseStyle) -> [MarkdownEntity] {
  let blocks = [BlockNode](markdown: markdown)
  let styles = style.inlineStyles
  var entities: [MarkdownEntity] = []
  var prose = AttributedString()

  func flushProse() {
    if !prose.characters.isEmpty {
      entities.append(.prose(prose))
      prose = AttributedString()
    }
  }

  for block in blocks {
    switch block {
    case .paragraph(let inlines):
      appendInlines(inlines, to: &prose,
                    base: style.base(size: style.baseSize, weight: .regular), styles: styles)
      prose += AttributedString("\n\n")

    case .heading(let level, let inlines):
      appendInlines(inlines, to: &prose,
                    base: style.base(size: style.baseSize * headingScale(level), weight: .bold),
                    styles: styles)
      prose += AttributedString("\n\n")

    case .codeBlock(let fenceInfo, let content):
      flushProse()
      entities.append(.code(language: fenceInfo, text: content))

    case .thematicBreak:
      flushProse()
      entities.append(.thematicBreak)

    case .table(let columnAlignments, let rows):
      flushProse()
      let base = style.base(size: style.baseSize, weight: .regular)
      let cells = rows.map { row in
        row.cells.map { cell -> AttributedString in
          var a = AttributedString()
          appendInlines(cell.content, to: &a, base: base, styles: styles)
          return a
        }
      }
      entities.append(
        .table(
          MarkdownTableModel(
            alignments: columnAlignments.map(MarkdownTableModel.Alignment.init),
            rows: cells)))

    default:
      flushProse()
      entities.append(.raw(plainText: [block].renderPlainText()))
    }
  }
  flushProse()
  return entities
}

// MARK: - Internal helpers (in-module: uses MarkdownUI's internal types)

extension MarkdownProseStyle {
  fileprivate var inlineStyles: InlineTextStyles {
    InlineTextStyles(
      code: FontFamilyVariant(.monospaced),
      emphasis: FontStyle(.italic),
      strong: FontWeight(.semibold),
      strikethrough: StrikethroughStyle(.single),
      link: ForegroundColor(linkColor))
  }

  fileprivate func base(size: CGFloat, weight: Font.Weight) -> AttributeContainer {
    var fp = FontProperties()
    fp.family = .system()
    fp.size = size
    fp.weight = weight
    var c = AttributeContainer()
    c.fontProperties = fp
    c.foregroundColor = textColor
    return c
  }
}

private func appendInlines(
  _ inlines: [InlineNode], to out: inout AttributedString,
  base: AttributeContainer, styles: InlineTextStyles
) {
  for node in inlines {
    out += node.renderAttributedString(
      baseURL: nil, textStyles: styles, softBreakMode: .space, attributes: base)
  }
}

private func headingScale(_ level: Int) -> CGFloat {
  switch level {
  case 1: return 1.6
  case 2: return 1.4
  case 3: return 1.2
  default: return 1.05
  }
}

extension MarkdownTableModel.Alignment {
  fileprivate init(_ raw: RawTableColumnAlignment) {
    switch raw {
    case .left: self = .left
    case .center: self = .center
    case .right: self = .right
    case .none: self = .none
    }
  }
}
