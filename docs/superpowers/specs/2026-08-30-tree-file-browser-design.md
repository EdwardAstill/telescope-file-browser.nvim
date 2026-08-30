# Tree File Browser Design

## Goal

Add a Telescope file browser mode that keeps a fixed project root and displays
folders as an expandable tree. Searching must preserve hierarchy: a matching
file shows its ancestor chain, while a matching folder shows its ancestor chain
and complete recursive subtree.

The local Neovim configuration in `/home/eastill/dotfiles` will load this fork
from `~/projects/telescope-file-browser.nvim` and open it with `<leader>t`.
Existing `<leader>f` and Yazi mappings remain unchanged.

## User Experience

- The picker is rooted at Neovim's current working directory.
- Only the root's direct children are initially visible. Directories start
  collapsed and the root itself is not rendered as a row.
- Results use depth-first tree order with indentation and distinct expanded and
  collapsed directory markers. They are never rearranged into a flat fuzzy
  ranking.
- The picker keeps the search prompt active (implemented with Neovim's insert
  mode), and results update after every typed character.
- Default controls are configurable through Telescope's extension mappings:
  - `<Up>`: move to the previous visible row without leaving the prompt.
  - `<Down>`: move to the next visible row without leaving the prompt.
  - `<Left>`: collapse the selected directory; do nothing on a file.
  - `<Right>`: expand the selected directory; do nothing on a file.
  - `<CR>`: open a file. It does nothing on a directory by default.
  - `<Esc>`: close the picker.
- Backspace and `/` edit the prompt normally. In particular, Backspace on an
  empty prompt never changes the browser root.
- Clearing the prompt restores the exact manual expanded/collapsed state that
  existed before searching.

## Search Semantics

The browser catalogs the full project tree while respecting the existing
hidden-file, ignore-file, Git-ignore, and symlink options. A non-empty prompt is
matched case-insensitively with Telescope's built-in fzy subsequence matcher
against each entry's path relative to the picker root.

The search projection is computed without mutating manual expansion state:

- For a matching file, include the file and every ancestor directory between it
  and the root.
- For a matching directory, include that directory, every ancestor directory,
  and every descendant file and directory recursively.
- Merge overlapping projections without duplicates.
- Render the merged projection in depth-first tree order. Any directory whose
  descendants are visible in the projection uses the expanded marker.

Because descendant relative paths contain their ancestor names, a folder-name
query naturally exposes that folder's complete subtree. Explicit directory
matches receive the same treatment even when no descendant path independently
matches.

## Architecture

### Tree state and projection

Create `lua/telescope/_extensions/file_browser/tree.lua` as the isolated tree
model. It receives the root path and the current catalog of file-browser entries
and builds parent/children indexes. It owns only manual expansion state and
provides operations to expand, collapse, locate a parent, and project visible
entries for either an empty or non-empty prompt.

The module returns existing cached file-browser entry objects rather than
inventing a second entry type. It annotates projected entries with transient
tree display metadata: depth, whether a directory is rendered expanded, and
whether it has children. Projection order is deterministic and follows the
existing `grouped` option within each directory.

### Finder integration

Extend `finders.lua` with a tree browser that obtains one recursive catalog using
the existing `fd` or Plenary scanning paths and existing option handling. The
tree finder is callable by Telescope and stores its latest projected results so
selection restoration and existing actions can inspect them.

The outer file-browser finder retains current list/folder behavior when tree
mode is disabled. When tree mode is enabled, its fixed `path` is the tree root,
it delegates each prompt update to the tree finder, and it exposes the tree
state to actions. Filesystem mutations close the inner finder so the catalog is
rebuilt; expand and collapse refresh only the projection and do not rescan disk.

### Stable-order search sorter

Tree projection performs filtering, so the picker uses Telescope's
`highlighter_only` sorter in tree mode. All projected rows receive the same
score, preserving finder order, while direct fuzzy matches still receive normal
prompt highlighting. List mode continues to use the configured file sorter.

### Entry display

Extend `make_entry.lua` to render tree rows from the transient metadata. A tree
row displays indentation, an expanded/collapsed marker for directories, the
existing icon, the basename, Git status, and configured stat columns. Its
ordinal remains the relative path so search can match both leaf names and path
segments. Non-tree display remains unchanged.

### Actions and mappings

Add exported `expand` and `collapse` actions.
Expand and collapse mutate only the tree state, preserve the logical selection,
and refresh the current projection. Existing file actions continue to use the
selected entry; create/copy/move targets resolve to the selected directory or a
selected file's parent in tree mode.

The directory branch of the default select action becomes a no-op in tree mode,
so `<CR>` can never change the browser root. The existing Miller-style
`open_dir` action remains available only for list mode, preserving compatibility
for users who do not enable the tree.

New `tree`, `tree_indent`, `tree_expanded`, and `tree_collapsed` options control
the mode and display. Telescope extension mappings remain the authoritative way
to replace any default control.

## Error and Edge Handling

- An empty catalog renders an empty picker without errors.
- Expanding a file or a directory without children is a no-op.
- Collapsing at the root level when no parent row exists is a no-op.
- Deleted or renamed paths trigger a catalog rebuild through the existing
  filesystem action refreshes.
- Paths unreadable between cataloging and display retain the plugin's existing
  warning and broken-entry behavior.
- The fixed root prevents directory selection from changing Neovim's working
  directory. The explicit existing `change_cwd` action remains available when
  users map it themselves.

## Dotfiles Integration

Update the existing Telescope plugin specification to add the local fork as a
dependency using `dir = vim.fn.expand("~/projects/telescope-file-browser.nvim")`,
configure tree mode and its default controls, and load the `file_browser`
extension after Telescope setup. Override tree `<CR>` so files retain
Telescope's default open behavior, while directories close the picker and open
embedded Yazi at the selected path.

Add `<leader>t` to the central keymap file as `Telescope file_browser`, with a
description identifying it as the project tree browser. Update the Neovim docs,
shortcut reference, and shortcut verification without modifying unrelated
in-progress dotfiles changes.

## Verification

Use test-driven development for executable behavior.

- Unit-test initial collapsed projection, nested expansion, selected-directory collapse,
  deterministic order, and empty trees.
- Unit-test file matches including exactly their ancestor chain.
- Unit-test folder matches including ancestors and the complete recursive
  subtree.
- Unit-test overlapping matches for deduplication and clearing the prompt for
  manual-state restoration.
- Unit-test configurable tree markers and entry display metadata.
- Run the plugin's full Plenary suite.
- Run headless Neovim checks that the local extension loads and the tree picker
  options/actions are available.
- Run the focused dotfiles Neovim shortcut checks, then `check-dotfiles` as the
  repository handoff check.
