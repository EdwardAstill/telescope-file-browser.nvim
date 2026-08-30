local Path = require "plenary.path"

local actions = require "telescope.actions"
local action_set = require "telescope.actions.set"
local action_state = require "telescope.actions.state"

local root
local prompt_bufnr

local function find_prompt()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "TelescopePrompt" then
      return bufnr
    end
  end
end

describe("tree picker", function()
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(Path:new(root, "src"):absolute(), "p")
    vim.fn.writefile({ "return true" }, Path:new(root, "src", "child.lua"):absolute())
    vim.fn.writefile({ "project" }, Path:new(root, "README.md"):absolute())
  end)

  after_each(function()
    if prompt_bufnr and vim.api.nvim_buf_is_valid(prompt_bufnr) then
      pcall(actions.close, prompt_bufnr)
    end
    prompt_bufnr = nil
    vim.fn.delete(root, "rf")
  end)

  it("keeps a fixed root and exposes tree controls", function()
    local telescope = require "telescope"
    local custom_expand_called = false
    telescope.setup {
      extensions = {
        file_browser = {
          tree = true,
          grouped = true,
          hidden = true,
          use_fd = false,
          git_status = false,
          display_stat = false,
          mappings = {
            n = {
              l = function()
                custom_expand_called = true
              end,
            },
          },
        },
      },
    }
    telescope.load_extension "file_browser"
    telescope.extensions.file_browser.file_browser {
      path = root,
      cwd = root,
      previewer = false,
    }

    assert.is_true(vim.wait(1000, function()
      prompt_bufnr = find_prompt()
      if not prompt_bufnr then
        return false
      end
      local picker = action_state.get_current_picker(prompt_bufnr)
      return picker and picker.finder.tree_state and #picker.finder.results > 0
    end, 10))

    local picker = action_state.get_current_picker(prompt_bufnr)
    assert.are.same("normal", picker.initial_mode)
    assert.is_true(action_state.get_selected_entry().is_dir)

    action_set.select(prompt_bufnr, "default")

    assert.are.same(root, picker.finder.path)
    assert.is_true(vim.api.nvim_buf_is_valid(prompt_bufnr))

    local fb_actions = telescope.extensions.file_browser.actions
    assert.is_not_nil(fb_actions.expand)
    assert.is_not_nil(fb_actions.collapse)
    assert.is_not_nil(fb_actions.enter_search)
    assert.is_not_nil(fb_actions.normal_mode)

    local normal_maps = vim.api.nvim_buf_get_keymap(prompt_bufnr, "n")
    local mapped = {}
    for _, mapping in ipairs(normal_maps) do
      mapped[mapping.lhs] = mapping
    end
    assert.is_not_nil(mapped.i)
    assert.is_not_nil(mapped.k)
    assert.is_not_nil(mapped.j)
    assert.is_not_nil(mapped.l)
    assert.is_not_nil(mapped["/"])

    mapped.l.callback()
    assert.is_true(custom_expand_called)

    local src = Path:new(root, "src"):absolute()
    local child = Path:new(root, "src", "child.lua"):absolute()
    fb_actions.expand(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 3
    end, 10))
    assert.is_true(picker.finder.tree_state.expanded[src])
    assert.are.same(src, action_state.get_selected_entry().path)

    mapped.k.callback(prompt_bufnr)
    assert.are.same(child, action_state.get_selected_entry().path)
    mapped.i.callback(prompt_bufnr)
    assert.are.same(src, action_state.get_selected_entry().path)
    mapped.k.callback(prompt_bufnr)
    mapped.j.callback(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 2
    end, 10))
    assert.are.same(src, action_state.get_selected_entry().path)

    local missing = Path:new(root, "missing.lua")
    picker:reset_prompt "missing.lua"
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 0
    end, 10))
    action_set.select(prompt_bufnr, "default")
    assert.is_false(missing:exists())

    picker:reset_prompt ""
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 2
    end, 10))
    fb_actions.expand(prompt_bufnr)
    assert.is_true(vim.wait(1000, function()
      return #picker.finder.results == 3
    end, 10))
    mapped.k.callback(prompt_bufnr)
    assert.are.same(child, action_state.get_selected_entry().path)
    action_set.select(prompt_bufnr, "default")
    assert.is_true(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(prompt_bufnr)
    end, 10))
    assert.are.same(child, vim.api.nvim_buf_get_name(0))
  end)
end)
