# Tree Outline Preview Design

## Goal

Add a lazy structural preview to tree mode. JSON, Markdown, and Python files
show compact outlines by default; `<M-o>` toggles between the outline and
Telescope's existing full-file preview. List mode remains unchanged.

## User Experience

- The outline is shown in Telescope's preview pane, not in the results tree.
- Tree mode starts with the outline previewer active.
- `<M-o>` cycles between outline and full-file previewers without replacing
  Telescope's `<Tab>` multi-selection mapping.
- Unsupported files and directories retain Telescope's normal preview.
- JSON objects show top-level key names in source order.
- Markdown shows headings only. Heading level controls indentation, so level 2
  is indented once, level 3 twice, and so on. Headings in fenced code blocks are
  ignored.
- Python shows class and function names with distinct symbols. Nesting of
  classes, methods, and inner functions is represented by indentation; bodies
  and signatures are omitted.

## Architecture

Create an isolated `outline.lua` module with pure extractors for JSON,
Markdown, and Python plus a Telescope buffer previewer constructor. The
extractors accept lines and return outline lines, which allows focused unit
tests without opening a picker.

Tree-mode picker construction supplies two previewers to Telescope: the outline
previewer and the existing configured file previewer. Telescope already owns
previewer cycling and buffer caching, so `<M-o>` maps to its
`cycle_previewers_next` action. Non-tree picker construction continues to pass
only the configured file previewer.

The outline previewer recognizes supported files by extension. It invokes
Telescope's configured `buffer_previewer_maker` only when a supported entry is
selected, inheriting Telescope's asynchronous reading, file-size limit,
timeout, and buffer cache. Once the selected file has loaded, the callback
replaces its raw lines with the extracted outline. An unsupported entry is
passed straight through to the normal buffer maker.

## Extraction Rules

### JSON

A small lexical scan tracks JSON strings, escapes, arrays, and object depth. If
the root value is an object, string keys followed by a colon at root-object
depth are emitted in source order. Nested keys are ignored. A root array or
scalar produces an empty outline message.

### Markdown

ATX headings (`#` through `######`) are emitted without marker text or trailing
closing hashes. The parser tracks backtick and tilde fences so heading-like
lines inside fenced code are ignored. Indentation is two spaces per level below
level 1.

### Python

Lines beginning with `class`, `def`, or `async def` after indentation are
recognized. A stack of definition indentation levels determines structural
nesting while ignoring non-definition body lines. Class and function rows use
distinct Nerd Font symbols already consistent with the plugin's icon-based UI,
and contain names only.

## Error and Edge Handling

- Missing, unreadable, oversized, timed-out, and binary files retain
  Telescope's existing preview messages.
- Invalid or incomplete supported content displays a concise `No outline
  available` message rather than raising an error.
- Empty outlines are valid and do not affect picker navigation.
- Parser work is limited to the currently selected supported file and is cached
  by Telescope for the picker session.
- User-supplied tree mappings keep priority over the default `<M-o>` mapping.

## Verification

- Unit tests cover top-level-only JSON keys and source order, nested Markdown
  heading indentation and fenced-code exclusion, and nested Python class,
  method, async-function, and inner-function symbols.
- Picker tests prove tree mode installs outline/raw previewers and `<M-o>`, while
  list mode retains one previewer.
- Run the focused tests and the complete Plenary suite.

