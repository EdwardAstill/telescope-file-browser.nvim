# Tree File Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an expandable, fixed-root Telescope file tree whose fuzzy search preserves ancestor paths and expands matching folder subtrees, then enable it in the user's Neovim config on `<leader>t`.

**Architecture:** A pure tree-state module indexes cached file-browser entries and projects either manual expansion state or a search-specific hierarchy. The current finder gains a recursive tree catalog and stable-order callable finder, while entry display, actions, and picker configuration add the UI behavior without changing list mode.

**Tech Stack:** Lua, Neovim 0.12, Telescope, Plenary, fd, Plenary Busted tests, lazy.nvim.

**Spec:** `docs/superpowers/specs/2026-08-30-tree-file-browser-design.md`

## Global Constraints

- The picker root is Neovim's current working directory and never changes when a directory row is selected.
- Empty-prompt browsing shows only root children and descendants of manually expanded directories.
- File search matches include their ancestor chain; directory search matches include ancestors and the complete recursive subtree.
- Search projection never mutates manual expanded/collapsed state.
- Tree results retain deterministic depth-first order instead of fuzzy-score order.
- Default normal mappings are `i` up, `k` down, `j` collapse, `l` expand, `<CR>` open file only, and `/` search.
- All tree controls remain replaceable through Telescope extension mappings.
- Existing list mode and filesystem actions remain compatible.
- Preserve every unrelated existing change in `/home/eastill/dotfiles`.

---

### Task 1: Tree state and hierarchy projection

**Files:**
- Create: `lua/telescope/_extensions/file_browser/tree.lua`
- Create: `lua/tests/tree_spec.lua`

**Interfaces:**
- Produces: `Tree.new(root, entries, opts) -> Tree`
- Produces: `Tree:expand(path) -> boolean`
- Produces: `Tree:collapse(path) -> string?` where the return is the row to select
- Produces: `Tree:parent(path) -> string?`
- Produces: `Tree:project(prompt) -> entry[]`
- Entry input fields: `path: string`, `ordinal: string`, `is_dir: boolean`
- Projected metadata: `_tree_depth: integer`, `_tree_expanded: boolean`, `_tree_has_children: boolean`

- [x] **Step 1: Write failing tree projection tests**

```lua
local Tree = require "telescope._extensions.file_browser.tree"

local root = "/project"
local function entry(path, is_dir)
  return { path = path, value = path, ordinal = path:sub(#root + 2), is_dir = is_dir }
end
local entries = {
  entry("/project/README.md", false),
  entry("/project/src", true),
  entry("/project/src/main.lua", false),
  entry("/project/src/util", true),
  entry("/project/src/util/parser.lua", false),
  entry("/project/tests", true),
  entry("/project/tests/parser_spec.lua", false),
}
local function paths(projected)
  return vim.tbl_map(function(item) return item.path end, projected)
end

describe("tree projection", function()
  it("starts with only sorted root children", function()
    local tree = Tree.new(root, entries, { grouped = true })
    assert.are.same({ "/project/src", "/project/tests", "/project/README.md" }, paths(tree:project ""))
  end)

  it("expands and collapses without losing nested state", function()
    local tree = Tree.new(root, entries, { grouped = true })
    assert.is_true(tree:expand "/project/src")
    assert.is_true(tree:expand "/project/src/util")
    assert.are.same("/project/src", tree:collapse "/project/src/main.lua")
    assert.are.same({ "/project/src", "/project/tests", "/project/README.md" }, paths(tree:project ""))
    assert.is_true(tree:expand "/project/src")
    assert.are.same({
      "/project/src", "/project/src/util", "/project/src/util/parser.lua", "/project/src/main.lua",
      "/project/tests", "/project/README.md",
    }, paths(tree:project ""))
  end)

  it("shows ancestors for a matching file", function()
    local tree = Tree.new(root, entries, { grouped = true })
    assert.are.same({ "/project/src", "/project/src/main.lua" }, paths(tree:project "main"))
  end)

  it("shows ancestors and the full subtree for a matching folder", function()
    local tree = Tree.new(root, entries, { grouped = true })
    assert.are.same({
      "/project/src", "/project/src/util", "/project/src/util/parser.lua",
    }, paths(tree:project "util"))
  end)

  it("restores manual expansion after clearing search", function()
    local tree = Tree.new(root, entries, { grouped = true })
    tree:expand "/project/tests"
    tree:project "parser"
    assert.are.same({
      "/project/src", "/project/tests", "/project/tests/parser_spec.lua", "/project/README.md",
    }, paths(tree:project ""))
  end)
end)
```

