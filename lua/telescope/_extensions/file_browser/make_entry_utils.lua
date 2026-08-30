local Path = require "plenary.path"
local fb_utils = require "telescope._extensions.file_browser.utils"

local os_sep = Path.path.sep
local os_sep_len = #os_sep

local M = {}

--- compute ordinal path
--- accounts for `auto_depth` option
---@param path string
---@param cwd string
---@param parent string
---@return string
M.get_ordinal_path = function(path, cwd, parent)
  path = fb_utils.sanitize_path_str(path)
  if path == cwd then
    return "."
  elseif path == parent then
    return ".."
  end

  local cwd_substr = #cwd + 1
  cwd_substr = cwd:sub(-1, -1) ~= os_sep and cwd_substr + os_sep_len or cwd_substr

  return path:sub(cwd_substr, -1)
end

---@param entry table
---@param opts table
---@return string prefix
---@return string basename
M.get_tree_display = function(entry, opts)
  local indent = string.rep(opts.tree_indent or "  ", entry._tree_depth or 0)
  local expanded = opts.tree_expanded or ""
  local collapsed = opts.tree_collapsed or ""
  local marker_width = math.max(vim.fn.strdisplaywidth(expanded), vim.fn.strdisplaywidth(collapsed))
  local marker

  if entry.is_dir and entry._tree_has_children ~= false then
    marker = entry._tree_expanded and expanded or collapsed
  else
    marker = string.rep(" ", marker_width)
  end

  return indent .. marker .. " ", vim.fs.basename(entry.path)
end

return M
