# Tree Outline Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add lazy JSON, Markdown, and Python outlines to the tree-mode preview pane, with `<M-o>` toggling to Telescope's full-file preview.

**Architecture:** A focused outline module exposes pure line extractors and constructs a Telescope buffer previewer. Tree-mode picker construction supplies that previewer before the existing raw previewer, allowing Telescope's built-in previewer cycling, async file loading, limits, and cache to provide the lifecycle.

**Tech Stack:** Lua, Neovim 0.12, Telescope buffer previewers, Plenary Busted.

**Spec:** `docs/superpowers/specs/2026-08-31-tree-outline-preview-design.md`

## Global Constraints

- Enable outlines only when `tree = true`; list mode remains unchanged.
- Parse only the currently selected preview entry, never the recursive file catalog.
- Add no runtime dependencies beyond Telescope and Plenary.
- `<M-o>` toggles outline/full preview without changing `<Tab>` multi-selection.
- JSON emits source-ordered top-level object key names only.
- Markdown emits heading text with two-space indentation per level and ignores fenced code.
- Python emits class/function symbols and names with two-space structural indentation; bodies and signatures are omitted.
- Preserve all unrelated uncommitted changes already present in the worktree.

---

### Task 1: Pure outline extraction

**Files:**
- Create: `lua/telescope/_extensions/file_browser/outline.lua`
- Create: `lua/tests/outline_spec.lua`

**Interfaces:**
- Produces: `outline.supports(path: string) -> boolean`
- Produces: `outline.extract(path: string, lines: string[]) -> string[]?`
- JSON, Markdown, and Python-specific extractors remain module-local.

- [ ] **Step 1: Write failing extraction tests**

Create `lua/tests/outline_spec.lua` with examples that assert:

```lua
local outline = require "telescope._extensions.file_browser.outline"

describe("outline extraction", function()
  it("extracts source-ordered top-level JSON keys only", function()
    assert.are.same({ "name", "nested", "enabled" }, outline.extract("config.json", {
      "{",
      '  "name": "demo",',
      '  "nested": { "ignored": true },',
      '  "enabled": true',
      "}",
    }))
  end)

  it("indents Markdown headings and ignores fenced code", function()
    assert.are.same({ "Guide", "  Setup", "    Linux" }, outline.extract("README.md", {
      "# Guide",
      "## Setup",
      "```python",
      "### ignored",
      "```",
      "### Linux ###",
    }))
  end)

  it("shows nested Python class and function symbols", function()
    assert.are.same({
      "󰠱 Client",
      "  󰊕 fetch",
      "    󰊕 parse",
      "󰊕 main",
    }, outline.extract("client.py", {
      "class Client:",
      "    async def fetch(self):",
      "        def parse():",
      "            pass",
      "def main():",
      "    pass",
    }))
  end)

  it("supports only requested extensions", function()
    assert.is_true(outline.supports "a.json")
    assert.is_true(outline.supports "a.md")
    assert.is_true(outline.supports "a.markdown")
    assert.is_true(outline.supports "a.py")
    assert.is_false(outline.supports "a.lua")
    assert.is_nil(outline.extract("a.lua", { "return true" }))
  end)
end)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
nvim --headless --noplugin -u scripts/minimal_init.vim \
  -c "lua require('plenary.busted').run('lua/tests/outline_spec.lua')"
```

Expected: FAIL because `telescope._extensions.file_browser.outline` does not exist.

- [ ] **Step 3: Implement minimal pure extractors**

Create `outline.lua` with extension dispatch and these rules:

```lua
local handlers = {
  json = extract_json,
  md = extract_markdown,
  markdown = extract_markdown,
  py = extract_python,
}

function M.supports(path)
  local extension = path:lower():match "%.([^./\\]+)$"
  return handlers[extension] ~= nil
end

function M.extract(path, lines)
  local extension = path:lower():match "%.([^./\\]+)$"
  local handler = handlers[extension]
  return handler and handler(lines) or nil
