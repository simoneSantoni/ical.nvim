-- Tab-based UI for ical with multiple view modes
local utils = require("ical.utils")

local M = {}

-- View modes
M.VIEW_MODES = {
  AGENDA = "agenda",
  DAILY = "daily",
  WEEKLY = "weekly",
  MONTHLY = "monthly",
  YEARLY = "yearly",
}

-- UI state
local state = {
  main_buf = nil,
  main_win = nil,
  tasks_buf = nil,
  tasks_win = nil,
  tab = nil,
  events = {},
  tasks = {},
  show_tasks = true,
  view_mode = M.VIEW_MODES.AGENDA,
  -- Current view date (center of the view)
  view_date = nil,
  -- Width of tasks sidebar (default, can be resized)
  tasks_width = 45,
  -- Callback for window resize
  on_resize_callback = nil,
  -- Line to item mapping for main buffer (line_num -> {type="event"|"task", item=...})
  line_items = {},
  -- Line to item mapping for tasks buffer
  tasks_line_items = {},
}

--- Check if window is open
---@return boolean
function M.is_open()
  return state.main_win ~= nil and vim.api.nvim_win_is_valid(state.main_win)
end

--- Get current view mode
---@return string
function M.get_view_mode()
  return state.view_mode
end

--- Set view mode
---@param mode string One of VIEW_MODES
function M.set_view_mode(mode)
  state.view_mode = mode
end

--- Toggle task visibility
function M.toggle_tasks()
  state.show_tasks = not state.show_tasks
end

--- Get current task visibility
---@return boolean
function M.get_show_tasks()
  return state.show_tasks
end

--- Get view date
---@return number timestamp
function M.get_view_date()
  return state.view_date or os.time()
end

--- Set view date
---@param timestamp number
function M.set_view_date(timestamp)
  state.view_date = timestamp
end

--- Set callback for window resize
---@param callback function
function M.set_resize_callback(callback)
  state.on_resize_callback = callback
end

--- Get item at current cursor position
---@return table|nil item The event or task at cursor, or nil
---@return string|nil type "event" or "task"
function M.get_item_at_cursor()
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line_num = cursor[1]

  -- Check if in tasks buffer
  if win == state.tasks_win and state.tasks_line_items[line_num] then
    local item_info = state.tasks_line_items[line_num]
    return item_info.item, item_info.type
  end

  -- Check if in main buffer
  if win == state.main_win and state.line_items[line_num] then
    local item_info = state.line_items[line_num]
    return item_info.item, item_info.type
  end

  return nil, nil
end

--- Create the tab-based UI
---@param opts table Window options
function M.open_window(opts)
  -- Close existing if open
  M.close_window()

  -- Initialize view date to today if not set
  if not state.view_date then
    state.view_date = utils.start_of_day(os.time())
  end

  -- Create new tab
  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()

  -- Create main buffer
  state.main_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.main_buf].buftype = "nofile"
  vim.bo[state.main_buf].bufhidden = "wipe"
  vim.bo[state.main_buf].swapfile = false
  vim.bo[state.main_buf].filetype = "ical"

  -- Set the buffer in current window
  state.main_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.main_win, state.main_buf)

  -- Window settings
  vim.wo[state.main_win].wrap = false
  vim.wo[state.main_win].cursorline = true
  vim.wo[state.main_win].number = false
  vim.wo[state.main_win].relativenumber = false
  vim.wo[state.main_win].signcolumn = "no"
  vim.wo[state.main_win].foldcolumn = "0"
  vim.wo[state.main_win].list = false

  -- Set tab label
  vim.api.nvim_buf_set_name(state.main_buf, "iCal Agenda")

  -- Create tasks sidebar if enabled
  if state.show_tasks then
    M.open_tasks_sidebar()
  end

  -- Setup resize handler to re-render on window resize
  local augroup = vim.api.nvim_create_augroup("IcalResize", { clear = true })
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
      if M.is_open() then
        -- Schedule to avoid issues during resize
        vim.schedule(function()
          if state.on_resize_callback then
            state.on_resize_callback()
          end
        end)
      end
    end,
  })

  return state.main_buf, state.main_win
end

