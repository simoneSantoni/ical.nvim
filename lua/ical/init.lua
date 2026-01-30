-- ical.nvim - Display calendar events and tasks from local iCal files
local config_module = require("ical.config")
local parser = require("ical.parser")
local ui = require("ical.ui")
local utils = require("ical.utils")

local M = {}

-- Lazy load form module
local form = nil
local function get_form()
  if not form then
    form = require("ical.form")
  end
  return form
end

-- Plugin configuration
M.config = {}

-- Track initialization
M._initialized = false

--- Setup the plugin
---@param opts table|nil User configuration
function M.setup(opts)
  if M._initialized then
    -- Allow re-setup to update config
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    return
  end

  M.config = vim.tbl_deep_extend("force", config_module.defaults, opts or {})
  M._initialized = true

  -- Create highlight groups
  ui.create_highlights(M.config.highlights)

  -- Setup autocommands if configured
  if M.config.refresh.on_focus then
    vim.api.nvim_create_autocmd("FocusGained", {
      group = vim.api.nvim_create_augroup("Ical", { clear = true }),
      callback = function()
        if ui.is_open() then
          M.refresh()
        end
      end,
    })
  end
end

--- Load and parse all configured calendar files
---@return table[] events All events from all calendars
---@return table[] todos All tasks from all calendars
function M.load_calendars()
  local all_events = {}
  local all_todos = {}

  for _, cal in ipairs(M.config.calendars) do
    local events, todos = parser.parse_directory(cal.path, cal)

    for _, event in ipairs(events) do
      event.calendar_name = cal.name
      table.insert(all_events, event)
    end

    for _, todo in ipairs(todos) do
      todo.calendar_name = cal.name
      table.insert(all_todos, todo)
    end
  end

  return all_events, all_todos
end

--- Calculate the date range for the agenda view
---@return number start_date Start of range (timestamp)
---@return number end_date End of range (timestamp)
function M.get_date_range()
  local today = utils.start_of_day(os.time())
  local start_date

  if M.config.display.show_past_events then
    start_date = utils.add_days(today, -7)
  else
    start_date = today
  end

  local end_date = utils.add_days(start_date, M.config.display.days_ahead)
  return start_date, end_date
end

--- Expand recurring events within a date range
---@param events table[] Array of events
---@param start_date number Start of range (timestamp)
---@param end_date number End of range (timestamp)
---@return table[] Expanded events
function M.expand_events(events, start_date, end_date)
  local expanded = {}

  -- Try to load rrule module
  local ok, rrule = pcall(require, "ical.rrule")

  for _, event in ipairs(events) do
    if event.rrule and ok then
      -- Expand recurring event within range (recurrences need bounds)
      local instances = rrule.expand(event, start_date, end_date)
      for _, instance in ipairs(instances) do
        table.insert(expanded, instance)
      end
    else
      -- Non-recurring: include if today or future
      local today = utils.start_of_day(os.time())
      if event.dtstart >= today or (event.dtend and event.dtend >= today) then
        table.insert(expanded, event)
      end
    end
  end

  -- Sort by start time
  table.sort(expanded, function(a, b)
    return a.dtstart < b.dtstart
  end)

  return expanded
end

--- Filter tasks based on configuration
---@param todos table[] Array of tasks
---@return table[] Filtered tasks
function M.filter_tasks(todos)
  local filtered = {}

  for _, task in ipairs(todos) do
    local is_completed = task.status == "COMPLETED"

    if not is_completed or M.config.display.show_completed_tasks then
      table.insert(filtered, task)
    end
  end

  -- Sort by due date (nil due dates at the end), then by priority
  table.sort(filtered, function(a, b)
    -- Completed tasks at the bottom
    if (a.status == "COMPLETED") ~= (b.status == "COMPLETED") then
      return a.status ~= "COMPLETED"
    end

    -- Sort by due date
    if a.due and b.due then
      return a.due < b.due
    elseif a.due then
      return true
    elseif b.due then
      return false
    end

    -- Sort by priority (lower number = higher priority)
    if a.priority ~= b.priority then
      return a.priority < b.priority
    end

    return a.summary < b.summary
  end)

  return filtered
