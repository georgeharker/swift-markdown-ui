import Foundation

/// A delineated, storable unit of a parsed Markdown document.
///
/// Produced off-main by ``markdownEntities(_:style:)``. Flowable prose is
/// already materialized to an `AttributedString`; structural entities carry
/// DATA (not views), so the caller plugs its own materialization — a syntax
/// highlighter for `.code`, a grid for `.table`, an image loader for images.
///
/// The list is a value type (`Hashable`, `Sendable`), so it can be cached or
/// persisted per message and re-materialized without re-parsing.
public enum MarkdownEntity: Hashable, Sendable {
  /// A coalesced run of flowable blocks (paragraphs, headings, …), styled.
  case prose(AttributedString)
  /// A fenced code block — deferred to the caller's highlighter.
  case code(language: String?, text: String)
  /// A table's structured data (pre-styled cells + alignments).
  case table(MarkdownTableModel)
  /// A horizontal rule.
  case thematicBreak
  /// A block not yet flattened to prose (lists / blockquote / html in v1, or a
  /// nested-structural island): its plain text, for a caller fallback.
  case raw(plainText: String)
}

/// Structured table data: pre-styled cells + per-column alignment. The grid
/// layout is the caller's to render (only the 2D layout must stay on the main
/// actor; the cell styling was done off-main).
public struct MarkdownTableModel: Hashable, Sendable {
  public enum Alignment: Hashable, Sendable {
    case none, left, center, right
  }
  public var alignments: [Alignment]
  /// `rows[row][column]` — the header is `rows.first`.
  public var rows: [[AttributedString]]

  public init(alignments: [Alignment], rows: [[AttributedString]]) {
    self.alignments = alignments
    self.rows = rows
  }
}
