-- Form UI for creating events and tasks
local utils = require("ical.utils")

local M = {}

-- Form state
local state = {
  buf = nil,
  win = nil,
  fields = {},
  current_field = 1,
  on_submit = nil,
  form_type = nil, -- "event" or "task"
}

-- Field definitions for events
local event_fields = {
  { name = "summary", label = "Title", required = true, default = "" },
  { name = "date", label = "Date", required = true, default = os.date("%Y-%m-%d"), placeholder = "YYYY-MM-DD" },
  { name = "start_time", label = "Start Time", required = false, default = "", placeholder = "HH:MM (empty for all-day)" },
  { name = "end_time", label = "End Time", required = false, default = "", placeholder = "HH:MM" },
  { name = "location", label = "Location", required = false, default = "" },
  { name = "description", label = "Description", required = false, default = "" },
  { name = "calendar", label = "Calendar", required = true, default = "", type = "select" },
}

-- Field definitions for tasks
local task_fields = {
  { name = "summary", label = "Title", required = true, default = "" },
  { name = "due_date", label = "Due Date", required = false, default = "", placeholder = "YYYY-MM-DD (optional)" },
  { name = "due_time", label = "Due Time", required = false, default = "", placeholder = "HH:MM (optional)" },
  { name = "priority", label = "Priority", required = false, default = "0", placeholder = "1-9 (1=highest, 0=none)" },
  { name = "description", label = "Description", required = false, default = "" },
  { name = "calendar", label = "Calendar", required = true, default = "", type = "select" },
}

--- Generate a unique ID for iCal
---@return string UID
local function generate_uid()
  local chars = "0123456789abcdef"
  local uid = ""
  for _ = 1, 32 do
    local idx = math.random(1, #chars)
    uid = uid .. chars:sub(idx, idx)
  end
  return uid .. "@ical.nvim"
end

--- Format date/time for iCal
---@param date string Date in YYYY-MM-DD format
---@param time string|nil Time in HH:MM format
---@return string iCal formatted datetime
local function format_ical_datetime(date, time)
  local year, month, day = date:match("(%d+)-(%d+)-(%d+)")
  if not year then
    return nil
  end

  if time and time ~= "" then
    local hour, min = time:match("(%d+):(%d+)")
    if hour and min then
      return string.format("%04d%02d%02dT%02d%02d00", year, month, day, hour, min)
    end
  end

  -- Date only (all-day event)
  return string.format("%04d%02d%02d", year, month, day)
end

--- Escape text for iCal format
---@param text string
---@return string
local function escape_ical_text(text)
  if not text then
    return ""
  end
  text = text:gsub("\\", "\\\\")
  text = text:gsub(",", "\\,")
  text = text:gsub(";", "\\;")
  text = text:gsub("\n", "\\n")
  return text
end

--- Create VEVENT content
---@param data table Form data
---@return string iCal content
function M.create_vevent(data)
  local lines = {
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//ical.nvim//EN",
    "BEGIN:VEVENT",
    "UID:" .. generate_uid(),
    "DTSTAMP:" .. os.date("!%Y%m%dT%H%M%SZ"),
  }

  -- Summary (required)
  table.insert(lines, "SUMMARY:" .. escape_ical_text(data.summary))

  -- Date/time
  local is_all_day = not data.start_time or data.start_time == ""
  local dtstart = format_ical_datetime(data.date, data.start_time)

  if is_all_day then
    table.insert(lines, "DTSTART;VALUE=DATE:" .. dtstart)
    -- All-day events: end date is exclusive, so add 1 day
    local year, month, day = data.date:match("(%d+)-(%d+)-(%d+)")
    local ts = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day) })
    local next_day = os.date("%Y%m%d", ts + 86400)
    table.insert(lines, "DTEND;VALUE=DATE:" .. next_day)
  else
    table.insert(lines, "DTSTART:" .. dtstart)
    if data.end_time and data.end_time ~= "" then
      local dtend = format_ical_datetime(data.date, data.end_time)
      table.insert(lines, "DTEND:" .. dtend)
    else
      -- Default: 1 hour duration
      local hour, min = data.start_time:match("(%d+):(%d+)")
      local end_hour = tonumber(hour) + 1
      local end_time = string.format("%02d:%02d", end_hour, min)
      local dtend = format_ical_datetime(data.date, end_time)
      table.insert(lines, "DTEND:" .. dtend)
    end
  end

  -- Optional fields
  if data.location and data.location ~= "" then
    table.insert(lines, "LOCATION:" .. escape_ical_text(data.location))
  end

  if data.description and data.description ~= "" then
    table.insert(lines, "DESCRIPTION:" .. escape_ical_text(data.description))
  end

  table.insert(lines, "END:VEVENT")
  table.insert(lines, "END:VCALENDAR")

  return table.concat(lines, "\r\n")