end
```

The JSON extractor must lex quoted strings and escapes, record a string only
when the root value is an object and the following token is `:` at object depth
one, and decode escaped key text with `vim.json.decode`. The Markdown extractor
must track matching three-or-more backtick/tilde fences and emit ATX headings
with `string.rep("  ", level - 1)`. The Python extractor must match `class`,
`def`, and `async def`, calculate leading whitespace columns (tab stop eight),
and pop a definition stack while the current indent is less than or equal to
the stack top.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: all outline extraction tests PASS.

- [ ] **Step 5: Commit extraction**

```bash
git add lua/telescope/_extensions/file_browser/outline.lua lua/tests/outline_spec.lua
git commit -m "feat: extract lazy file outlines"
```

---

### Task 2: Lazy previewer and tree-mode toggle

**Files:**
- Modify: `lua/telescope/_extensions/file_browser/outline.lua`
- Modify: `lua/telescope/_extensions/file_browser/picker.lua`
- Modify: `lua/telescope/_extensions/file_browser/config.lua`
- Modify: `lua/tests/outline_spec.lua`
- Modify: `lua/tests/tree_picker_spec.lua`

**Interfaces:**
- Consumes: `outline.supports(path)` and `outline.extract(path, lines)` from Task 1.
- Produces: `outline.new(opts: table) -> telescope.Previewer`
- Produces: tree-mode `picker.all_previewers = { outline_previewer, raw_previewer }`.
- Produces: default tree insert mapping `<M-o> = telescope.actions.cycle_previewers_next`.

- [ ] **Step 1: Write failing previewer integration tests**

Extend `outline_spec.lua` with an injected buffer-maker test proving
`outline.new()` does not call the maker until `define_preview` is invoked for an
entry, then extracts only that selected path. Extend the first tree picker test
to assert:

```lua
assert.are.same(2, #picker.all_previewers)
assert.are.same(1, picker.current_previewer_index)
assert.is_not_nil(mapped["<M-o>"])
mapped["<M-o>"].callback(prompt_bufnr)
assert.are.same(2, picker.current_previewer_index)
```

The injected maker invokes its callback after filling the provided buffer with
the selected JSON fixture, allowing the test to assert the resulting buffer
contains only its top-level keys.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
nvim --headless --noplugin -u scripts/minimal_init.vim \
  -c "lua require('plenary.busted').run('lua/tests/outline_spec.lua')"
nvim --headless --noplugin -u scripts/minimal_init.vim \
  -c "lua require('plenary.busted').run('lua/tests/tree_picker_spec.lua')"
```

Expected: FAIL because `outline.new`, the second tree previewer, and `<M-o>` are missing.

- [ ] **Step 3: Implement the lazy buffer previewer**

Add `outline.new(opts)` using `require("telescope.previewers").new_buffer_previewer`.
Resolve the selected path with `telescope.from_entry.path`, use that path from
`get_buffer_by_name` for Telescope's per-entry cache, and call the configured
buffer maker from `define_preview`. In the maker callback, transform the loaded
buffer only for supported paths that were not already cached:

```lua
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local extracted = M.extract(path, lines)
vim.api.nvim_buf_set_lines(
  bufnr,
  0,
  -1,
  false,
  extracted and #extracted > 0 and extracted or { "No outline available" }
)
```

Accept `opts.buffer_previewer_maker` as a test seam and otherwise use
`require("telescope.config").values.buffer_previewer_maker`. Pass through
Telescope's `preview` and `file_encoding` options. Unsupported paths are loaded
unchanged. Do not scan directories or catalog entries in the constructor.

- [ ] **Step 4: Install two previewers and the mapping only in tree mode**

In `picker.lua`, construct the configured raw previewer once. When `opts.tree`
and the raw previewer is enabled, pass `{ outline.new(opts), raw_previewer }` as
the picker default; otherwise pass the raw previewer unchanged.

In `config.lua`, add:

```lua
["<M-o>"] = telescope_actions.cycle_previewers_next,
```

to insert-mode `tree_mappings`. Keep the existing user-mapping precedence logic.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run both commands from Step 2.

Expected: both specs PASS.

- [ ] **Step 6: Commit preview integration**

```bash
git add lua/telescope/_extensions/file_browser/outline.lua \
  lua/telescope/_extensions/file_browser/picker.lua \
  lua/telescope/_extensions/file_browser/config.lua \
  lua/tests/outline_spec.lua lua/tests/tree_picker_spec.lua
git commit -m "feat: add lazy tree outline preview"
```

---

### Task 3: User documentation and regression verification

**Files:**
- Modify: `README.md`
- Modify: `doc/telescope-file-browser.txt`

**Interfaces:**
- Documents: tree outline formats, lazy selection-time behavior, and `<M-o>` toggle.

- [ ] **Step 1: Update tree-mode documentation**

Add a short `Outline preview` paragraph to the tree-mode sections in both files
describing JSON top-level keys, indented Markdown headings, indented Python
class/function symbols, lazy selected-file processing, and fallback to normal
preview for unsupported files. Add `<M-o>` to the tree controls table as
`Toggle outline / full-file preview`.

- [ ] **Step 2: Run documentation and whitespace checks**

Run:

```bash
git diff --check
make docgen
git diff --check
```

Expected: commands exit 0; generated Vim help remains consistent.

- [ ] **Step 3: Run the complete test suite**

Run:

```bash
make test
```

Expected: all Plenary specs PASS with no errors.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md doc/telescope-file-browser.txt
git commit -m "docs: describe tree outline previews"
```

