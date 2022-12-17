local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local themes = require("telescope.themes")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local utils = require("telescope.utils")

-- main table with default options
local M = {
  -- Absolute path to file where colorscheme should be saved
  file_path = os.getenv("HOME") .. "/.nvim.colorscheme-persist.lua",
  -- In case there's no saved colorscheme yet
  fallback = "default",
  -- List of ugly colorschemes to avoid in the selection window
  disable = {
    "darkblue",
    "default",
    "delek",
    "desert",
    "elflord",
    "evening",
    "industry",
    "koehler",
    "morning",
    "murphy",
    "pablo",
    "peachpuff",
    "ron",
    "shine",
    "slate",
    "torte",
    "zellner"
  },
  -- Options for the telescope picker
  picker_opts = themes.get_dropdown(),
  enable_preview = false,
}

-- Get list with all colorschemes without disabled ones
local _get_colors = function(disable)
  disable = disable or {}
  local colors = {}
  local all_colors = vim.fn.getcompletion("", "color")
  for _, color in ipairs(all_colors) do
    local ignored = false
    for _, disabled_color in ipairs(disable) do
      if color == disabled_color then
        ignored = true
        break
      end
    end
    if not ignored then
      table.insert(colors, color)
    end
  end
  return colors
end

-- Save colorscheme to file
local _save_colorscheme = function(colorscheme)
  -- write lua code with colorscheme as a string
  -- so it can be be retrieved later by executing the file (dofile)
  vim.loop.fs_open(M.file_path, "w", 432, function(_, fd)
    local string_to_write = "return " .. "'" .. colorscheme .. "'"
    vim.loop.fs_write(fd, string_to_write, nil, function()
      vim.loop.fs_close(fd)
    end)
  end)
end

-- Set options
function M.setup(opts)
  -- override defaults with input options
  opts = opts or {}
  for k, v in pairs(opts) do
    M[k] = v
  end

  -- Set available colors for picker
  M.colorschemes = _get_colors(M.disable)
end

-- Get stored colorscheme
function M.get_colorscheme()
  local ok, colorscheme = pcall(dofile, M.file_path)
  if ok then
    return colorscheme
  else
    return M.fallback
  end
end

-- Open telescope picker to change and save colorscheme
function M.picker()
  local before_color = M.get_colorscheme()
  local need_restore = true
  local colors = M.colorschemes or { before_color }

  if not vim.tbl_contains(colors, before_color) then
    table.insert(colors, 1, before_color)
  end

  colors = vim.list_extend(
    { before_color },
    vim.tbl_filter(function(color)
      return color ~= before_color
    end, colors)
  )

  local previewer

  if M.enable_preview then
    local bufnr = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(bufnr)

    if not vim.fn.buflisted(bufnr) then
      -- don't need previewer for empty buffers
      local deleted = false
      local del_win = function(win_id)
        if win_id and vim.api.nvim_win_is_valid(win_id) then
          utils.buf_delete(vim.api.nvim_win_get_buf(win_id))
          pcall(vim.api.nvim_win_close, win_id, true)
        end
      end

      previewer = previewers.new {
        preview_fn = function(_, entry, status)
          if not deleted then
            deleted = true
            del_win(status.preview_win)
            del_win(status.preview_border_win)
          end
          vim.cmd("colorscheme" .. entry.value)
        end,
      }
    else
      -- show current buffer content in previewer
      previewer = previewers.new_buffer_previewer {
        get_buffer_by_name = function()
          return name
        end,
        define_preview = function(self, entry)
          if vim.loop.fs_stat(name) then
            conf.buffer_previewer_maker(name, self.state.bufnr, { bufname = self.state.bufname })
          else
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          end
          vim.cmd("colorscheme " .. entry.value)
        end,
      }
    end
  end

  local picker = pickers.new(M.picker_opts, {
    prompt_title = "colorschemes",
    finder = finders.new_table({ results = colors }),
    sorter = conf.generic_sorter(M.picker_opts),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        -- set selected colorscheme
        local selection = action_state.get_selected_entry()
        local colorscheme = ""
        if selection == nil then
          vim.notify("colorscheme-persist: Selection not valid")
          return
        else
          colorscheme = selection[1]
        end
        need_restore = false
        vim.cmd("colorscheme default") -- reset settings
        vim.cmd("colorscheme " .. colorscheme) -- change colorscheme
        -- save
        _save_colorscheme(colorscheme)
      end)
      return true
    end,
  })

  if M.enable_preview then
    local old_close_windows = picker.close_windows

    -- restore original colorscheme, if needed
    picker.close_windows = function(status)
      old_close_windows(status)
      if need_restore then
        vim.cmd("colorscheme " .. before_color)
      end
    end
  end

  picker:find()
end

return M
