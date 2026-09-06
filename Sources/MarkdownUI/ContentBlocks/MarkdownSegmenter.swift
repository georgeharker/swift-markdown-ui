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

  var i = 0
  while i < blocks.count {
    let block = blocks[i]

    // <details>/<summary> -> a fixed-height callout entity. cmark splits the
    // construct across htmlBlock(<details>..<summary>..) / markdown body /
    // htmlBlock(</details>) at blank lines; collect the body between them.
    if case .htmlBlock(let content) = block,
       content.range(of: "<details", options: [.caseInsensitive]) != nil {
      flush()
      var summaryText = extractSummary(content)
      var body: [BlockNode] = []
      if content.range(of: "</details", options: [.caseInsensitive]) != nil {
        let inline = detailsInlineBody(content)
        if !inline.isEmpty { body = [BlockNode](markdown: inline) }
        i += 1
      } else {
        i += 1
        while i < blocks.count {
          if case .htmlBlock(let c) = blocks[i],
             c.range(of: "</details", options: [.caseInsensitive]) != nil {
            i += 1
            break
          }
          if case .htmlBlock(let c) = blocks[i],
             c.range(of: "<summary", options: [.caseInsensitive]) != nil {
            if summaryText.isEmpty { summaryText = extractSummary(c) }
            i += 1
            continue
          }
          body.append(blocks[i])
          i += 1
        }
      }
      var summary = AttributedString(summaryText.isEmpty ? "Details" : summaryText)
      summary.mergeAttributes(style.base(size: style.baseSize, weight: .semibold))
      out.append(.details(summary: summary, children: entities(for: body, style: style)))
      continue
    }

    switch block {
    case .paragraph(let inlines):
      proseSeparator(&prose)
      appendInlines(inlines, to: &prose,
                    base: style.base(size: style.baseSize, weight: .regular), styles: styles)

    case .heading(let level, let inlines):
      flush()
      var heading = AttributedString()
      appendInlines(inlines, to: &heading,
                    base: style.base(size: style.baseSize * headingScale(level), weight: .bold),
                    styles: styles)
      out.append(.heading(level: level, text: heading))

    case .htmlBlock(let content):
      // MarkdownUI treats an html block as a paragraph; unknown tags show as
      // text. Keep it in the prose run.
      proseSeparator(&prose)
      var seg = AttributedString(content.trimmingCharacters(in: .newlines))
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

    case .bulletedList(let isTight, let items):
      flush()
      out.append(.list(listModel(.bulleted, isTight: isTight, items: items, style: style)))

    case .numberedList(let isTight, let start, let items):
      flush()
      out.append(.list(listModel(.numbered(start: start), isTight: isTight,
                                 items: items, style: style, start: start)))

    case .taskList(let isTight, let items):
      flush()
      out.append(.list(taskListModel(isTight: isTight, items: items, style: style)))

    case .blockquote(let children):
      flush()
      var quoted = style
      if let quoteColor = style.quoteColor { quoted.textColor = quoteColor }
      out.append(.blockquote(entities(for: children, style: quoted)))
    }
    i += 1
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
  _ kind: MarkdownListModel.Kind, isTight: Bool, items: [RawListItem],
  style: MarkdownProseStyle, start: Int = 1
) -> MarkdownListModel {
  let modelItems = items.enumerated().map { index, item -> MarkdownListModel.Item in
    let marker: String
    if case .numbered = kind { marker = "\(start + index)." } else { marker = "\u{2022}" }
    return MarkdownListModel.Item(marker: marker, checked: nil,
                                  content: entities(for: item.children, style: style))
  }
  return MarkdownListModel(kind: kind, isTight: isTight, items: modelItems)
}

private func taskListModel(
  isTight: Bool, items: [RawTaskListItem], style: MarkdownProseStyle
) -> MarkdownListModel {
  let modelItems = items.map { item in
    MarkdownListModel.Item(
      marker: item.isCompleted ? "\u{2611}" : "\u{2610}",
      checked: item.isCompleted,
      content: entities(for: item.children, style: style))
  }
  return MarkdownListModel(kind: .task, isTight: isTight, items: modelItems)
}

// MARK: - Inline helpers (in-module: uses MarkdownUI's internal types)

extension MarkdownProseStyle {
  fileprivate var inlineStyles: InlineTextStyles {
    InlineTextStyles(
      code: Self.codeStyle(fontName: codeFontName, color: codeColor, background: codeBackground),
      emphasis: FontStyle(.italic),
      strong: FontWeight(.semibold),
      strikethrough: StrikethroughStyle(.single),
      link: ForegroundColor(linkColor))
  }

  // Explicit mono FAMILY (not FontFamilyVariant.monospaced) — a custom body
  // font has no monospaced variant, so inline `code` would fall back to body.
  @TextStyleBuilder
  fileprivate static func codeStyle(fontName: String?, color: Color?, background: Color?) -> some TextStyle {
    FontFamily(fontName.map { .custom($0) } ?? .system(.monospaced))
    ForegroundColor(color)
    BackgroundColor(background)
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

/// A blank line BETWEEN flowable blocks (never trailing) so a prose run
/// doesn't accumulate empty space before the next entity.
private func proseSeparator(_ prose: inout AttributedString) {
  if !prose.characters.isEmpty { prose += AttributedString("\n\n") }
}

private func appendInlines(
  _ inlines: [InlineNode], to out: inout AttributedString,
  base: AttributeContainer, styles: InlineTextStyles
) {
  var current = base
  for node in inlines {
    if case .html(let raw) = node, let name = HTMLTag(raw)?.name.lowercased() {
      switch (name, raw.contains("</")) {
      case ("sub", false): current = subSuperscript(base, direction: -1); continue
      case ("sup", false): current = subSuperscript(base, direction: 1); continue
      case ("sub", true), ("sup", true): current = base; continue
      default: break
      }
    }
    out += node.renderAttributedString(
      baseURL: nil, textStyles: styles, softBreakMode: .space, attributes: current)
  }
}

// <sub>/<sup>: a smaller run nudged off the baseline (fontProperties.size is
// resolved to a concrete font by renderAttributedString; baselineOffset passes
// through). `<br>` stays handled by MarkdownUI; other tags render as literal text.
private func subSuperscript(_ base: AttributeContainer, direction: CGFloat) -> AttributeContainer {
  var c = base
  let size = c.fontProperties?.size ?? 16
  if var props = c.fontProperties {
    props.size = size * 0.75
    c.fontProperties = props
  }
  c.baselineOffset = direction * size * 0.3
  return c
}

// The <summary>…</summary> text inside a <details> html block.
private func extractSummary(_ html: String) -> String {
  guard let open = html.range(of: "<summary", options: [.caseInsensitive]),
        let gt = html.range(of: ">", range: open.upperBound..<html.endIndex)
  else { return "" }
  guard let close = html.range(of: "</summary", options: [.caseInsensitive],
                               range: gt.upperBound..<html.endIndex)
  else { return String(html[gt.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
  return String(html[gt.upperBound..<close.lowerBound])
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

// Body text between </summary> and </details> for a single-line <details>.
private func detailsInlineBody(_ html: String) -> String {
  var start = html.startIndex
  if let sum = html.range(of: "</summary>", options: [.caseInsensitive]) {
    start = sum.upperBound
  } else if let gt = html.range(of: ">") {
    start = gt.upperBound
  }
  var end = html.endIndex
  if let det = html.range(of: "</details", options: [.caseInsensitive],
                          range: start..<html.endIndex) {
    end = det.lowerBound
  }
  return String(html[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
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
