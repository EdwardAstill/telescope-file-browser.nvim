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
