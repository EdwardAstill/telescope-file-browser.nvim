local fzy = require "telescope.algos.fzy"
local Path = require "plenary.path"

local fb_utils = require "telescope._extensions.file_browser.utils"

local Tree = {}
Tree.__index = Tree

local function normalize(path)
  return fb_utils.sanitize_path_str(path)
end

local function sort_children(children, grouped)
  table.sort(children, function(left, right)
    if grouped and left.is_dir ~= right.is_dir then
      return left.is_dir
    end

    local left_path = left.path:lower()
    local right_path = right.path:lower()
    if left_path == right_path then
      return left.path < right.path
    end
    return left_path < right_path
  end)
end

---@class telescope-file-browser.Tree
---@field root string
---@field entries table<string, table>
---@field children table<string, table[]>
---@field parents table<string, string>
---@field expanded table<string, boolean>
---@field grouped boolean

---@param root string
---@param entries table[]
---@param opts table?
---@return telescope-file-browser.Tree
function Tree.new(root, entries, opts)
  opts = opts or {}
  root = normalize(root)

  local self = setmetatable({
    root = root,
    entries = {},
    children = { [root] = {} },
    parents = {},
    expanded = {},
    grouped = vim.F.if_nil(opts.grouped, false),
  }, Tree)

  for _, entry in ipairs(entries) do
    local path = normalize(entry.path)
    if path ~= root then
      local parent = normalize(Path:new(path):parent():absolute())
      entry.path = path
      entry.value = path
      self.entries[path] = entry
      self.parents[path] = parent
      self.children[parent] = self.children[parent] or {}
      self.children[path] = self.children[path] or {}
      table.insert(self.children[parent], entry)
    end
  end

  for _, children in pairs(self.children) do
    sort_children(children, self.grouped)
  end

  return self
end

---@param path string
---@return string?
function Tree:parent(path)
  return self.parents[normalize(path)]
end

---@param path string
---@return boolean
function Tree:expand(path)
  path = normalize(path)
  local entry = self.entries[path]
  if not entry or not entry.is_dir or #(self.children[path] or {}) == 0 then
    return false
  end

  self.expanded[path] = true
  return true
end

---@param path string
---@return string?
function Tree:collapse(path)
  path = normalize(path)
  local entry = self.entries[path]
  if entry and entry.is_dir and self.expanded[path] then
    self.expanded[path] = nil
    return path
  end

  local parent = self.parents[path]
  if not parent or parent == self.root then
    return nil
  end

  self.expanded[parent] = nil
  return parent
end

local function set_metadata(entry, depth, expanded, has_children)
  entry._tree_depth = depth
  entry._tree_expanded = expanded
  entry._tree_has_children = has_children
end

---@param prompt string
---@return table[]
function Tree:project(prompt)
  prompt = prompt or ""
  local results = {}

  if prompt == "" then
    local function add_expanded(parent, depth)
      for _, entry in ipairs(self.children[parent] or {}) do
        local children = self.children[entry.path] or {}
        local expanded = entry.is_dir and self.expanded[entry.path] == true and #children > 0
        set_metadata(entry, depth, expanded, entry.is_dir and #children > 0)
        table.insert(results, entry)
        if expanded then
          add_expanded(entry.path, depth + 1)
        end
      end
    end

    add_expanded(self.root, 0)
    return results
  end

  local included = {}

  local function include_ancestors(path)
    while path and path ~= self.root do
      included[path] = true
      path = self.parents[path]
    end
  end

  local function include_subtree(path)
    included[path] = true
    for _, child in ipairs(self.children[path] or {}) do
      include_subtree(child.path)
    end
  end

  for path, entry in pairs(self.entries) do
    if fzy.has_match(prompt, entry.ordinal or path) then
      include_ancestors(path)
      if entry.is_dir then
        include_subtree(path)
      end
    end
  end

  local function add_search_results(parent, depth)
    for _, entry in ipairs(self.children[parent] or {}) do
      if included[entry.path] then
        local has_visible_children = false
        for _, child in ipairs(self.children[entry.path] or {}) do
          if included[child.path] then
            has_visible_children = true
            break
          end
        end
        set_metadata(
          entry,
          depth,
          entry.is_dir and has_visible_children,
          entry.is_dir and #(self.children[entry.path] or {}) > 0
        )
        table.insert(results, entry)
        if has_visible_children then
          add_search_results(entry.path, depth + 1)
        end
      end
    end
  end

  add_search_results(self.root, 0)
  return results
end

return Tree