- [x] **Step 2: Run the focused test and verify RED**

Run: `make test-deps && nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/tree_spec.lua')"`

Expected: FAIL because `telescope._extensions.file_browser.tree` does not exist.

- [x] **Step 3: Implement the minimal tree model**

Create a `Tree` object that normalizes the root with `fb_utils.sanitize_path_str`, indexes entries by path, indexes each path's parent using `plenary.path`, sorts each children array with directories first only when `opts.grouped`, and keeps an `expanded` set. `project("")` must depth-first walk only expanded branches. `project(prompt)` must use `telescope.algos.fzy.has_match`, add ancestors for every direct match, add all descendants for direct directory matches, then depth-first walk only the include set while assigning the three `_tree_*` fields.

```lua
local fzy = require "telescope.algos.fzy"
local Path = require "plenary.path"
local fb_utils = require "telescope._extensions.file_browser.utils"

local Tree = {}
Tree.__index = Tree

function Tree.new(root, entries, opts)
  local self = setmetatable({
    root = fb_utils.sanitize_path_str(root),
    entries = {}, children = {}, parents = {}, expanded = {},
    grouped = opts and opts.grouped or false,
  }, Tree)
  self.children[self.root] = {}
  for _, item in ipairs(entries) do
    local path = fb_utils.sanitize_path_str(item.path)
    local parent = fb_utils.sanitize_path_str(Path:new(path):parent():absolute())
    item.path = path
    self.entries[path] = item
    self.parents[path] = parent
    self.children[parent] = self.children[parent] or {}
    self.children[path] = self.children[path] or {}
    table.insert(self.children[parent], item)
  end
  for _, children in pairs(self.children) do
    table.sort(children, function(left, right)
      if self.grouped and left.is_dir ~= right.is_dir then return left.is_dir end
      return left.path:lower() < right.path:lower()
    end)
  end
  return self
end

function Tree:expand(path)
  local item = self.entries[path]
  if not item or not item.is_dir or #(self.children[path] or {}) == 0 then return false end
  self.expanded[path] = true
  return true
end

function Tree:collapse(path)
  local item = self.entries[path]
  if item and item.is_dir and self.expanded[path] then
    self.expanded[path] = nil
    return path
  end
  local parent = self.parents[path]
  if not parent or parent == self.root then return nil end
  self.expanded[parent] = nil
  return parent
end
```

- [x] **Step 4: Run the focused test and verify GREEN**

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/tree_spec.lua')"`

Expected: all tree projection tests PASS.

- [x] **Step 5: Commit the tree model**

```bash
git add lua/telescope/_extensions/file_browser/tree.lua lua/tests/tree_spec.lua
git commit -m "feat: add tree hierarchy projection"
```

### Task 2: Recursive tree finder and stable-order picker

**Files:**
- Modify: `lua/telescope/_extensions/file_browser/finders.lua`
- Modify: `lua/telescope/_extensions/file_browser/picker.lua`
- Create: `lua/tests/tree_finder_spec.lua`

**Interfaces:**
- Consumes: `Tree.new`, `Tree:project`
- Produces: `fb_finders.browse_tree(opts) -> callable finder`
- Finder fields: `tree_state: Tree`, `results: entry[]`, `close(): nil`
- Outer finder fields: `tree: boolean`, `_browse_tree: function`, proxied `tree_state`