--- Open or refresh tasks sidebar
function M.open_tasks_sidebar()
  if state.tasks_win and vim.api.nvim_win_is_valid(state.tasks_win) then
    return state.tasks_buf, state.tasks_win
  end

  -- Create tasks buffer
  state.tasks_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.tasks_buf].buftype = "nofile"
  vim.bo[state.tasks_buf].bufhidden = "wipe"
  vim.bo[state.tasks_buf].swapfile = false
  vim.bo[state.tasks_buf].filetype = "ical-tasks"

  -- Create vertical split on the right
  vim.cmd("vsplit")
  vim.cmd("wincmd L")
  state.tasks_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.tasks_win, state.tasks_buf)
  vim.api.nvim_win_set_width(state.tasks_win, state.tasks_width)

  -- Window settings
  vim.wo[state.tasks_win].wrap = true
  vim.wo[state.tasks_win].cursorline = true
  vim.wo[state.tasks_win].number = false
  vim.wo[state.tasks_win].relativenumber = false
  vim.wo[state.tasks_win].signcolumn = "no"
  vim.wo[state.tasks_win].winfixwidth = true
  vim.wo[state.tasks_win].list = false

  -- Go back to main window
  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    vim.api.nvim_set_current_win(state.main_win)
  end

  return state.tasks_buf, state.tasks_win
end

--- Close tasks sidebar
function M.close_tasks_sidebar()
  if state.tasks_win and vim.api.nvim_win_is_valid(state.tasks_win) then
    vim.api.nvim_win_close(state.tasks_win, true)
  end
  state.tasks_win = nil
  state.tasks_buf = nil
end

--- Close the agenda window
function M.close_window()
  M.close_tasks_sidebar()
  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    -- Close the tab
    local current_tab = vim.api.nvim_get_current_tabpage()
    if state.tab and state.tab == current_tab then
      -- Only close if there are other tabs
      if #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd("tabclose")
      else
        vim.api.nvim_win_close(state.main_win, true)
      end
    else
      vim.api.nvim_win_close(state.main_win, true)
    end
  end
  state.main_win = nil
  state.main_buf = nil
  state.tab = nil
end