end

--- Create VTODO content
---@param data table Form data
---@return string iCal content
function M.create_vtodo(data)
  local lines = {
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//ical.nvim//EN",
    "BEGIN:VTODO",
    "UID:" .. generate_uid(),
    "DTSTAMP:" .. os.date("!%Y%m%dT%H%M%SZ"),
    "CREATED:" .. os.date("!%Y%m%dT%H%M%SZ"),
  }

  -- Summary (required)
  table.insert(lines, "SUMMARY:" .. escape_ical_text(data.summary))

  -- Status
  table.insert(lines, "STATUS:NEEDS-ACTION")

  -- Due date (optional)
  if data.due_date and data.due_date ~= "" then
    local due = format_ical_datetime(data.due_date, data.due_time)
    if data.due_time and data.due_time ~= "" then
      table.insert(lines, "DUE:" .. due)
    else
      table.insert(lines, "DUE;VALUE=DATE:" .. due)
    end
  end

  -- Priority (optional)
  if data.priority and data.priority ~= "" and data.priority ~= "0" then
    local priority = tonumber(data.priority)
    if priority and priority >= 1 and priority <= 9 then
      table.insert(lines, "PRIORITY:" .. priority)
    end
  end

  -- Description (optional)
  if data.description and data.description ~= "" then
    table.insert(lines, "DESCRIPTION:" .. escape_ical_text(data.description))
  end

  table.insert(lines, "END:VTODO")
  table.insert(lines, "END:VCALENDAR")

  return table.concat(lines, "\r\n")
end

