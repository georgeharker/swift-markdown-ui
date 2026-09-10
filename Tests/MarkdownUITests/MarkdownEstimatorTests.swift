import XCTest
@testable import MarkdownUI

/// Fast-cut estimator correctness (analytic height tier): the fence/prefix
/// scan must AGREE with the block structure on well-formed markdown — counts
/// per kind are the contract the caller's chrome composition relies on.
final class MarkdownEstimatorTests: XCTestCase {
  private let style = MarkdownProseStyle(baseSize: 15)

  func testEmptyAndOptOut() {
    let zero = markdownEstimateMetrics("", style: style, width: 400)
    XCTAssertEqual(zero, MarkdownEstimateMetrics())
    let optedOut = markdownEstimateMetrics("hello **world**", style: style, width: 0)
    XCTAssertEqual(optedOut, MarkdownEstimateMetrics())
  }

  func testProseBlocksAndParagraphSplitting() {
    let md = """
    First paragraph line one
    continued on the next line.

    Second paragraph.
    """
    let m = markdownEstimateMetrics(md, style: style, width: 400)
    XCTAssertEqual(m.proseBlocks, 2, "blank line splits paragraphs")
    XCTAssertGreaterThan(m.textHeight, 0)
  }

  func testFencesCountAsCodeNotProse() {
    let md = """
    before

    ```swift
    let a = 1
    let b = 2
    ```

    after
    """
    let m = markdownEstimateMetrics(md, style: style, width: 400)
    XCTAssertEqual(m.codeBlocks, 1)
    XCTAssertEqual(m.codeLines, 2, "fence content lines only (markers excluded)")
    XCTAssertEqual(m.proseBlocks, 2, "'before' and 'after'")
  }

  func testUnterminatedFenceStillCountsBlock() {
    let m = markdownEstimateMetrics("```\ncode line", style: style, width: 400)
    XCTAssertEqual(m.codeBlocks, 1)
    XCTAssertEqual(m.codeLines, 1)
  }

  func testTildeFences() {
    let m = markdownEstimateMetrics("~~~\nx\n~~~\n", style: style, width: 400)
    XCTAssertEqual(m.codeBlocks, 1)
    XCTAssertEqual(m.codeLines, 1)
  }

  func testTablesHeadingsListsQuotes() {
    let md = """
    # Title

    | a | b |
    |---|---|
    | 1 | 2 |

    - one
    - two
    * three

    1. ordered

    > quoted line

    Tail paragraph.
    """
    let m = markdownEstimateMetrics(md, style: style, width: 400)
    XCTAssertEqual(m.headings, 1)
    XCTAssertEqual(m.tableRows, 3, "header + separator + data row")
    XCTAssertEqual(m.listItems, 4, "3 bullets + 1 ordered")
    XCTAssertEqual(m.quoteLines, 1)
    XCTAssertEqual(m.proseBlocks, 1, "only the tail paragraph")
  }

  func testHeadingScaleApplies() {
    let m = markdownEstimateMetrics("# Big", style: style, width: 400)
    XCTAssertEqual(m.headings, 1)
    // A level-1 heading measures taller than one body line.
    XCTAssertGreaterThan(m.textHeight, style.baseSize * 1.5)
  }

  func testWidthSensitivity() {
    let md = String(repeating: "word ", count: 200)
    let wide = markdownEstimateMetrics(md, style: style, width: 800)
    let narrow = markdownEstimateMetrics(md, style: style, width: 200)
    XCTAssertEqual(wide.proseBlocks, narrow.proseBlocks)
    XCTAssertGreaterThan(narrow.textHeight, wide.textHeight * 2,
                         "narrower wrap must be substantially taller")
  }

  func testHashNotFollowedBySpaceIsProse() {
    let m = markdownEstimateMetrics("#hashtag not heading", style: style, width: 400)
    XCTAssertEqual(m.headings, 0)
    XCTAssertEqual(m.proseBlocks, 1)
  }
}