- [x] **Step 1: Write a failing real-filesystem finder test**

Create a temporary directory containing `src/main.lua`, `src/util/parser.lua`, and `README.md`. Supply a real entry maker that uses `vim.uv.fs_stat(path).type == "directory"`, call `fb_finders.browse_tree` with `use_fd = false`, `git_status = false`, `hidden = true`, and collect results through the finder's callable interface. Assert the empty prompt returns `src` and `README.md`, expanding `src` reveals its children, and prompt `parser` returns `src`, `src/util`, and `src/util/parser.lua` in order. Remove the temporary directory in `after_each`.

- [x] **Step 2: Run the focused finder test and verify RED**

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/tree_finder_spec.lua')"`

Expected: FAIL because `fb_finders.browse_tree` does not exist.

- [x] **Step 3: Implement the recursive catalog and callable finder**

`browse_tree` must force files plus directories and unlimited depth, collect Git status through the existing code path, convert paths with the configured entry maker, construct one `Tree`, and return a callable object. On each call, set `self.results = self.tree_state:project(prompt)`, assign stable `entry.index` values, invoke `process_result` in order, and then invoke `process_complete`.

Extend the outer finder so `tree = true` selects `_browse_tree`; list and folder branches remain byte-for-byte behaviorally equivalent. In `picker.lua`, default tree pickers to `initial_mode = "normal"`, use prompt title `Tree Browser`, and use `require("telescope.sorters").highlighter_only {}` so finder order remains stable.

- [x] **Step 4: Run finder and tree tests and verify GREEN**

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/tree_finder_spec.lua')"`

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/tree_spec.lua')"`

Expected: both files PASS.

- [x] **Step 5: Commit finder integration**

```bash
git add lua/telescope/_extensions/file_browser/finders.lua lua/telescope/_extensions/file_browser/picker.lua lua/tests/tree_finder_spec.lua
git commit -m "feat: add recursive tree finder"
```

### Task 3: Tree display, actions, and configurable controls

**Files:**
- Modify: `lua/telescope/_extensions/file_browser/make_entry_utils.lua`
- Modify: `lua/telescope/_extensions/file_browser/make_entry.lua`
- Modify: `lua/telescope/_extensions/file_browser/actions.lua`
- Modify: `lua/telescope/_extensions/file_browser/config.lua`
- Modify: `lua/telescope/_extensions/file_browser/picker.lua`
- Modify: `lua/telescope/_extensions/file_browser/utils.lua`
- Modify: `lua/tests/make_entry_spec.lua`
- Create: `lua/tests/tree_picker_spec.lua`

**Interfaces:**
- Produces: `make_entry_utils.get_tree_display(entry, opts) -> prefix, basename`
- Produces actions: `expand(prompt_bufnr)`, `collapse(prompt_bufnr)`, `enter_search()`, `normal_mode()`
- Produces options: `tree`, `tree_indent`, `tree_expanded`, `tree_collapsed`
- Consumes: outer finder `tree_state` and latest `results`

- [x] **Step 1: Write failing display-helper tests**

Add table-driven assertions to `make_entry_spec.lua`:

```lua
describe("get_tree_display", function()
  local opts = { tree_indent = "  ", tree_expanded = "v", tree_collapsed = ">" }
  it("renders collapsed and expanded directories", function()
    assert.are.same({ "> ", "src" }, {
      me_utils.get_tree_display({ path = "/p/src", is_dir = true, _tree_depth = 0, _tree_expanded = false }, opts),
    })
    assert.are.same({ "  v ", "util" }, {
      me_utils.get_tree_display({ path = "/p/src/util", is_dir = true, _tree_depth = 1, _tree_expanded = true }, opts),
    })
  end)
  it("aligns files under directory markers", function()
    assert.are.same({ "    ", "main.lua" }, {
      me_utils.get_tree_display({ path = "/p/src/main.lua", is_dir = false, _tree_depth = 1 }, opts),
    })
  end)
end)
```

