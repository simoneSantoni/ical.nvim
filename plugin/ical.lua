-- ical.nvim - Calendar events and tasks from local iCal files
-- This file is loaded automatically by Neovim

if vim.g.loaded_ical then
  return
end
vim.g.loaded_ical = true

-- Create user commands (setup is called lazily when commands are used)
local function ensure_setup()
  local ical = require("ical")
  if not ical._initialized then
    ical.setup()
  end
  return ical
end

-- View commands
vim.api.nvim_create_user_command("IcalAgenda", function()
  local ical = ensure_setup()
  ical.open_agenda()
end, {
  desc = "Open iCal agenda view",
})

vim.api.nvim_create_user_command("IcalAgendaRefresh", function()
  ensure_setup().refresh()
end, { desc = "Refresh iCal agenda" })

vim.api.nvim_create_user_command("IcalAgendaClose", function()
  require("ical.ui").close_window()
end, { desc = "Close iCal agenda" })

-- Calendar management commands
vim.api.nvim_create_user_command("IcalAddCalendar", function(opts)
  local args = opts.fargs
  local path = args[1]
  if not path then
    vim.notify("Usage: :IcalAddCalendar <path> [name] [--recursive]", vim.log.levels.ERROR)
    return
  end

  local name = nil
  local recursive = false

  for i = 2, #args do
    if args[i] == "--recursive" or args[i] == "-r" then
      recursive = true
    else
      name = args[i]
    end
  end

  ensure_setup().add_calendar({ path = path, name = name, recursive = recursive })
end, {
  desc = "Add a calendar source (path [name] [--recursive])",
  nargs = "+",
  complete = "file",
})

vim.api.nvim_create_user_command("IcalRemoveCalendar", function(opts)
  local name = opts.args
  if name == "" then
    vim.notify("Usage: :IcalRemoveCalendar <name>", vim.log.levels.ERROR)
    return
  end

  local ical = ensure_setup()
  local num = tonumber(name)
  if num then
    ical.remove_calendar(num)
  else
    ical.remove_calendar(name)
  end
end, {
  desc = "Remove a calendar source by name or index",
  nargs = 1,
  complete = function()
    local ical = require("ical")
    local names = {}
    for _, cal in ipairs(ical.config.calendars or {}) do
      table.insert(names, cal.name)
    end
    return names
  end,
})

vim.api.nvim_create_user_command("IcalListCalendars", function()
  ensure_setup().list_calendars()
end, { desc = "List configured calendar sources" })

-- Event/task creation commands
vim.api.nvim_create_user_command("IcalNewEvent", function()
  ensure_setup().new_event()
end, { desc = "Create a new calendar event" })

vim.api.nvim_create_user_command("IcalNewTask", function()
  ensure_setup().new_task()
end, { desc = "Create a new task/todo" })