--- Render the form
local function render_form()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = {}
  local highlights = {}

  -- Title
  local title = state.form_type == "event" and "New Event" or "New Task"
  table.insert(lines, " " .. title)
  table.insert(highlights, { 1, 0, #title + 2, "Title" })
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "")

  -- Fields
  for i, field in ipairs(state.fields) do
    local is_current = i == state.current_field
    local prefix = is_current and " > " or "   "
    local required_mark = field.required and "*" or " "

    -- Label line
    local label_line = prefix .. required_mark .. field.label .. ":"
    table.insert(lines, label_line)

    if is_current then
      table.insert(highlights, { #lines, 0, #label_line, "CursorLine" })
    end

    -- Value line (input field)
    local value = field.value or field.default or ""
    local value_line
    if field.type == "select" and field.options then
      -- Show selected option
      local selected = field.options[field.selected_idx or 1] or "(none)"
      value_line = "     [" .. selected .. "] (Tab to change)"
    else
      if value == "" and field.placeholder then
        value_line = "     " .. field.placeholder
        table.insert(highlights, { #lines + 1, 5, 5 + #field.placeholder, "Comment" })
      else
        value_line = "     " .. value
      end
    end
    table.insert(lines, value_line)

    if is_current and field.type ~= "select" then
      table.insert(highlights, { #lines, 5, #value_line, "Visual" })
    elseif is_current and field.type == "select" then
      table.insert(highlights, { #lines, 5, #value_line, "Special" })
    end

    table.insert(lines, "")
  end

  -- Footer
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, " j/k: Navigate  Enter: Edit  Tab: Next/Cycle  S: Save  q: Cancel")
  table.insert(highlights, { #lines, 0, 70, "Comment" })

  -- Write to buffer
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("ical-form")
  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)

  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, state.buf, ns_id, hl[4], hl[1] - 1, hl[2], hl[3])
  end
end

--- Edit current field value
local function edit_current_field()
  local field = state.fields[state.current_field]
  if not field then
    return
  end

  if field.type == "select" then
    -- Cycle through options
    local idx = (field.selected_idx or 1) + 1
    if idx > #field.options then
      idx = 1
    end
    field.selected_idx = idx
    field.value = field.options[idx]
    render_form()
    return
  end

  -- Text input
  local current_value = field.value or field.default or ""
  vim.ui.input({
    prompt = field.label .. ": ",
    default = current_value,
  }, function(input)
    if input ~= nil then
      field.value = input
    end
    render_form()
  end)
end

--- Move to next/prev field
---@param direction number 1 for next, -1 for prev
local function navigate_field(direction)
  state.current_field = state.current_field + direction
  if state.current_field < 1 then
    state.current_field = #state.fields
  elseif state.current_field > #state.fields then
    state.current_field = 1
  end
  render_form()
end

--- Cycle select field options
local function cycle_select()
  local field = state.fields[state.current_field]
  if field and field.type == "select" and field.options then
    local idx = (field.selected_idx or 1) + 1
    if idx > #field.options then
      idx = 1
    end
    field.selected_idx = idx
    field.value = field.options[idx]
    render_form()
  else
    -- Move to next field
    navigate_field(1)
  end
end

--- Validate and submit the form
local function submit_form()
  -- Validate required fields
  for _, field in ipairs(state.fields) do
    if field.required then
      local value = field.value or field.default or ""
      if value == "" then
        vim.notify("ical: " .. field.label .. " is required", vim.log.levels.ERROR)
        return
      end
    end
  end

  -- Collect form data
  local data = {}
  for _, field in ipairs(state.fields) do
    data[field.name] = field.value or field.default or ""
  end

  -- Close form
  M.close()

  -- Call submit callback
  if state.on_submit then
    state.on_submit(data)
  end
end

--- Setup keymaps for the form
local function setup_keymaps()
  local buf = state.buf
  local opts = { buffer = buf, silent = true }

  vim.keymap.set("n", "j", function()
    navigate_field(1)
  end, opts)
  vim.keymap.set("n", "k", function()
    navigate_field(-1)
  end, opts)
  vim.keymap.set("n", "<Down>", function()
    navigate_field(1)
  end, opts)
  vim.keymap.set("n", "<Up>", function()
    navigate_field(-1)
  end, opts)
  vim.keymap.set("n", "<CR>", edit_current_field, opts)
  vim.keymap.set("n", "e", edit_current_field, opts)
  vim.keymap.set("n", "<Tab>", cycle_select, opts)
  vim.keymap.set("n", "S", submit_form, opts)
  vim.keymap.set("n", "<C-s>", submit_form, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
end

--- Open the form window
---@param form_type string "event" or "task"
---@param calendars table[] Available calendars
---@param on_submit function Callback with form data
function M.open(form_type, calendars, on_submit)
  -- Close existing form
  M.close()

  state.form_type = form_type
  state.on_submit = on_submit
  state.current_field = 1

  -- Copy field definitions
  local field_defs = form_type == "event" and event_fields or task_fields
  state.fields = {}
  for _, def in ipairs(field_defs) do
    local field = vim.tbl_extend("force", {}, def)

    -- Setup calendar select options
    if field.name == "calendar" then
      field.options = {}
      for _, cal in ipairs(calendars) do
        table.insert(field.options, cal.name)
      end
      if #field.options > 0 then
        field.selected_idx = 1
        field.value = field.options[1]
      else
        field.options = { "(no calendars configured)" }
        field.selected_idx = 1
        field.value = ""
      end
    end

    table.insert(state.fields, field)
  end

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "ical-form"

  -- Calculate window size and position
  local width = 55
  local height = #state.fields * 3 + 6
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Create window
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = form_type == "event" and " New Event " or " New Task ",
    title_pos = "center",
  })

  vim.wo[state.win].cursorline = false
  vim.wo[state.win].wrap = true

  -- Setup keymaps and render
  setup_keymaps()
  render_form()
end

--- Close the form window
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.fields = {}
  state.on_submit = nil
end

--- Check if form is open
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return M