end

--- Navigate the agenda by weeks
---@param direction number 1 for next, -1 for previous
function M.navigate(direction)
  local view_date = ui.get_view_date()
  ui.set_view_date(utils.add_days(view_date, direction * 7))

  if ui.is_open() then
    M.refresh()
  end
end

--- Go to today
function M.goto_today()
  ui.set_view_date(utils.start_of_day(os.time()))
  if ui.is_open() then
    M.refresh()
  end
end

--- Open the agenda view
---@param opts table|nil Optional override options
function M.open_agenda(opts)
  opts = opts or {}

  -- Reset view date to today
  ui.set_view_date(utils.start_of_day(os.time()))

  M.refresh()
end

--- Refresh the agenda display
function M.refresh()
  local events, todos = M.load_calendars()

  -- Calculate date range
  local start_date, end_date = M.get_date_range()

  -- Expand recurring events
  local expanded_events = M.expand_events(events, start_date, end_date)

  -- Filter tasks
  local filtered_tasks = M.filter_tasks(todos)

  -- Open window if not already open
  if not ui.is_open() then
    ui.open_window(M.config.window)
    -- Set resize callback to refresh on window resize
    ui.set_resize_callback(function()
      M.refresh()
    end)
  end

  -- Render
  local display_opts = vim.tbl_extend("force", M.config.display, {
    width = M.config.window.width,
  })
  ui.render(expanded_events, filtered_tasks, display_opts, M.config.icons)

  -- Setup keymaps
  ui.setup_keymaps(M.config.keymaps, {
    close = function()
      ui.close_window()
    end,
    refresh = function()
      M.refresh()
    end,
    nav_next = function()
      M.navigate(1)
    end,
    nav_prev = function()
      M.navigate(-1)
    end,
    goto_today = function()
      M.goto_today()
    end,
    toggle_tasks = function()
      ui.toggle_tasks()
      M.refresh()
    end,
    open_calendar = function()
      ui.close_window()
      vim.cmd("Calendar")
    end,
    -- Create new items
    new_event = function()
      M.new_event()
    end,
    new_task = function()
      M.new_task()
    end,
    -- Edit item
    edit_item = function()
      M.edit_item()
    end,
    -- Complete task
    complete_task = function()
      M.complete_task()
    end,
    -- Delete item
    delete_item = function()
      M.delete_item()
    end,
  })
end

