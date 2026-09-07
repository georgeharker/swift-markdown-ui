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
  segmentWithEnds([BlockNode](markdown: markdown), style: style).0
}

/// Off-main INCREMENTAL segmenter for streaming markdown. Holds the prior parse
/// + entities; each submit re-parses (cheap cmark), finds the unchanged
/// top-level block prefix vs the prior parse, keeps the entities that cover it,
/// and re-segments ONLY the changed tail. Because a stream APPENDS, the tail is
/// small. An `actor` so its `[BlockNode]` state stays confined off-main (actor
/// isolation, not Sendable) — only the `[MarkdownEntity]` result (Sendable)
/// crosses out. Cutting strictly BEFORE the first changed block (`end < p`)
/// keeps a coalescing prose run from being split when the boundary block moves.
public actor MarkdownStreamSegmenter {
  private let style: MarkdownProseStyle
  private var priorBlocks: [BlockNode] = []
  private var priorEntities: [MarkdownEntity] = []
  private var priorEnds: [Int] = []

  public init(style: MarkdownProseStyle) { self.style = style }

  public func reset() {
    priorBlocks = []
    priorEntities = []
    priorEnds = []
  }

  public func segment(_ markdown: String) -> [MarkdownEntity] {
    let blocks = [BlockNode](markdown: markdown)
    var p = 0
    let common = min(blocks.count, priorBlocks.count)
    while p < common && blocks[p] == priorBlocks[p] { p += 1 }

    // Keep entities whose end is STRICTLY before the first changed block, so the
    // re-walk starts on a clean (prose-empty) boundary and any run touching the
    // change is rebuilt whole.
    var keptCount = 0
    var k = 0
    while keptCount < priorEnds.count && priorEnds[keptCount] < p {
      k = priorEnds[keptCount]
      keptCount += 1
    }

    let (tail, tailEnds) = segmentWithEnds(Array(blocks[k...]), style: style)
    let entities = Array(priorEntities[0..<keptCount]) + tail
    priorBlocks = blocks
    priorEntities = entities
    priorEnds = Array(priorEnds[0..<keptCount]) + tailEnds.map { $0 + k }
    return entities
  }
}

// MARK: - Recursive walk

private func entities(for blocks: [BlockNode], style: MarkdownProseStyle) -> [MarkdownEntity] {
  segmentWithEnds(blocks, style: style).0
}

/// The top-level walk, recording each emitted entity's EXCLUSIVE end block
/// index. Ends are monotonic; entity j spans blocks[ends[j-1]..<ends[j]] with
/// ends[-1] = 0. Nested children (list items, blockquotes) recurse via
/// `entities(for:)` and don't need spans — only the top level is diffed.
private func segmentWithEnds(
  _ blocks: [BlockNode], style: MarkdownProseStyle
) -> ([MarkdownEntity], [Int]) {
  let styles = style.inlineStyles
  var out: [MarkdownEntity] = []
  var ends: [Int] = []
  var prose = AttributedString()

  func emit(_ entity: MarkdownEntity, end: Int) {
    out.append(entity)
    ends.append(end)
  }
  // A prose run ends at the block that triggered the flush (exclusive).
  func flush(end: Int) {
    if !prose.characters.isEmpty {
      out.append(.prose(prose))
      ends.append(end)
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
      flush(end: i)
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
      emit(.details(summary: summary, children: entities(for: body, style: style)), end: i)
      continue
    }

    switch block {
    case .paragraph(let inlines):
      proseSeparator(&prose)
      appendInlines(inlines, to: &prose,
                    base: style.base(size: style.baseSize, weight: .regular), styles: styles)

    case .heading(let level, let inlines):
      flush(end: i)
      var heading = AttributedString()
      appendInlines(inlines, to: &heading,
                    base: style.base(size: style.baseSize * headingScale(level), weight: .bold),
                    styles: styles)
      emit(.heading(level: level, text: heading), end: i + 1)

    case .htmlBlock(let content):
      // MarkdownUI treats an html block as a paragraph; unknown tags show as
      // text. Keep it in the prose run.
      proseSeparator(&prose)
      var seg = AttributedString(content.trimmingCharacters(in: .newlines))
      seg.mergeAttributes(style.base(size: style.baseSize, weight: .regular))
      prose += seg

    case .codeBlock(let fenceInfo, let content):
      flush(end: i)
      emit(.code(language: fenceInfo, text: content), end: i + 1)

    case .thematicBreak:
      flush(end: i)
      emit(.thematicBreak, end: i + 1)

    case .table(let columnAlignments, let rows):
      flush(end: i)
      emit(.table(tableModel(columnAlignments, rows, style: style, styles: styles)), end: i + 1)

    case .bulletedList(let isTight, let items):
      flush(end: i)
      emit(.list(listModel(.bulleted, isTight: isTight, items: items, style: style)), end: i + 1)

    case .numberedList(let isTight, let start, let items):
      flush(end: i)
      emit(.list(listModel(.numbered(start: start), isTight: isTight,
                           items: items, style: style, start: start)), end: i + 1)

    case .taskList(let isTight, let items):
      flush(end: i)
      emit(.list(taskListModel(isTight: isTight, items: items, style: style)), end: i + 1)

    case .blockquote(let children):
      flush(end: i)
      var quoted = style
      if let quoteColor = style.quoteColor { quoted.textColor = quoteColor }
      emit(.blockquote(entities(for: children, style: quoted)), end: i + 1)
    }
    i += 1
  }
  flush(end: blocks.count)
  return (out, ends)
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
