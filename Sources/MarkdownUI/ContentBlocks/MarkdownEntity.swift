import Foundation

/// A delineated, storable unit of a parsed Markdown document.
///
/// Produced off-main by ``markdownEntities(_:style:)``. Flowable prose is
/// already materialized to an `AttributedString`; structural entities carry
/// DATA (not views), so the caller plugs its own materialization — a syntax
/// highlighter for `.code`, a grid for `.table`, marker columns for `.list`, a
/// bar for `.blockquote`, an image loader for images.
///
/// The list is a value type (`Hashable`, `Sendable`), so it can be cached or
/// persisted per message and re-materialized without re-parsing.
public indirect enum MarkdownEntity: Hashable, Sendable {
  /// A coalesced run of flowable blocks (paragraphs, html), styled.
  case prose(AttributedString)
  /// A heading — its own entity so the caller can apply per-level margins.
  case heading(level: Int, text: AttributedString)
  /// A fenced code block — deferred to the caller's highlighter.
  case code(language: String?, text: String)
  /// A table's structured data (pre-styled cells + alignments).
  case table(MarkdownTableModel)
  /// A list — marker column + per-item content (items recurse).
  case list(MarkdownListModel)
  /// A blockquote — recursive children, rendered behind a bar by the caller.
  case blockquote([MarkdownEntity])
  /// A `<details>`/`<summary>` disclosure — a summary header + recursive body.
  /// Rendered as a FIXED-HEIGHT callout (never collapsible): a windowed
  /// transcript freezes row heights offscreen, so a togglable height breaks it.
  case details(summary: AttributedString, children: [MarkdownEntity])
  /// A horizontal rule.
  case thematicBreak
  /// A node the walker couldn't flatten (reserved fallback; unused in practice).
  case raw(plainText: String)
}

/// Structured table data: pre-styled cells + per-column alignment. The grid
/// layout is the caller's to render; the cell styling was done off-main.
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

/// Structured list data: a kind + items. Each item carries a marker string
/// (bullet / number / checkbox) and its own recursively-walked content (usually
/// one `.prose`, but may nest a `.list` or hold a `.code`). The caller lays out
/// the marker column; the item text was styled off-main.
public struct MarkdownListModel: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case bulleted
    case numbered(start: Int)
    case task
  }

  public struct Item: Hashable, Sendable {
    public var marker: String
    public var checked: Bool?           // task items only
    public var content: [MarkdownEntity]

    public init(marker: String, checked: Bool?, content: [MarkdownEntity]) {
      self.marker = marker
      self.checked = checked
      self.content = content
    }
  }

  public var kind: Kind
  /// A tight list (no blank lines between items) renders compactly; a loose
  /// list gets paragraph-sized gaps — mirrors CommonMark / MarkdownUI.
  public var isTight: Bool
  public var items: [Item]

  public init(kind: Kind, isTight: Bool, items: [Item]) {
    self.kind = kind
    self.isTight = isTight
    self.items = items
  }
}