- [x] **Step 2: Write a failing picker smoke test**

Open a real tree picker against a temporary directory with `tree = true`, `git_status = false`, `display_stat = false`, and an `attach_mappings` callback that records buffer-local mappings. Assert the current picker starts in normal mode, its finder exposes `tree_state`, directory selection through `action_set.select` leaves `finder.path` unchanged, and the configured tree actions exist. Close the picker and delete the temporary directory after the assertion.

- [x] **Step 3: Run display and picker tests and verify RED**

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/make_entry_spec.lua')"`

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/tree_picker_spec.lua')"`

Expected: FAIL because the display helper, tree options, and actions are missing.

- [x] **Step 4: Implement display and controls**

`get_tree_display` must use `vim.fs.basename(entry.path)`, prepend `tree_indent` once per depth, show the configured expanded/collapsed marker for directories, and reserve the same marker width with spaces for files. `make_entry.lua` must insert this prefix as a separately highlighted display segment and keep `entry.ordinal` unchanged.

In actions, tree create/copy/move targets resolve to the selected directory or selected file's parent. `expand` and `collapse` mutate `finder.tree_state`, queue selection restoration through `fb_utils.selection_callback`, and call `current_picker:refresh(nil, { reset_prompt = false, multi = current_picker._multi })`. They are no-ops while the prompt is non-empty. `enter_search` runs `startinsert`; `normal_mode` runs `stopinsert`.

Make selection restoration scan all `finder.results` in tree mode rather than requiring a shared immediate parent. In config, route directory selection to a no-op when `finder.tree` and to existing `open_dir` otherwise. Attach default tree mappings before user mappings so user configuration can override them:

```lua
map("n", "i", actions.move_selection_previous)
map("n", "k", actions.move_selection_next)
map("n", "j", fb_actions.collapse)
map("n", "l", fb_actions.expand)
map("n", "/", fb_actions.enter_search)
map("i", "<Esc>", fb_actions.normal_mode)
```

Set option defaults to `tree = false`, `tree_indent = "  "`, `tree_expanded = ""`, and `tree_collapsed = ""`. The dotfiles opt into tree mode.

- [x] **Step 5: Run focused tests and verify GREEN**

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/make_entry_spec.lua')"`

Run: `nvim --headless --noplugin -u scripts/minimal_init.vim -c "lua require('plenary.busted').run('lua/tests/tree_picker_spec.lua')"`

Expected: both files PASS with no warnings.

- [x] **Step 6: Run the full plugin suite**

Run: `make test`

Expected: every Plenary spec PASS.

- [x] **Step 7: Commit tree interaction**

```bash
git add lua/telescope/_extensions/file_browser lua/tests
git commit -m "feat: add expandable tree interaction"
```

### Task 4: Plugin documentation and compatibility verification

**Files:**
- Modify: `README.md`
- Modify: `lua/telescope/_extensions/file_browser/picker.lua`
- Modify: `lua/telescope/_extensions/file_browser/config.lua`
- Generated: `doc/telescope-file-browser.txt`

**Interfaces:**
- Documents the four tree options, default controls, fixed-root behavior, and search projection semantics.

- [x] **Step 1: Document tree setup and controls**

Add a concise README example with `tree = true`, describe `/`, `<Esc>`, `i/k/j/l`, and state that matching files reveal ancestors while matching folders reveal complete subtrees. Add EmmyLua option fields and action comments so docgen includes the new API.

- [x] **Step 2: Update and verify Vim help**

Run: `make docgen`. If the upstream bootstrap is unavailable, update the help
from the same annotated APIs and verify its tags with `:helptags doc` plus
`:help` lookups for each new action and finder.