--- Add a calendar source at runtime
---@param opts table Calendar options { path, name?, color?, recursive? }
function M.add_calendar(opts)
  if not opts.path then
    vim.notify("ical: path is required", vim.log.levels.ERROR)
    return false
  end

  local path = vim.fn.expand(opts.path)

  -- Validate path exists
  if vim.fn.filereadable(path) ~= 1 and vim.fn.isdirectory(path) ~= 1 then
    vim.notify("ical: path not found: " .. path, vim.log.levels.ERROR)
    return false
  end

  -- Check for duplicates
  for _, cal in ipairs(M.config.calendars) do
    if vim.fn.expand(cal.path) == path then
      vim.notify("ical: calendar already added: " .. path, vim.log.levels.WARN)
      return false
    end
  end

  -- Generate name from path if not provided
  local name = opts.name or vim.fn.fnamemodify(path, ":t:r")

  -- Default colors cycle
  local colors = { "#87CEEB", "#FFD700", "#98FB98", "#DDA0DD", "#F0E68C", "#E6E6FA" }
  local color = opts.color or colors[(#M.config.calendars % #colors) + 1]

  local calendar = {
    path = opts.path, -- Keep original path for config
    name = name,
    color = color,
    recursive = opts.recursive or false,
  }

  table.insert(M.config.calendars, calendar)
  vim.notify("ical: added calendar '" .. name .. "' from " .. opts.path, vim.log.levels.INFO)

  -- Refresh if open
  if ui.is_open() then
    M.refresh()
  end

  return true
end

--- Remove a calendar source by name or index
---@param identifier string|number Calendar name or index
function M.remove_calendar(identifier)
  local index

  if type(identifier) == "number" then
    index = identifier
  else
    for i, cal in ipairs(M.config.calendars) do
      if cal.name == identifier then
        index = i
        break
      end
    end
  end

  if not index or not M.config.calendars[index] then
    vim.notify("ical: calendar not found: " .. tostring(identifier), vim.log.levels.ERROR)
    return false
  end

  local removed = table.remove(M.config.calendars, index)
  vim.notify("ical: removed calendar '" .. removed.name .. "'", vim.log.levels.INFO)

  if ui.is_open() then
    M.refresh()
  end

  return true
end

--- List all configured calendars
function M.list_calendars()
  if #M.config.calendars == 0 then
    vim.notify("ical: no calendars configured", vim.log.levels.INFO)
    return
  end

  local lines = { "Configured calendars:" }
  for i, cal in ipairs(M.config.calendars) do
    local path = vim.fn.expand(cal.path)
    local status = ""

    if vim.fn.filereadable(path) == 1 then
      status = "(file)"
    elseif vim.fn.isdirectory(path) == 1 then
      local count = #vim.fn.glob(path .. "/*.ics", false, true)
        + #vim.fn.glob(path .. "/*.ical", false, true)
      status = "(" .. count .. " files)"
      if cal.recursive then
        status = status .. " [recursive]"
      end
    else
      status = "(not found!)"
    end

    table.insert(lines, string.format("  %d. %s: %s %s", i, cal.name, cal.path, status))
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Get writable calendar path for a calendar name
---@param cal_name string Calendar name
---@return string|nil path Path to write to, or nil if not found
local function get_calendar_write_path(cal_name)
  for _, cal in ipairs(M.config.calendars) do
    if cal.name == cal_name then
      local path = vim.fn.expand(cal.path)

      -- If it's a directory, we'll create a new file inside
      if vim.fn.isdirectory(path) == 1 then
        return path
      end

      -- If it's a file, we need to append to it or use its directory
      if vim.fn.filereadable(path) == 1 then
        -- Return the directory containing the file
        return vim.fn.fnamemodify(path, ":h")
      end

      -- Path doesn't exist yet - check if parent exists
      local parent = vim.fn.fnamemodify(path, ":h")
      if vim.fn.isdirectory(parent) == 1 then
        return parent
      end

      return nil
    end
  end
  return nil
end

--- Generate a UUID v4
---@return string uuid
local function generate_uuid()
  local chars = "0123456789abcdef"
  local uuid = {}
  for i = 1, 32 do
    uuid[i] = chars:sub(math.random(1, 16), math.random(1, 16))
  end
  -- Format as 8-4-4-4-12
  return table.concat(uuid, "", 1, 8)
    .. "-" .. table.concat(uuid, "", 9, 12)
    .. "-4" .. table.concat(uuid, "", 14, 16)  -- Version 4
    .. "-" .. chars:sub(math.random(9, 12), math.random(9, 12)) .. table.concat(uuid, "", 18, 20)  -- Variant
    .. "-" .. table.concat(uuid, "", 21, 32)
end

--- Generate a filename for a new event/task
---@return string filename
local function generate_filename()
  return generate_uuid() .. ".ics"
end

--- Save content to an iCal file
---@param dir_path string Directory to save in
---@param filename string Filename
---@param content string iCal content
---@return boolean success
---@return string|nil error_message
local function save_ical_file(dir_path, filename, content)
  local full_path = dir_path .. "/" .. filename

  local file, err = io.open(full_path, "w")
  if not file then
    return false, "Failed to open file: " .. (err or "unknown error")
  end

  local ok, write_err = file:write(content)
  file:close()

  if not ok then
    return false, "Failed to write file: " .. (write_err or "unknown error")
  end

  return true, nil
end

--- Open the new event form
---@param opts table|nil Options { date?: string }
function M.new_event(opts)
  opts = opts or {}

  if #M.config.calendars == 0 then
    vim.notify("ical: no calendars configured. Use :IcalAddCalendar first.", vim.log.levels.ERROR)
    return
  end

  local form_module = get_form()

  form_module.open("event", M.config.calendars, function(data)
    -- Find the calendar path
    local write_path = get_calendar_write_path(data.calendar)
    if not write_path then
      vim.notify("ical: cannot write to calendar '" .. data.calendar .. "'", vim.log.levels.ERROR)
      return
    end

    -- Create the VEVENT content
    local content = form_module.create_vevent(data)

    -- Generate filename and save
    local filename = generate_filename()
    local ok, err = save_ical_file(write_path, filename, content)

    if ok then
      vim.notify("ical: created event '" .. data.summary .. "'", vim.log.levels.INFO)
      -- Refresh if agenda is open
      if ui.is_open() then
        M.refresh()
      end
    else
      vim.notify("ical: " .. err, vim.log.levels.ERROR)
    end
  end)
end

--- Open the new task form
---@param opts table|nil Options
function M.new_task(opts)
  opts = opts or {}

  if #M.config.calendars == 0 then
    vim.notify("ical: no calendars configured. Use :IcalAddCalendar first.", vim.log.levels.ERROR)
    return
  end

  local form_module = get_form()

  form_module.open("task", M.config.calendars, function(data)
    -- Find the calendar path
    local write_path = get_calendar_write_path(data.calendar)
    if not write_path then
      vim.notify("ical: cannot write to calendar '" .. data.calendar .. "'", vim.log.levels.ERROR)
      return
    end

    -- Create the VTODO content
    local content = form_module.create_vtodo(data)

    -- Generate filename and save
    local filename = generate_filename()
    local ok, err = save_ical_file(write_path, filename, content)

    if ok then
      vim.notify("ical: created task '" .. data.summary .. "'", vim.log.levels.INFO)
      -- Refresh if agenda is open
      if ui.is_open() then
        M.refresh()
      end
    else
      vim.notify("ical: " .. err, vim.log.levels.ERROR)
    end
  end)
end

--- Edit event/task at cursor — opens an editable form, saves back to .ics file
function M.edit_item()
  local item, item_type = ui.get_item_at_cursor()
  if not item then
    return
  end

  local form_module = get_form()

  if item_type == "event" then
    local data = {
      summary = item.summary or "",
      date = item.dtstart and os.date("%Y-%m-%d", item.dtstart) or "",
      start_time = item.all_day and "" or (item.dtstart and os.date("%H:%M", item.dtstart) or ""),
      end_time = item.all_day and "" or (item.dtend and os.date("%H:%M", item.dtend) or ""),
      location = item.location or "",
      description = item.description or "",
      calendar = item.calendar_name or "",
    }

    form_module.open_edit("event", data, M.config.calendars, function(updated)
      -- Write the updated event back to the source file
      local source_file = item.source_file
      if not source_file then
        vim.notify("ical: cannot find source file for this event", vim.log.levels.ERROR)
        return
      end

      local content = form_module.create_vevent(updated)
      local file, err = io.open(source_file, "w")
      if not file then
        vim.notify("ical: failed to save: " .. (err or "unknown"), vim.log.levels.ERROR)
        return
      end
      file:write(content)
      file:close()

      vim.notify("ical: updated event '" .. updated.summary .. "'", vim.log.levels.INFO)
      if ui.is_open() then
        M.refresh()
      end
    end)
  else
    local data = {
      summary = item.summary or "",
      due_date = item.due and os.date("%Y-%m-%d", item.due) or "",
      due_time = item.due and os.date("%H:%M", item.due) or "",
      priority = item.priority and tostring(item.priority) or "0",
      description = item.description or "",
      tags = item.categories and table.concat(item.categories, ", ") or "",
      calendar = item.calendar_name or "",
      status = form_module.ical_to_display_status(item.status or "NEEDS-ACTION"),
    }

    form_module.open_edit("task", data, M.config.calendars, function(updated)
      -- Write the updated task back to the source file
      local source_file = item.source_file
      if not source_file then
        vim.notify("ical: cannot find source file for this task", vim.log.levels.ERROR)
        return
      end

      local content = form_module.create_vtodo(updated)
      local file, err = io.open(source_file, "w")
      if not file then
        vim.notify("ical: failed to save: " .. (err or "unknown"), vim.log.levels.ERROR)
        return
      end
      file:write(content)
      file:close()

      vim.notify("ical: updated task '" .. updated.summary .. "'", vim.log.levels.INFO)
      if ui.is_open() then
        M.refresh()
      end
    end)
  end
end

--- Delete event/task at cursor (with confirmation)
function M.delete_item()
  local item, item_type = ui.get_item_at_cursor()
  if not item then
    vim.notify("ical: no item under cursor", vim.log.levels.WARN)
    return
  end

  local source_file = item.source_file
  if not source_file or vim.fn.filereadable(source_file) ~= 1 then
    vim.notify("ical: cannot find source file for this item", vim.log.levels.ERROR)
    return
  end

  local label = item_type == "event" and "event" or "task"
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Delete " .. label .. " '" .. item.summary .. "'?",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end

    local ok, err = os.remove(source_file)
    if not ok then
      vim.notify("ical: failed to delete: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end

    vim.notify("ical: deleted " .. label .. " '" .. item.summary .. "'", vim.log.levels.INFO)
    if ui.is_open() then
      M.refresh()
    end
  end)
end

--- Mark task at cursor as completed
function M.complete_task()
  local item, item_type = ui.get_item_at_cursor()
  if not item or item_type ~= "task" then
    vim.notify("ical: no task under cursor", vim.log.levels.WARN)
    return
  end

  if item.status == "COMPLETED" then
    vim.notify("ical: task already completed", vim.log.levels.INFO)
    return
  end

  local source_file = item.source_file
  if not source_file or vim.fn.filereadable(source_file) ~= 1 then
    vim.notify("ical: cannot find task source file", vim.log.levels.ERROR)
    return
  end

  if M.config.display.delete_completed_tasks then
    -- Delete the task file
    local ok, err = os.remove(source_file)
    if not ok then
      vim.notify("ical: failed to delete task: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    vim.notify("ical: completed and removed '" .. item.summary .. "'", vim.log.levels.INFO)
  else
    -- Update STATUS in the file
    local content = utils.read_file(source_file)
    if not content then
      vim.notify("ical: cannot read task file", vim.log.levels.ERROR)
      return
    end

    -- Update STATUS line
    content = content:gsub("STATUS:[^\r\n]+", "STATUS:COMPLETED")

    -- Add COMPLETED timestamp if not present
    local completed_ts = os.date("!%Y%m%dT%H%M%SZ")
    if not content:match("COMPLETED:") then
      content = content:gsub("(STATUS:COMPLETED)", "%1\r\nCOMPLETED:" .. completed_ts)
    end

    -- Write back
    local file = io.open(source_file, "w")
    if not file then
      vim.notify("ical: cannot write task file", vim.log.levels.ERROR)
      return
    end
    file:write(content)
    file:close()
    vim.notify("ical: marked '" .. item.summary .. "' as completed", vim.log.levels.INFO)
  end

  -- Refresh to update the view
  M.refresh()
end

return M
