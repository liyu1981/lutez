// Demo examples, ordered from simple to complex.
export const examples = [
  {
    id: "hello",
    label: "Hello",
    difficulty: "simple",
    markdown: `# Hello, Markdown

A **paragraph** with *emphasis*, \`inline code\`, and an
[inline link](https://commonmark.org "spec").

> Blockquotes nest containers.
`,
  },
  {
    id: "links",
    label: "Links & images",
    difficulty: "simple",
    markdown: `# Links and images

[inline](https://example.com/path?q=1) ·
[reference][ref] · [collapsed][] · <https://example.com>

![alt text](/img/logo.png "title")

[ref]: https://example.com/ref "Reference title"
[collapsed]: https://example.com/collapsed
`,
  },
  {
    id: "lists",
    label: "Lists & tasks",
    difficulty: "medium",
    markdown: `# Lists & tasks

- [x] arena allocation
- [ ] C ABI accessors
  - nested item with *emphasis*
  - nested item with \`code\`

1. ordered
2. items
3. keep numbers

* loose list

* second paragraph
`,
  },
  {
    id: "tables",
    label: "Tables & strike",
    difficulty: "medium",
    markdown: `# GFM extensions

| backend | language | time |
|:--------|:--------:|-----:|
| lutez   | Zig      | 0.91 |
| lute    | Go       | 3.54 |

~~struck through~~ and ~single tilde~.

- [ ] task list inside a table row reference: [spec](https://github.github.com/gfm/)
`,
  },
  {
    id: "code",
    label: "Code & HTML",
    difficulty: "complex",
    markdown: `# Code and HTML

\`\`\`zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("hello {s}\\n", .{"wasm"});
}
\`\`\`

    indented code block
    keeps whitespace

<div class="note">
  <p>HTML blocks are scanned, not parsed.</p>
</div>

Inline <kbd>HTML</kbd> stays raw; entities: &copy; &#35; &#x1F600;.
`,
  },
  {
    id: "dialect",
    label: "Dialect extensions",
    difficulty: "complex",
    extensions: true,
    markdown: `---
title: Opal note
tags: [demo]
...

# Dialect extensions

Inline math $a^2 + b^2 = c^2$ and display $$\\int_0^1 x dx$$.
A [[wikilink|with alias]] and #topic/subtopic.

^block-42

- outliner:: value
- another:: property

$$
\\sum_{i=1}^{n} i
$$
`,
  },
  {
    id: "kitchen",
    label: "Kitchen sink",
    difficulty: "complex",
    markdown: `# Kitchen sink

A document that touches most of the grammar — headings, quotes, lists,
tables, code, HTML, entities, autolinks and Unicode.

## Sections

> Quote with **strong**, *em*, \`code\`, and a [link][ref].
>
> > nested quote
>
> 1. ordered inside quote
> 2. second

### Lists

- [x] done
- [ ] todo
    - nested with ~~strike~~
    - nested with ~tilde~

### Table

| left | center | right |
|:-----|:------:|------:|
| a    | b      | c     |
| 1    | 2      | 3     |

### Code

\`\`\`go
func main() {
    fmt.Println("hi")
}
\`\`\`

    raw indented block

### Inline

Autolinks: <https://example.com> and www.example.com.
Entities: &amp; &copy; &#169;.
Escapes: \\*not emphasis\\*, \\[not a link\\].
Unicode: naïve — 中文 — 😀 — ẞ.

<div>block HTML</div>

[ref]: https://example.com "title"
`,
  },
];