--- Generate header line with view mode indicators
---@param view_mode string Current view mode
---@param view_date number Current view date timestamp
---@param width number Available width
---@return string header line
---@return table highlights Array of {col_start, col_end, hl_group}
local function generate_header(view_mode, view_date, width)
  local modes = { "Agenda", "Daily", "Weekly", "Monthly", "Yearly" }
  local mode_keys = { "a", "d", "w", "m", "y" }
  local current_mode_idx = ({
    [M.VIEW_MODES.AGENDA] = 1,
    [M.VIEW_MODES.DAILY] = 2,
    [M.VIEW_MODES.WEEKLY] = 3,
    [M.VIEW_MODES.MONTHLY] = 4,
    [M.VIEW_MODES.YEARLY] = 5,
  })[view_mode] or 1

  local parts = {}
  local highlights = {}
  local col = 0

  for i, mode in ipairs(modes) do
    local label = "[" .. mode_keys[i] .. "]" .. mode
    if i == current_mode_idx then
      table.insert(highlights, { col, col + #label, "IcalAgendaActiveMode" })
    else
      table.insert(highlights, { col, col + #label, "IcalAgendaMode" })
    end
    table.insert(parts, label)
    col = col + #label + 2
  end

  local mode_str = table.concat(parts, "  ")

  -- Date indicator on the right
  local date_str = os.date("%B %Y", view_date)
  local padding = width - #mode_str - #date_str - 2
  if padding < 2 then
    padding = 2
  end

  local header = mode_str .. string.rep(" ", padding) .. date_str
  table.insert(highlights, { #mode_str + padding, #header, "IcalAgendaDateHeader" })

  return header, highlights
end

--- Generate agenda view (list of upcoming events)
---@param events table[] Sorted events
---@param opts table Display options
---@param icons table Icon configuration
---@param width number Available width
---@return string[] lines
---@return table[] highlights
---@return table line_items Line to item mapping
local function render_agenda_view(events, opts, icons, width)
  local lines = {}
  local highlights = {}
  local line_items = {}

  if #events == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No upcoming events")
    return lines, highlights, line_items
  end

  local current_date = nil

  for _, event in ipairs(events) do
    local event_date = os.date("%Y-%m-%d", event.dtstart)

    -- Date header when date changes
    if opts.group_by_date and event_date ~= current_date then
      current_date = event_date
      table.insert(lines, "")

      local date_str = os.date(opts.date_format, event.dtstart)
      if utils.is_today(event.dtstart) then
        date_str = date_str .. " (Today)"
      end

      local line_num = #lines + 1
      table.insert(lines, date_str)
      table.insert(highlights, { line_num, 0, #date_str, "IcalAgendaDateHeader" })
    end

    -- Event line
    local time_str
    if event.all_day then
      time_str = icons.all_day .. " All day"
    else
      time_str = os.date(opts.time_format, event.dtstart)
    end

    local prefix = event.is_recurring and (icons.recurring .. " ") or "  "
    local event_line = prefix .. time_str .. "  " .. event.summary

    if event.location and event.location ~= "" then
      event_line = event_line .. " " .. icons.location .. " " .. event.location
    end

    -- Truncate if too long
    local max_width = width - 2
    if vim.fn.strdisplaywidth(event_line) > max_width then
      event_line = vim.fn.strcharpart(event_line, 0, max_width - 3) .. "..."
    end

    local line_num = #lines + 1
    table.insert(lines, event_line)
    line_items[line_num] = { type = "event", item = event }

    local time_end = #prefix + #time_str
    table.insert(highlights, { line_num, #prefix, time_end, "IcalAgendaEventTime" })
  end

  return lines, highlights, line_items
end

--- Generate daily view
---@param events table[] Events for the day
---@param view_date number Date timestamp
---@param opts table Display options
---@param icons table Icon configuration
---@param width number Available width
---@return string[] lines
---@return table[] highlights
---@return table line_items
local function render_daily_view(events, view_date, opts, icons, width)
  local lines = {}
  local highlights = {}
  local line_items = {}

  -- Day header
  local day_header = os.date("%A, %B %d, %Y", view_date)
  if utils.is_today(view_date) then
    day_header = day_header .. " (Today)"
  end
  table.insert(lines, day_header)
  table.insert(highlights, { 1, 0, #day_header, "IcalAgendaDateHeader" })
  table.insert(lines, string.rep("─", math.min(#day_header + 10, width)))
  table.insert(lines, "")

  -- Filter events for this specific day
  local day_start = utils.start_of_day(view_date)
  local day_end = utils.end_of_day(view_date)
  local day_events = {}

  for _, event in ipairs(events) do
    if event.dtstart <= day_end and event.dtend >= day_start then
      table.insert(day_events, event)
    end
  end

  if #day_events == 0 then
    table.insert(lines, "  No events scheduled")
    return lines, highlights, line_items
  end

  -- Hour-by-hour timeline
  local all_day_events = {}
  local timed_events = {}

  for _, event in ipairs(day_events) do
    if event.all_day then
      table.insert(all_day_events, event)
    else
      table.insert(timed_events, event)
    end
  end

  -- All-day events first
  if #all_day_events > 0 then
    table.insert(lines, "All Day:")
    table.insert(highlights, { #lines, 0, 8, "IcalAgendaEventTime" })
    for _, event in ipairs(all_day_events) do
      local line = "  " .. icons.all_day .. " " .. event.summary
      local line_num = #lines + 1
      table.insert(lines, line)
      line_items[line_num] = { type = "event", item = event }
    end
    table.insert(lines, "")
  end

  -- Timed events by hour
  if #timed_events > 0 then
    table.sort(timed_events, function(a, b)
      return a.dtstart < b.dtstart
    end)

    for _, event in ipairs(timed_events) do
      local time_str = os.date(opts.time_format, event.dtstart)
      local end_time_str = os.date(opts.time_format, event.dtend)
      local prefix = event.is_recurring and (icons.recurring .. " ") or "  "
      local line = prefix .. time_str .. " - " .. end_time_str .. "  " .. event.summary

      if event.location and event.location ~= "" then
        line = line .. " " .. icons.location .. " " .. event.location
      end

      local max_width = width - 2
      if vim.fn.strdisplaywidth(line) > max_width then
        line = vim.fn.strcharpart(line, 0, max_width - 3) .. "..."
      end

      local line_num = #lines + 1
      table.insert(lines, line)
      line_items[line_num] = { type = "event", item = event }
      table.insert(highlights, { line_num, #prefix, #prefix + #time_str + 3 + #end_time_str, "IcalAgendaEventTime" })
    end
  end

  return lines, highlights, line_items
end

--- Generate weekly view (7-day grid)
---@param events table[] Events for the week
---@param view_date number Date timestamp (any day in the week)
---@param opts table Display options
---@param icons table Icon configuration
---@param width number Available width
---@return string[] lines
---@return table[] highlights
---@return table line_items
local function render_weekly_view(events, view_date, opts, icons, width)
  local lines = {}
  local highlights = {}
  local line_items = {}

  -- Find start of week (Monday)
  local dow = utils.day_of_week(view_date)
  local week_start = utils.add_days(utils.start_of_day(view_date), 1 - dow)

  -- Week header
  local week_end = utils.add_days(week_start, 6)
  local header = os.date("%b %d", week_start) .. " - " .. os.date("%b %d, %Y", week_end)
  table.insert(lines, header)
  table.insert(highlights, { 1, 0, #header, "IcalAgendaDateHeader" })
  table.insert(lines, string.rep("─", width - 2))

  -- Each day of the week
  local day_names = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

  for i = 0, 6 do
    local day_date = utils.add_days(week_start, i)
    local day_start = utils.start_of_day(day_date)
    local day_end = utils.end_of_day(day_date)

    -- Day header
    table.insert(lines, "")
    local day_header = day_names[i + 1] .. " " .. os.date("%d", day_date)
    if utils.is_today(day_date) then
      day_header = day_header .. " (Today)"
    end

    local line_num = #lines + 1
    table.insert(lines, day_header)

    if utils.is_today(day_date) then
      table.insert(highlights, { line_num, 0, #day_header, "IcalAgendaToday" })
    else
      table.insert(highlights, { line_num, 0, #day_header, "IcalAgendaDateHeader" })
    end

    -- Filter events for this day
    local day_events = {}
    for _, event in ipairs(events) do
      if event.dtstart <= day_end and event.dtend >= day_start then
        table.insert(day_events, event)
      end
    end

    if #day_events == 0 then
      table.insert(lines, "    (no events)")
      table.insert(highlights, { #lines, 0, 15, "Comment" })
    else
      for _, event in ipairs(day_events) do
        local time_str
        if event.all_day then
          time_str = icons.all_day
        else
          time_str = os.date(opts.time_format, event.dtstart)
        end

        local line = "    " .. time_str .. " " .. event.summary
        local max_width = width - 4
        if vim.fn.strdisplaywidth(line) > max_width then
          line = vim.fn.strcharpart(line, 0, max_width - 3) .. "..."
        end

        local event_line_num = #lines + 1
        table.insert(lines, line)
        line_items[event_line_num] = { type = "event", item = event }
        table.insert(highlights, { event_line_num, 4, 4 + #time_str, "IcalAgendaEventTime" })
      end
    end
  end

  return lines, highlights, line_items
end

--- Generate monthly view (calendar grid)
---@param events table[] Events for the month
---@param view_date number Date timestamp (any day in the month)
---@param opts table Display options
---@param icons table Icon configuration
---@param width number Available width
---@return string[] lines
---@return table[] highlights
---@return table line_items
local function render_monthly_view(events, view_date, opts, icons, width)
  local lines = {}
  local highlights = {}
  local line_items = {}

  local date_parts = os.date("*t", view_date)
  local year = date_parts.year
  local month = date_parts.month

  -- Month header
  local month_header = os.date("%B %Y", view_date)
  table.insert(lines, month_header)
  table.insert(highlights, { 1, 0, #month_header, "IcalAgendaDateHeader" })
  table.insert(lines, "")

  -- Day name headers
  local day_width = math.floor((width - 2) / 7)
  if day_width < 4 then
    day_width = 4
  end
  local day_names = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
  local header_line = ""
  for _, name in ipairs(day_names) do
    header_line = header_line .. string.format("%-" .. day_width .. "s", name)
  end
  table.insert(lines, header_line)
  table.insert(highlights, { #lines, 0, #header_line, "IcalAgendaDateHeader" })
  table.insert(lines, string.rep("─", #header_line))

  -- First day of month
  local first_day = os.time({ year = year, month = month, day = 1 })
  local first_dow = utils.day_of_week(first_day)

  -- Last day of month
  local last_day = os.time({ year = year, month = month + 1, day = 0 })
  local last_date = os.date("*t", last_day).day

  -- Build event lookup by day
  local events_by_day = {}
  for _, event in ipairs(events) do
    local event_date = os.date("*t", event.dtstart)
    if event_date.year == year and event_date.month == month then
      local day = event_date.day
      if not events_by_day[day] then
        events_by_day[day] = {}
      end
      table.insert(events_by_day[day], event)
    end
  end

  -- Build calendar grid
  local current_day = 1
  local today = os.date("*t", os.time())
  local is_current_month = today.year == year and today.month == month

  while current_day <= last_date do
    local week_line = ""
    local week_events_line = ""

    for dow = 1, 7 do
      local cell = ""
      local event_indicator = ""

      if current_day == 1 and dow < first_dow then
        cell = string.rep(" ", day_width)
        event_indicator = string.rep(" ", day_width)
      elseif current_day > last_date then
        cell = string.rep(" ", day_width)
        event_indicator = string.rep(" ", day_width)
      else
        local day_str = string.format("%2d", current_day)
        local event_count = events_by_day[current_day] and #events_by_day[current_day] or 0

        if event_count > 0 then
          day_str = day_str .. "*"
          event_indicator = string.format("%-" .. day_width .. "s", "[" .. event_count .. "]")
        else
          event_indicator = string.rep(" ", day_width)
        end

        cell = string.format("%-" .. day_width .. "s", day_str)

        -- Highlight today
        if is_current_month and current_day == today.day then
          local col_start = #week_line
          local line_num = #lines + 1
          table.insert(highlights, { line_num, col_start, col_start + #cell, "IcalAgendaToday" })
        end

        current_day = current_day + 1
      end

      week_line = week_line .. cell
      week_events_line = week_events_line .. event_indicator
    end

    table.insert(lines, week_line)
    if week_events_line:match("%S") then
      table.insert(lines, week_events_line)
      table.insert(highlights, { #lines, 0, #week_events_line, "Comment" })
    end
  end

  -- Show events for selected day or today
  table.insert(lines, "")
  table.insert(lines, string.rep("─", width - 2))

  local selected_day = is_current_month and today.day or 1
  local selected_events = events_by_day[selected_day] or {}

  local events_header = "Events for " .. os.date("%b %d", os.time({ year = year, month = month, day = selected_day }))
  table.insert(lines, events_header)
  table.insert(highlights, { #lines, 0, #events_header, "IcalAgendaDateHeader" })

  if #selected_events == 0 then
    table.insert(lines, "  (no events)")
  else
    for _, event in ipairs(selected_events) do
      local time_str = event.all_day and (icons.all_day .. " All day")
        or os.date(opts.time_format, event.dtstart)
      local line = "  " .. time_str .. " " .. event.summary
      local event_line_num = #lines + 1
      table.insert(lines, line)
      line_items[event_line_num] = { type = "event", item = event }
      table.insert(highlights, { event_line_num, 2, 2 + #time_str, "IcalAgendaEventTime" })
    end
  end

  return lines, highlights, line_items
end

--- Generate yearly view (12-month overview)
---@param events table[] Events for the year
---@param view_date number Date timestamp (any day in the year)
---@param opts table Display options
---@param icons table Icon configuration
---@param width number Available width
---@return string[] lines
---@return table[] highlights
---@return table line_items
local function render_yearly_view(events, view_date, opts, icons, width)
  local lines = {}
  local highlights = {}
  local line_items = {}  -- Yearly view doesn't show individual events

  local year = os.date("*t", view_date).year

  -- Year header
  local header = tostring(year)
  table.insert(lines, header)
  table.insert(highlights, { 1, 0, #header, "IcalAgendaDateHeader" })
  table.insert(lines, "")

  -- Build event count by month
  local events_by_month = {}
  for i = 1, 12 do
    events_by_month[i] = 0
  end

  for _, event in ipairs(events) do
    local event_date = os.date("*t", event.dtstart)
    if event_date.year == year then
      events_by_month[event_date.month] = events_by_month[event_date.month] + 1
    end
  end

  local month_names = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  local today = os.date("*t", os.time())

  -- Display months in 3x4 grid
  local col_width = math.floor(width / 4)
  if col_width < 12 then
    col_width = 12
  end

  for row = 0, 2 do
    local month_line = ""
    local count_line = ""

    for col = 0, 3 do
      local month_idx = row * 4 + col + 1
      local month_name = month_names[month_idx]
      local event_count = events_by_month[month_idx]

      local count_str = event_count > 0 and (event_count .. " events") or "(empty)"
      month_line = month_line .. string.format("%-" .. col_width .. "s", month_name)
      count_line = count_line .. string.format("%-" .. col_width .. "s", "  " .. count_str)

      -- Highlight current month
      if today.year == year and today.month == month_idx then
        local col_start = col * col_width
        table.insert(highlights, { #lines + 1, col_start, col_start + #month_name, "IcalAgendaToday" })
      end
    end

    table.insert(lines, month_line)
    table.insert(lines, count_line)
    table.insert(highlights, { #lines, 0, #count_line, "Comment" })
    table.insert(lines, "")
  end

  return lines, highlights, line_items
end

--- Render tasks into the sidebar buffer
---@param tasks table[] Array of tasks
---@param opts table Display options
---@param icons table Icon configuration
function M.render_tasks(tasks, opts, icons)
  if not state.tasks_buf or not vim.api.nvim_buf_is_valid(state.tasks_buf) then
    return
  end

  -- Update tasks_width from actual window width (handles resize)
  if state.tasks_win and vim.api.nvim_win_is_valid(state.tasks_win) then
    state.tasks_width = vim.api.nvim_win_get_width(state.tasks_win)
  end

  local lines = {}
  local highlights = {}
  local now = os.time()
  local separator = " " .. string.rep("─", state.tasks_width - 3)

  -- Reset tasks line items mapping
  state.tasks_line_items = {}

  -- Group tasks by date (declared early to avoid goto scope issues)
  local overdue_tasks = {}
  local today_tasks = {}
  local upcoming_tasks = {}
  local no_date_tasks = {}

  local today_start = utils.start_of_day(now)
  local today_end = utils.end_of_day(now)

  -- Header
  table.insert(lines, " Tasks")
  table.insert(highlights, { 1, 0, 6, "IcalAgendaTitle" })
  table.insert(lines, separator)
  table.insert(lines, "")

  if #tasks == 0 then
    table.insert(lines, " No tasks")
    goto write_buffer
  end

  for _, task in ipairs(tasks) do
    if task.status == "COMPLETED" and not opts.show_completed_tasks then
      goto continue
    end

    if not task.due then
      table.insert(no_date_tasks, task)
    elseif task.due < today_start and task.status ~= "COMPLETED" then
      table.insert(overdue_tasks, task)
    elseif task.due >= today_start and task.due <= today_end then
      table.insert(today_tasks, task)
    else
      table.insert(upcoming_tasks, task)
    end

    ::continue::
  end

  -- Overdue section
  if #overdue_tasks > 0 then
    table.insert(lines, " Overdue")
    table.insert(highlights, { #lines, 0, 8, "IcalAgendaOverdue" })

    for _, task in ipairs(overdue_tasks) do
      local checkbox = task.status == "COMPLETED" and icons.task_done or icons.task
      local line = "  " .. checkbox .. " " .. task.summary
      if task.due then
        line = line .. " (" .. os.date(opts.date_format, task.due) .. ")"
      end
      if vim.fn.strdisplaywidth(line) > state.tasks_width - 2 then
        line = vim.fn.strcharpart(line, 0, state.tasks_width - 5) .. "..."
      end
      local task_line_num = #lines + 1
      table.insert(lines, line)
      state.tasks_line_items[task_line_num] = { type = "task", item = task }
      table.insert(highlights, { task_line_num, 0, #line, "IcalAgendaOverdue" })
    end
    table.insert(lines, "")
  end

  -- Today section
  if #today_tasks > 0 then
    table.insert(lines, " Today")
    table.insert(highlights, { #lines, 0, 6, "IcalAgendaToday" })

    for _, task in ipairs(today_tasks) do
      local checkbox = task.status == "COMPLETED" and icons.task_done or icons.task
      local line = "  " .. checkbox .. " " .. task.summary
      if vim.fn.strdisplaywidth(line) > state.tasks_width - 2 then
        line = vim.fn.strcharpart(line, 0, state.tasks_width - 5) .. "..."
      end
      local task_line_num = #lines + 1
      table.insert(lines, line)
      state.tasks_line_items[task_line_num] = { type = "task", item = task }
      local hl = task.status == "COMPLETED" and "IcalAgendaTaskCompleted" or "IcalAgendaTaskPending"
      table.insert(highlights, { task_line_num, 0, #line, hl })
    end
    table.insert(lines, "")
  end

  -- Upcoming section
  if #upcoming_tasks > 0 then
    table.insert(lines, " Upcoming")
    table.insert(highlights, { #lines, 0, 9, "IcalAgendaDateHeader" })

    -- Group by date
    local by_date = {}
    for _, task in ipairs(upcoming_tasks) do
      local date_key = os.date("%Y-%m-%d", task.due)
      if not by_date[date_key] then
        by_date[date_key] = { date = task.due, tasks = {} }
      end
      table.insert(by_date[date_key].tasks, task)
    end

    -- Sort dates
    local sorted_dates = {}
    for k, v in pairs(by_date) do
      table.insert(sorted_dates, { key = k, data = v })
    end
    table.sort(sorted_dates, function(a, b)
      return a.data.date < b.data.date
    end)

    for _, date_entry in ipairs(sorted_dates) do
      local date_label = os.date(opts.date_format, date_entry.data.date)
      table.insert(lines, " " .. date_label)
      table.insert(highlights, { #lines, 0, #date_label + 1, "Comment" })

      for _, task in ipairs(date_entry.data.tasks) do
        local checkbox = task.status == "COMPLETED" and icons.task_done or icons.task
        local line = "   " .. checkbox .. " " .. task.summary
        if vim.fn.strdisplaywidth(line) > state.tasks_width - 2 then
          line = vim.fn.strcharpart(line, 0, state.tasks_width - 5) .. "..."
        end
        local task_line_num = #lines + 1
        table.insert(lines, line)
        state.tasks_line_items[task_line_num] = { type = "task", item = task }
        local hl = task.status == "COMPLETED" and "IcalAgendaTaskCompleted" or "IcalAgendaTaskPending"
        table.insert(highlights, { task_line_num, 0, #line, hl })
      end
    end
    table.insert(lines, "")
  end

  -- No date section
  if #no_date_tasks > 0 then
    table.insert(lines, " No Due Date")
    table.insert(highlights, { #lines, 0, 12, "Comment" })

    for _, task in ipairs(no_date_tasks) do
      local checkbox = task.status == "COMPLETED" and icons.task_done or icons.task
      local line = "  " .. checkbox .. " " .. task.summary
      if vim.fn.strdisplaywidth(line) > state.tasks_width - 2 then
        line = vim.fn.strcharpart(line, 0, state.tasks_width - 5) .. "..."
      end
      local task_line_num = #lines + 1
      table.insert(lines, line)
      state.tasks_line_items[task_line_num] = { type = "task", item = task }
      local hl = task.status == "COMPLETED" and "IcalAgendaTaskCompleted" or "IcalAgendaTaskPending"
      table.insert(highlights, { task_line_num, 0, #line, hl })
    end
  end

  ::write_buffer::

  -- Write to buffer
  vim.bo[state.tasks_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.tasks_buf, 0, -1, false, lines)
  vim.bo[state.tasks_buf].modifiable = false

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("ical-tasks")
  vim.api.nvim_buf_clear_namespace(state.tasks_buf, ns_id, 0, -1)

  for _, hl in ipairs(highlights) do
    local line, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    pcall(vim.api.nvim_buf_add_highlight, state.tasks_buf, ns_id, hl_group, line - 1, col_start, col_end)
  end
end

--- Render events and tasks into buffer
---@param events table[] Array of events (sorted)
---@param tasks table[] Array of tasks
---@param opts table Display options
---@param icons table Icon configuration
function M.render(events, tasks, opts, icons)
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end

  state.events = events
  state.tasks = tasks

  local width = vim.api.nvim_win_get_width(state.main_win)
  local view_date = state.view_date or os.time()

  local lines = {}
  local highlights = {}

  -- Generate header with view mode selector
  local header, header_hl = generate_header(state.view_mode, view_date, width)
  table.insert(lines, header)
  for _, hl in ipairs(header_hl) do
    table.insert(highlights, { 1, hl[1], hl[2], hl[3] })
  end
  table.insert(lines, string.rep("═", width - 2))
  table.insert(lines, "")

  -- Render based on view mode
  local content_lines, content_hl, content_line_items

  if state.view_mode == M.VIEW_MODES.AGENDA then
    content_lines, content_hl, content_line_items = render_agenda_view(events, opts, icons, width)
  elseif state.view_mode == M.VIEW_MODES.DAILY then
    content_lines, content_hl, content_line_items = render_daily_view(events, view_date, opts, icons, width)
  elseif state.view_mode == M.VIEW_MODES.WEEKLY then
    content_lines, content_hl, content_line_items = render_weekly_view(events, view_date, opts, icons, width)
  elseif state.view_mode == M.VIEW_MODES.MONTHLY then
    content_lines, content_hl, content_line_items = render_monthly_view(events, view_date, opts, icons, width)
  elseif state.view_mode == M.VIEW_MODES.YEARLY then
    content_lines, content_hl, content_line_items = render_yearly_view(events, view_date, opts, icons, width)
  else
    content_lines, content_hl, content_line_items = render_agenda_view(events, opts, icons, width)
  end

  -- Append content
  local line_offset = #lines
  for _, line in ipairs(content_lines) do
    table.insert(lines, line)
  end
  for _, hl in ipairs(content_hl) do
    table.insert(highlights, { hl[1] + line_offset, hl[2], hl[3], hl[4] })
  end

  -- Store line-to-item mapping (adjusted for line offset)
  state.line_items = {}
  for line_num, item_info in pairs(content_line_items or {}) do
    state.line_items[line_num + line_offset] = item_info
  end

  -- Footer with help
  table.insert(lines, "")
  table.insert(lines, string.rep("─", width - 2))
  local footer = "q:close r:refresh t:today </> nav n:event N:task x:done"
  table.insert(lines, footer)
  table.insert(highlights, { #lines, 0, #footer, "IcalAgendaFooter" })

  -- Write to buffer
  vim.bo[state.main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
  vim.bo[state.main_buf].modifiable = false

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("ical")
  vim.api.nvim_buf_clear_namespace(state.main_buf, ns_id, 0, -1)

  for _, hl in ipairs(highlights) do
    local line, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    pcall(vim.api.nvim_buf_add_highlight, state.main_buf, ns_id, hl_group, line - 1, col_start, col_end)
  end

  -- Render tasks sidebar
  if state.show_tasks then
    if not state.tasks_win or not vim.api.nvim_win_is_valid(state.tasks_win) then
      M.open_tasks_sidebar()
    end
    M.render_tasks(tasks, opts, icons)
  else
    M.close_tasks_sidebar()
  end
end

--- Setup keymaps for the agenda buffer
---@param keymaps table Keymap configuration
---@param callbacks table Callback functions
function M.setup_keymaps(keymaps, callbacks)
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end

  local buf = state.main_buf

  -- Close keymaps
  local close_keys = type(keymaps.close) == "table" and keymaps.close or { keymaps.close }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, callbacks.close, { buffer = buf, silent = true, desc = "Close agenda" })
  end

  -- Navigation and actions
  vim.keymap.set("n", keymaps.refresh, callbacks.refresh, { buffer = buf, silent = true, desc = "Refresh agenda" })
  vim.keymap.set("n", keymaps.goto_today, callbacks.goto_today, { buffer = buf, silent = true, desc = "Go to today" })
  vim.keymap.set(
    "n",
    keymaps.toggle_tasks,
    callbacks.toggle_tasks,
    { buffer = buf, silent = true, desc = "Toggle tasks" }
  )
  vim.keymap.set(
    "n",
    keymaps.open_calendar,
    callbacks.open_calendar,
    { buffer = buf, silent = true, desc = "Open calendar.vim" }
  )

  -- Navigation keys
  vim.keymap.set("n", "<", callbacks.nav_prev, { buffer = buf, silent = true, desc = "Navigate previous" })
  vim.keymap.set("n", ">", callbacks.nav_next, { buffer = buf, silent = true, desc = "Navigate next" })
  vim.keymap.set("n", "h", callbacks.nav_prev, { buffer = buf, silent = true, desc = "Navigate previous" })
  vim.keymap.set("n", "l", callbacks.nav_next, { buffer = buf, silent = true, desc = "Navigate next" })

  -- View mode keys
  vim.keymap.set("n", "a", callbacks.view_agenda, { buffer = buf, silent = true, desc = "Agenda view" })
  vim.keymap.set("n", "d", callbacks.view_daily, { buffer = buf, silent = true, desc = "Daily view" })
  vim.keymap.set("n", "w", callbacks.view_weekly, { buffer = buf, silent = true, desc = "Weekly view" })
  vim.keymap.set("n", "m", callbacks.view_monthly, { buffer = buf, silent = true, desc = "Monthly view" })
  vim.keymap.set("n", "y", callbacks.view_yearly, { buffer = buf, silent = true, desc = "Yearly view" })

  -- Create new event/task keys
  if callbacks.new_event then
    vim.keymap.set("n", "n", callbacks.new_event, { buffer = buf, silent = true, desc = "New event" })
  end
  if callbacks.new_task then
    vim.keymap.set("n", "N", callbacks.new_task, { buffer = buf, silent = true, desc = "New task" })
  end

  -- View item details on Enter
  if callbacks.view_item then
    vim.keymap.set("n", "<CR>", callbacks.view_item, { buffer = buf, silent = true, desc = "View item details" })
  end

  -- Complete task
  if callbacks.complete_task then
    vim.keymap.set("n", "x", callbacks.complete_task, { buffer = buf, silent = true, desc = "Complete task" })
  end

  -- Also set keymaps on tasks buffer if it exists
  if state.tasks_buf and vim.api.nvim_buf_is_valid(state.tasks_buf) then
    for _, key in ipairs(close_keys) do
      vim.keymap.set("n", key, callbacks.close, { buffer = state.tasks_buf, silent = true, desc = "Close agenda" })
    end
    if callbacks.view_item then
      vim.keymap.set("n", "<CR>", callbacks.view_item, { buffer = state.tasks_buf, silent = true, desc = "View item details" })
    end
    if callbacks.complete_task then
      vim.keymap.set("n", "x", callbacks.complete_task, { buffer = state.tasks_buf, silent = true, desc = "Complete task" })
    end
  end
end

--- Create highlight groups
---@param highlights table Highlight configuration
function M.create_highlights(highlights)
  vim.api.nvim_set_hl(0, "IcalAgendaTitle", { link = highlights.date_header, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaDateHeader", { link = highlights.date_header, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaEventTime", { link = highlights.event_time, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaEventTitle", { link = highlights.event_title, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaEventLocation", { link = highlights.event_location, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaToday", { link = highlights.today, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaTaskPending", { link = highlights.task_pending, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaTaskCompleted", { link = highlights.task_completed, default = true })
  -- Overdue tasks: bold + inherit color from overdue highlight
  local overdue_hl = vim.api.nvim_get_hl(0, { name = highlights.overdue, link = false })
  vim.api.nvim_set_hl(0, "IcalAgendaOverdue", {
    fg = overdue_hl.fg,
    bold = true,
    italic = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "IcalAgendaFooter", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaActiveMode", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaMode", { link = "Comment", default = true })
end

return M
