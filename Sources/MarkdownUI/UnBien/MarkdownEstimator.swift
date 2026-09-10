import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Fast-cut analytic height metrics for a markdown string — the ADDITIVE
/// estimation core (design: analytic height tier). This is NOT a parse: a
/// single fence/prefix-aware line scan classifies blocks and measures wrapped
/// text with real font metrics, skipping everything that makes the full
/// `markdownEntities` parse expensive (cmark structure, inline parsing,
/// AttributedString runs, entity boxing). Expected 10-50× cheaper than the
/// parse — cheap enough to run UNCAPPED for every row in a leading window.
///
/// OWNERSHIP SPLIT (deliberate): this function returns TEXT METRICS ONLY —
/// per-kind counts and wrapped text heights from the fonts `MarkdownProseStyle`
/// itself styles. It applies NO layout constants: block chrome, gaps, and row
/// padding live in the CALLER's render layer, where they are single-sourced
/// alongside the views that apply them (the app's `TranscriptMetrics`). The
/// estimator and the renderer cannot drift because neither owns a copy of the
/// other's constants.
///
/// Classification is intentionally approximate (prefix heuristics, not cmark):
/// the consumer composes chrome per KIND, so a mis-scanned rare construct
/// shifts one block's height by its chrome delta — bounded, never structural.
public struct MarkdownEstimateMetrics: Sendable, Equatable {
  /// Σ wrapped heights of prose/heading/list/quote TEXT (body-font metrics).
  public var textHeight: Double = 0
  /// Paragraph-level prose blocks measured above (excludes headings/lists).
  public var proseBlocks = 0
  /// Total lines inside fences (caller composes × mono line height + chrome).
  public var codeLines = 0
  /// Distinct fenced blocks.
  public var codeBlocks = 0
  /// `|`-prefixed table rows.
  public var tableRows = 0
  /// `#`-prefixed headings, by level bucket (1...3+).
  public var headings = 0
  /// List-item lines (bulleted or ordered; nesting adds one per line).
  public var listItems = 0
  /// `>`-prefixed quote lines.
  public var quoteLines = 0

  public init() {}
}

/// Scan `markdown` and measure its text metrics at `width` with the fonts
/// derived from `style`. Width <= 0 returns zeroed metrics (caller opts out).
public func markdownEstimateMetrics(
  _ markdown: String, style: MarkdownProseStyle, width: Double
) -> MarkdownEstimateMetrics {
  var m = MarkdownEstimateMetrics()
  guard width > 0, !markdown.isEmpty else { return m }

  let bodyFont = EstimateSupport.font(size: style.baseSize, name: style.fontName)
  // WRAP-AWARE code accounting (2026-09-10): the renderer WRAPS long code
  // lines (no horizontal scroll), so raw line counts undercount. Monospace
  // makes the wrap factor exact: renderedLines = ceil(chars / charsPerLine),
  // charsPerLine from the mono advance of "0" at the effective code size.
  let codeSize = style.codeSize ?? style.baseSize
  let monoFont = EstimateSupport.font(size: codeSize, name: style.codeFontName)
  let zero = ("0" as NSString).size(withAttributes: [.font: monoFont]).width
  let codeContentWidth = max(1, width - 24)   // minus the code block's padding
  let charsPerLine = max(1, Int(codeContentWidth / max(zero, 0.5)))
  func wrappedCodeLines(_ line: String) -> Int {
    max(1, Int(ceil(Double(line.count) / Double(charsPerLine))))
  }
  var prose = ""
  var inFence = false

  func flushProse() {
    let trimmed = prose.trimmingCharacters(in: .newlines)
    guard !trimmed.isEmpty else { return }
    m.textHeight += EstimateSupport.wrappedHeight(trimmed, font: bodyFont, width: width)
    m.proseBlocks += 1
    prose = ""
  }

  for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("```") || line.hasPrefix("~~~") {
      flushProse()
      if inFence { m.codeBlocks += 1 }
      inFence.toggle()
      continue
    }
    if inFence {
      m.codeLines += wrappedCodeLines(String(rawLine))
      continue
    }
    if line.isEmpty {
      flushProse()
      continue
    }
    if line.hasPrefix("|") {
      flushProse()
      m.tableRows += 1
      continue
    }
    if let headingLevel = EstimateSupport.headingLevel(line) {
      flushProse()
      let text = String(line.drop(while: { $0 == "#" || $0 == " " }))
      let size = style.baseSize * EstimateSupport.headingScale(headingLevel)
      let font = EstimateSupport.font(size: size, name: style.fontName)
      m.textHeight += EstimateSupport.wrappedHeight(text, font: font, width: width)
      m.headings += 1
      continue
    }
    if EstimateSupport.isListItem(line) {
      flushProse()
      m.listItems += 1
      // Item text measured at an indented width (marker column).
      m.textHeight += EstimateSupport.wrappedHeight(
        EstimateSupport.listItemText(line), font: bodyFont, width: max(0, width - 24))
      continue
    }
    if line.hasPrefix(">") {
      m.quoteLines += 1
      m.textHeight += EstimateSupport.wrappedHeight(
        String(line.dropFirst()).trimmingCharacters(in: .whitespaces),
        font: bodyFont, width: max(0, width - 20))
      continue
    }
    prose += rawLine + "\n"
  }
  flushProse()
  if inFence { m.codeBlocks += 1 }   // unterminated fence: still one block
  return m
}

private enum EstimateSupport {
  static func font(size: Double, name: String?) -> PlatformFont {
    if let name, let named = PlatformFont(name: name, size: size) { return named }
    return PlatformFont.systemFont(ofSize: size)
  }

  /// Wrapped height via boundingRect — single-font layout, no attribute runs
  /// (the cheap variant; the styled render happens later, at materialization).
  static func wrappedHeight(_ s: String, font: PlatformFont, width: Double) -> Double {
    guard !s.isEmpty, width > 0 else { return 0 }
    let attr = NSAttributedString(string: s, attributes: [.font: font])
    let rect = attr.boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    return rect.height.rounded()
  }

  static func headingLevel(_ line: String) -> Int? {
    var level = 0
    for ch in line {
      if ch == "#" { level += 1 } else { break }
    }
    guard level >= 1, level <= 6 else { return nil }
    let after = line.dropFirst(level)
    guard after.first == " " || after.first == "\t" || after.isEmpty else { return nil }
    return level
  }

  /// ATX heading scale approximation (level 1 largest, flattening by 3).
  static func headingScale(_ level: Int) -> Double {
    switch level {
    case 1: return 1.6
    case 2: return 1.4
    case 3: return 1.2
    default: return 1.1
    }
  }

  static func isListItem(_ line: String) -> Bool {
    if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
    // Ordered: digits/parens then a period + space.
    var idx = line.startIndex
    while idx < line.endIndex, line[idx].isNumber { idx = line.index(after: idx) }
    return idx > line.startIndex && idx < line.endIndex
      && (line[idx] == "." || line[idx] == ")")
      && line.index(after: idx) < line.endIndex
      && line[line.index(after: idx)] == " "
  }

  static func listItemText(_ line: String) -> String {
    if let space = line.firstIndex(where: { $0 == " " }) {
      return String(line[line.index(after: space)...])
    }
    return line
  }
}

#if canImport(AppKit)
typealias PlatformFont = NSFont
#elseif canImport(UIKit)
typealias PlatformFont = UIFont
#endif