Actual: the upstream bootstrap URL returned HTTP 404, so the help was updated
from the annotations and both new help tags were resolved successfully.

- [x] **Step 3: Run formatting and compatibility checks**

Run: `stylua --check lua` when `stylua` is installed; otherwise run `git diff --check` and parse each changed Lua file with `nvim --headless -u NONE -l` through `loadfile`.

Run: `make test`

Expected: formatting/parsing checks and all tests PASS.

- [x] **Step 4: Commit documentation**

```bash
git add README.md lua/telescope/_extensions/file_browser/picker.lua lua/telescope/_extensions/file_browser/config.lua doc/telescope-file-browser.txt
git commit -m "docs: describe tree browser mode"
```

### Task 5: Local Neovim integration

**Files:**
- Modify: `/home/eastill/dotfiles/app-configuration/nvim/.config/nvim/lua/plugins/telescope.lua`
- Modify: `/home/eastill/dotfiles/app-configuration/nvim/.config/nvim/lua/config/keymaps.lua`
- Modify: `/home/eastill/dotfiles/tests/nvim-shortcuts.lua`
- Modify: `/home/eastill/dotfiles/docs/apps/nvim.md`
- Modify: `/home/eastill/dotfiles/shortcuts/nvim.md`

**Interfaces:**
- Consumes local plugin directory: `~/projects/telescope-file-browser.nvim`
- Produces command mapping: `<leader>t -> <cmd>Telescope file_browser<cr>`
- Produces Telescope extension config: `tree = true`, `hidden = true`, `grouped = true`, fixed current working directory root.

- [ ] **Step 1: Add the failing shortcut expectation**

Extend the existing real Neovim shortcut test using its established assertion helper:

```lua
assert_map("n", "<leader>t", "<cmd>Telescope file_browser<cr>", "Project tree browser")
```

- [ ] **Step 2: Run the focused dotfiles test and verify RED**

Run the exact command documented at the top of `tests/nvim-shortcuts.lua` or used by `check-dotfiles` for that test file.

Expected: FAIL because `<leader>t` is not mapped.

- [ ] **Step 3: Configure lazy.nvim and Telescope**

Add this dependency to the existing Telescope spec without changing its current dependencies:

```lua
{
  dir = vim.fn.expand("~/projects/telescope-file-browser.nvim"),
  name = "telescope-file-browser.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
},
```

Add `extensions.file_browser = { tree = true, hidden = true, grouped = true, hide_parent_dir = true }`, call `pcall(telescope.load_extension, "file_browser")`, and add the central keymap:

```lua
map("n", "<leader>t", "<cmd>Telescope file_browser<cr>", { desc = "Project tree browser" })
```

- [ ] **Step 4: Update user-facing navigation docs**

Add `Space+t` to the Telescope/navigation tables and document the tree-local `i/k/j/l`, `/`, `<Esc>`, and `<CR>` controls. Keep `Space+f`, `Space+e`, and Neo-tree documentation unchanged.

- [ ] **Step 5: Run focused shortcut and headless load checks**

Run the focused shortcut test again.

Run:

```bash
nvim --headless "+lua local t=require('telescope'); assert(pcall(t.load_extension, 'file_browser')); local e=t.extensions.file_browser; assert(type(e.file_browser)=='function'); assert(type(e.actions.expand)=='table' or type(e.actions.expand)=='function')" +qa
```

Expected: shortcut test PASS and Neovim exits 0.

- [ ] **Step 6: Run repository and final plugin verification**

Run: `check-dotfiles`

Run in the plugin checkout: `make test`

Run in both repositories: `git diff --check`

Expected: all checks PASS. Any pre-existing dotfiles failure must be reported with evidence and kept separate from this change.

- [ ] **Step 7: Review the final diffs**

Confirm the plugin branch contains only the design, plan, tree implementation, tests, and docs. Confirm the dotfiles diff contains only surgical additions to the five scoped files and preserves every pre-existing change.
