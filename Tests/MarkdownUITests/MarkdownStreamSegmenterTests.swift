import XCTest

@testable import MarkdownUI

final class MarkdownStreamSegmenterTests: XCTestCase {
  private let doc = """
    # Heading One

    Some **bold** intro paragraph with `inline code` and a [link](https://example.com).

    Another paragraph in the same prose run.

    ## Section Two

    - first bullet
    - second bullet with *emphasis*

    ```swift
    let x = 1
    print(x)
    ```

    > a quoted line
    > a second quoted line

    | a | b |
    |---|---|
    | 1 | 2 |

    Final trailing paragraph.
    """

  /// The incremental segmenter, fed monotonically growing prefixes (as a stream
  /// appends), must produce EXACTLY what a full parse of that prefix produces —
  /// at every step, including incomplete states (a half-typed fence, an
  /// unterminated table row). If any growth step diverges, streaming would show
  /// content the settled render wouldn't.
  func testIncrementalMatchesFullAtEveryPrefix() async {
    let style = MarkdownProseStyle()
    let segmenter = MarkdownStreamSegmenter(style: style)
    var prefix = ""
    for ch in doc {
      prefix.append(ch)
      let incremental = await segmenter.segment(prefix)
      let full = markdownEntities(prefix, style: style)
      XCTAssertEqual(incremental, full, "diverged at prefix length \(prefix.count)")
    }
  }

  /// A non-append edit (rewrite from the front) must still converge — the
  /// common-prefix is short, so most of it re-segments, but the result is still
  /// a correct full parse.
  func testRewriteFromFrontStillMatches() async {
    let style = MarkdownProseStyle()
    let segmenter = MarkdownStreamSegmenter(style: style)
    _ = await segmenter.segment(doc)
    let rewritten = "# Totally different\n\nnew body paragraph\n\n```\ncode\n```"
    let incremental = await segmenter.segment(rewritten)
    XCTAssertEqual(incremental, markdownEntities(rewritten, style: style))
  }

  func testResetRestartsClean() async {
    let style = MarkdownProseStyle()
    let segmenter = MarkdownStreamSegmenter(style: style)
    _ = await segmenter.segment(doc)
    await segmenter.reset()
    let text = "# New\n\njust a paragraph"
    let afterReset = await segmenter.segment(text)
    XCTAssertEqual(afterReset, markdownEntities(text, style: style))
  }
}
