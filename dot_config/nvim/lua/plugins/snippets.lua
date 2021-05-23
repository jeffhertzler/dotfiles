local M = {}

local loaded = false

function M.complete(key, dir)
  if require('luasnip').jumpable(dir) then
    require('luasnip').jump(dir)
  else
    require('helpers').feedkeys(key)
  end
end

function M.config()
  if not loaded then
    require('luasnip').config.set_config({ history = true })
    require('luasnip.loaders.from_vscode').load()
    loaded = true
  end
end

return M
