# MarkdownUI
[![CI](https://github.com/gonzalezreal/MarkdownUI/workflows/CI/badge.svg)](https://github.com/gonzalezreal/MarkdownUI/actions?query=workflow%3ACI)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgonzalezreal%2Fswift-markdown-ui%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgonzalezreal%2Fswift-markdown-ui%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui)

---

> ## Fork: `un-bien-fork` (purely additive)
>
> This is a fork of [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) for the **un-bien** app. It is **add-only**: no upstream source file is modified, added-to, or deleted, so **every original MarkdownUI API and behaviour is maintained unchanged**. The entire diff vs the upstream `2.4.1` tag is one new directory (`git diff 2.4.1..un-bien-fork` = 3 files added, 0 changed).
>
> ### What's extra: `Sources/MarkdownUI/ContentBlocks/`
>
> A first-class **parse → storable entities** API for rendering Markdown **off the main thread**:
>
> - **`markdownEntities(_:style:) -> [MarkdownEntity]`** — parses a document (pure cmark, off-main-safe) and delineates it into a flat list of storable entities, materialising flowable prose to a themed `AttributedString` up front.
> - **`MarkdownEntity`** — `.prose(AttributedString)` (already styled), `.heading(level:text:)`, `.code(language:text:)`, `.table(MarkdownTableModel)`, `.list(MarkdownListModel)`, `.blockquote([MarkdownEntity])`, `.thematicBreak`. Structural entities carry **data, not views**, so the caller plugs its own materialisation (a syntax highlighter, a grid, marker columns, a bar).
> - **`MarkdownProseStyle`** — plain caller-supplied styling (base size + text/link colour); the segmenter builds MarkdownUI's internal `InlineTextStyles` from it, so **no MarkdownUI-internal type leaks into the public API**.
>
> ### Why
>
> It lets an app produce the expensive parse + inline styling on a background queue and render settled Markdown as one cached `Text` per prose run — keeping fast scroll jank-free (measured: 0 dropped frames vs the live view's 72% under a fast fling). The segmenter lives **inside** the module, so it reuses MarkdownUI's own cmark parser, inline `AttributedString` renderer, and `TextStyle` DSL directly — which is why the change stays add-only.
>
> ### Coverage
>
> Every CommonMark/GFM block maps to an entity: paragraphs (and html blocks) coalesce into `.prose`; `.heading`, `.code`, `.table`, `.list` (bulleted / numbered / task, honouring tight vs loose), `.blockquote` (recursive), and `.thematicBreak` are their own entities. The walker recurses through list items and blockquote children.
>
> ### Known holes
>
> - **Images** — inline `![alt](url)` renders as **alt text only** (`AttributedString` can't hold an image, so there is no image entity). In practice that's usually right: LLM-emitted inline image URLs are typically placeholder/hallucinated, and *real* images arrive as **separate content blocks bound positionally**, not referenced from the markdown — splice those in alongside the entity list yourself.
> - **Raw HTML** — LLMs emit raw HTML **unfenced** (`<br>` in table cells, `<details>`, `<sub>`/`<sup>`), so a consumer needs a policy. Here: inline `<br>` is handled by the inline renderer; block / unknown HTML falls through as **plain text**, not parsed or rendered.
> - **Streaming** — the entity path is for *settled* documents; while a message streams, render live and settle-swap to entities.
>
> ### Syncing upstream
>
> Rebase `un-bien-fork` on a newer upstream tag; only the three `ContentBlocks/` files re-apply.

---

Display and customize Markdown text in SwiftUI.

* [Overview](#overview)
* [Minimum requirements](#minimum-requirements)
* [Getting started](#getting-started)
  * [Creating a Markdown view](#creating-a-markdown-view)
  * [Styling Markdown](#styling-markdown)
* [Documentation](#documentation)
  * [Related content](#related-content)
* [Demo](#demo)
* [Installation](#installation)

## Overview

MarkdownUI is a powerful library for displaying and customizing Markdown text in SwiftUI. It is
compatible with the [GitHub Flavored Markdown Spec](https://github.github.com/gfm/) and can
display images, headings, lists (including task lists), blockquotes, code blocks, tables,
and thematic breaks, besides styled text and links.

MarkdownUI offers comprehensible theming features to customize how it displays Markdown text.
You can use the built-in themes, create your own or override specific text and block styles.

![](Sources/MarkdownUI/Documentation.docc/Resources/MarkdownUI@2x.png#gh-light-mode-only)
![](Sources/MarkdownUI/Documentation.docc/Resources/MarkdownUI~dark@2x.png#gh-dark-mode-only)

## Minimum requirements

You can use MarkdownUI on the following platforms:

- macOS 12.0+
- iOS 15.0+
- tvOS 15.0+
- watchOS 8.0+

Some features, like displaying tables or multi-image paragraphs, require macOS 13.0+, iOS 16.0+,
tvOS 16.0+, and watchOS 9.0+.

## Getting started

### Creating a Markdown view

A `Markdown` view displays rich structured text using the Markdown syntax. It can display images,
headings, lists (including task lists), blockquotes, code blocks, tables, and thematic breaks,
besides styled text and links.

The simplest way of creating a `Markdown` view is to pass a Markdown string to the
`init(_:baseURL:imageBaseURL:)` initializer.

```swift
let markdownString = """
  ## Try MarkdownUI

  **MarkdownUI** is a native Markdown renderer for SwiftUI
  compatible with the
  [GitHub Flavored Markdown Spec](https://github.github.com/gfm/).
  """

var body: some View {
  Markdown(markdownString)
}
```

![](Sources/MarkdownUI/Documentation.docc/Resources/MarkdownString@2x.png#gh-light-mode-only)
![](Sources/MarkdownUI/Documentation.docc/Resources/MarkdownString~dark@2x.png#gh-dark-mode-only)

A more convenient way to create a `Markdown` view is by using the
`init(baseURL:imageBaseURL:content:)` initializer, which takes a Markdown content
builder in which you can compose the view content, either by providing Markdown strings or by
using an expressive domain-specific language.

```swift
var body: some View {
  Markdown {
    """
    ## Using a Markdown Content Builder
    Use Markdown strings or an expressive domain-specific language
    to build the content.
    """
    Heading(.level2) {
      "Try MarkdownUI"
    }
    Paragraph {
      Strong("MarkdownUI")
      " is a native Markdown renderer for SwiftUI"
      " compatible with the "
      InlineLink(
        "GitHub Flavored Markdown Spec",
        destination: URL(string: "https://github.github.com/gfm/")!
      )
      "."
    }
  }
}
```

![](Sources/MarkdownUI/Documentation.docc/Resources/MarkdownContentBuilder@2x.png#gh-light-mode-only)
![](Sources/MarkdownUI/Documentation.docc/Resources/MarkdownContentBuilder~dark@2x.png#gh-dark-mode-only)

You can also create a `MarkdownContent` value in your model layer and later create a `Markdown`
view by passing the content value to the `init(_:baseURL:imageBaseURL:)` initializer. The
`MarkdownContent` value pre-parses the Markdown string preventing the view from doing this step.

```swift
// Somewhere in the model layer
let content = MarkdownContent("You can try **CommonMark** [here](https://spec.commonmark.org/dingus/).")

// Later in the view layer
var body: some View {
  Markdown(self.model.content)
}
```

### Styling Markdown

Markdown views use a basic default theme to display the contents. For more information, read about
the `basic` theme.

```swift
Markdown {
  """
  You can quote text with a `>`.

  > Outside of a dog, a book is man's best friend. Inside of a
  > dog it's too dark to read.

  – Groucho Marx
  """
}
```

![](Sources/MarkdownUI/Documentation.docc/Resources/BlockquoteContent@2x.png#gh-light-mode-only)
![](Sources/MarkdownUI/Documentation.docc/Resources/BlockquoteContent~dark@2x.png#gh-dark-mode-only)

You can customize the appearance of Markdown content by applying different themes using the
`markdownTheme(_:)` modifier. For example, you can apply one of the built-in themes, like
`gitHub`, to either a Markdown view or a view hierarchy that contains Markdown views.

```swift
Markdown {
  """
  You can quote text with a `>`.

  > Outside of a dog, a book is man's best friend. Inside of a
  > dog it's too dark to read.

  – Groucho Marx
  """
}
.markdownTheme(.gitHub)
```

![](Sources/MarkdownUI/Documentation.docc/Resources/GitHubBlockquote@2x.png#gh-light-mode-only)
![](Sources/MarkdownUI/Documentation.docc/Resources/GitHubBlockquote~dark@2x.png#gh-dark-mode-only)

To override a specific text style from the current theme, use the `markdownTextStyle(_:textStyle:)`
modifier. The following example shows how to override the `code` text style.

```swift
Markdown {
  """
  Use `git status` to list all new or modified files
  that haven't yet been committed.
  """
}
.markdownTextStyle(\.code) {
  FontFamilyVariant(.monospaced)
  FontSize(.em(0.85))
  ForegroundColor(.purple)
  BackgroundColor(.purple.opacity(0.25))
}
```

![](Sources/MarkdownUI/Documentation.docc/Resources/CustomInlineCode@2x.png#gh-light-mode-only)
![](Sources/MarkdownUI/Documentation.docc/Resources/CustomInlineCode~dark@2x.png#gh-dark-mode-only)

You can also use the `markdownBlockStyle(_:body:)` modifier to override a specific block style. For
example, you can override only the `blockquote` block style, leaving other block styles untouched.

```swift
Markdown {
  """
  You can quote text with a `>`.

  > Outside of a dog, a book is man's best friend. Inside of a
  > dog it's too dark to read.

  – Groucho Marx
  """
}
.markdownBlockStyle(\.blockquote) { configuration in
  configuration.label
    .padding()
    .markdownTextStyle {
      FontCapsVariant(.lowercaseSmallCaps)
      FontWeight(.semibold)
      BackgroundColor(nil)
    }
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Color.teal)
        .frame(width: 4)
    }
    .background(Color.teal.opacity(0.5))
}
```

![](Sources/MarkdownUI/Documentation.docc/Resources/CustomBlockquote@2x.png#gh-light-mode-only)
![](Sources/MarkdownUI/Documentation.docc/Resources/CustomBlockquote~dark@2x.png#gh-dark-mode-only)

Another way to customize the appearance of Markdown content is to create your own theme. To create
a theme, start by instantiating an empty `Theme` and chain together the different text and block
styles in a single expression.

```swift
extension Theme {
  static let fancy = Theme()
    .code {
      FontFamilyVariant(.monospaced)
      FontSize(.em(0.85))
    }
    .link {
      ForegroundColor(.purple)
    }
    // More text styles...
    .paragraph { configuration in
      configuration.label
        .relativeLineSpacing(.em(0.25))
        .markdownMargin(top: 0, bottom: 16)
    }
    .listItem { configuration in
      configuration.label
        .markdownMargin(top: .em(0.25))
    }
    // More block styles...
}
```

## Documentation

[Swift Package Index](https://swiftpackageindex.com) kindly hosts the online documentation for all versions, available here:

- [main](https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui/main/documentation/markdownui)
- [2.1.0](https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui/2.1.0/documentation/markdownui)
- [2.0.2](https://swiftpackageindex.com/gonzalezreal/swift-markdown-ui/2.0.2/documentation/markdownui)

### Related content

You can learn more about MarkdownUI by referring to the following articles and third-party resources:

- [Better Markdown Rendering in SwiftUI](https://gonzalezreal.github.io/2023/02/18/better-markdown-rendering-in-swiftui.html)
- [Unlock the Power of Markdown in SwiftUI with THIS Hack!](https://youtu.be/gVy06iJQFWQ) by [@Rebeloper](https://twitter.com/Rebeloper)

## Demo

MarkdownUI comes with a few more tricks on the sleeve. You can explore the
[companion demo project](Examples/Demo/) and discover its complete set of capabilities.

![](Examples/Demo/Screenshot.png#gh-light-mode-only)
![](Examples/Demo/Screenshot~dark.png#gh-dark-mode-only)

## Installation
### Adding MarkdownUI to a Swift package

To use MarkdownUI in a Swift Package Manager project, add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2")
```

Include `"MarkdownUI"` as a dependency for your executable target:

```swift
.target(name: "<target>", dependencies: [
  .product(name: "MarkdownUI", package: "swift-markdown-ui")
]),
```

Finally, add `import MarkdownUI` to your source code.

### Adding MarkdownUI to an Xcode project

1. From the **File** menu, select **Add Packages…**
1. Enter `https://github.com/gonzalezreal/swift-markdown-ui` into the
   *Search or Enter Package URL* search field
1. Link **MarkdownUI** to your application target
