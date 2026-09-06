import SwiftUI

/// Parse `markdown` and delineate it into storable ``MarkdownEntity`` values.
///
/// PURE + off-main safe: parsing is cmark, prose styling uses value-type
/// `TextStyle` DSL, and no SwiftUI `Environment` is touched. Flowable blocks
/// (paragraph, heading, html) coalesce into `.prose(AttributedString)`;
/// codeBlock / table / thematicBreak become data entities; lists + blockquotes
/// become structural entities whose text is still styled off-main (the walker
/// recurses through their children).
public func markdownEntities(_ markdown: String, style: MarkdownProseStyle) -> [MarkdownEntity] {
  entities(for: [BlockNode](markdown: markdown), style: style)
}

// MARK: - Recursive walk

private func entities(for blocks: [BlockNode], style: MarkdownProseStyle) -> [MarkdownEntity] {
  let styles = style.inlineStyles
  var out: [MarkdownEntity] = []
  var prose = AttributedString()

  func flush() {
    if !prose.characters.isEmpty {
      out.append(.prose(prose))
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

    case .htmlBlock(let content):
      // MarkdownUI treats an html block as a paragraph; unknown tags show as
      // text. Keep it in the prose run.
      var seg = AttributedString(content.trimmingCharacters(in: .newlines) + "\n\n")
      seg.mergeAttributes(style.base(size: style.baseSize, weight: .regular))
      prose += seg

    case .codeBlock(let fenceInfo, let content):
      flush()
      out.append(.code(language: fenceInfo, text: content))

    case .thematicBreak:
      flush()
      out.append(.thematicBreak)

    case .table(let columnAlignments, let rows):
      flush()
      out.append(.table(tableModel(columnAlignments, rows, style: style, styles: styles)))

    case .bulletedList(_, let items):
      flush()
      out.append(.list(listModel(.bulleted, items: items, style: style)))

    case .numberedList(_, let start, let items):
      flush()
      out.append(.list(listModel(.numbered(start: start), items: items, style: style, start: start)))

    case .taskList(_, let items):
      flush()
      out.append(.list(taskListModel(items, style: style)))

    case .blockquote(let children):
      flush()
      out.append(.blockquote(entities(for: children, style: style)))
    }
  }
  flush()
  return out
}

// MARK: - Structural models

private func tableModel(
  _ alignments: [RawTableColumnAlignment], _ rows: [RawTableRow],
  style: MarkdownProseStyle, styles: InlineTextStyles
) -> MarkdownTableModel {
  let base = style.base(size: style.baseSize, weight: .regular)
  let cells = rows.map { row in
    row.cells.map { cell -> AttributedString in
      var attributed = AttributedString()
      appendInlines(cell.content, to: &attributed, base: base, styles: styles)
      return attributed
    }
  }
  return MarkdownTableModel(alignments: alignments.map(MarkdownTableModel.Alignment.init), rows: cells)
}

private func listModel(
  _ kind: MarkdownListModel.Kind, items: [RawListItem],
  style: MarkdownProseStyle, start: Int = 1
) -> MarkdownListModel {
  let modelItems = items.enumerated().map { index, item -> MarkdownListModel.Item in
    let marker: String
    if case .numbered = kind { marker = "\(start + index)." } else { marker = "\u{2022}" }
    return MarkdownListModel.Item(marker: marker, checked: nil,
                                  content: entities(for: item.children, style: style))
  }
  return MarkdownListModel(kind: kind, items: modelItems)
}

private func taskListModel(_ items: [RawTaskListItem], style: MarkdownProseStyle) -> MarkdownListModel {
  let modelItems = items.map { item in
    MarkdownListModel.Item(
      marker: item.isCompleted ? "\u{2611}" : "\u{2610}",
      checked: item.isCompleted,
      content: entities(for: item.children, style: style))
  }
  return MarkdownListModel(kind: .task, items: modelItems)
}

// MARK: - Inline helpers (in-module: uses MarkdownUI's internal types)

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
    var properties = FontProperties()
    properties.family = fontName.map { .custom($0) } ?? .system()
    properties.size = size
    properties.weight = weight
    var container = AttributeContainer()
    container.fontProperties = properties
    container.foregroundColor = textColor
    return container
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
