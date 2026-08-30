local Path = require "plenary.path"

local fb_finders = require "telescope._extensions.file_browser.finders"

local root

local function make_path(...)
  return Path:new(root, ...):absolute()
end

local function entry_maker(opts)
  return function(path)
    local stat = vim.uv.fs_stat(path)
    return {
      value = path,
      path = path,
      ordinal = Path:new(path):make_relative(opts.cwd),
      Path = Path:new(path),
      is_dir = stat and stat.type == "directory" or false,
    }
  end
end

local function collect(finder, prompt)
  local results = {}
  local completed = false
  finder(prompt, function(item)
    table.insert(results, Path:new(item.path):make_relative(root))
  end, function()
    completed = true
  end)
  assert.is_true(completed)
  return results
end

describe("tree finder", function()
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(make_path("src", "util"), "p")
    vim.fn.writefile({ "return true" }, make_path("src", "main.lua"))
    vim.fn.writefile({ "return {}" }, make_path("src", "util", "parser.lua"))
    vim.fn.writefile({ "project" }, make_path("README.md"))
  end)

  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  it("projects a recursive real-filesystem catalog", function()
    local finder = fb_finders.browse_tree {
      path = root,
      cwd = root,
      files = true,
      add_dirs = true,
      grouped = true,
      hidden = true,
      respect_gitignore = false,
      follow_symlinks = false,
      use_fd = false,
      git_status = false,
      entry_maker = entry_maker,
    }

    assert.are.same({ "src", "README.md" }, collect(finder, ""))

    assert.is_true(finder.tree_state:expand(make_path "src"))
    assert.are.same({ "src", "src/util", "src/main.lua", "README.md" }, collect(finder, ""))

    assert.are.same({ "src", "src/util", "src/util/parser.lua" }, collect(finder, "parser"))
  end)
end)
