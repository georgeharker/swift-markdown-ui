import SwiftUI

/// Plain, caller-supplied styling for the off-main prose renderer.
///
/// The caller resolves these from its OWN theme on the main actor and passes
/// the values in; the segmenter builds MarkdownUI's internal `InlineTextStyles`
/// from them, so no MarkdownUI-internal type leaks into the public API.
public struct MarkdownProseStyle: Sendable {
  public var baseSize: CGFloat
  public var textColor: Color
  public var linkColor: Color
  /// Inline `code` foreground / background chip. `nil` = inherit / none.
  public var codeColor: Color?
  public var codeBackground: Color?
  /// Custom body font family (PostScript/registered name). `nil` = system.
  public var fontName: String?

  public init(
    baseSize: CGFloat = 16,
    textColor: Color = .primary,
    linkColor: Color = .accentColor,
    codeColor: Color? = nil,
    codeBackground: Color? = nil,
    fontName: String? = nil
  ) {
    self.baseSize = baseSize
    self.textColor = textColor
    self.linkColor = linkColor
    self.codeColor = codeColor
    self.codeBackground = codeBackground
    self.fontName = fontName
  }
}
