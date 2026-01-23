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
  { name = "description", label = "Description", required = false, default = "", multiline = true, lines = 8 },
  { name = "calendar", label = "Calendar", required = true, default = "", type = "select" },
}

-- Field definitions for tasks
local task_fields = {
  { name = "summary", label = "Title", required = true, default = "" },
  { name = "due_date", label = "Due Date", required = false, default = "", placeholder = "YYYY-MM-DD (optional)" },
  { name = "due_time", label = "Due Time", required = false, default = "", placeholder = "HH:MM (optional)" },
  { name = "priority", label = "Priority", required = false, default = "0", placeholder = "1-9 (1=highest, 0=none)" },
  { name = "description", label = "Description", required = false, default = "", multiline = true, lines = 8 },
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
  local win_width = state.win_width or 83
  local separator_width = win_width - 2  -- Nearly full width
  local separator_line = " " .. string.rep("─", separator_width)  -- 1 space padding for visual balance

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

    -- Value line(s) (input field)
    local value = field.value or field.default or ""
    if field.type == "select" and field.options then
      -- Show selected option
      local selected = field.options[field.selected_idx or 1] or "(none)"
      local value_line = "     [" .. selected .. "] (Tab to change)"
      table.insert(lines, value_line)
      if is_current then
        table.insert(highlights, { #lines, 5, #value_line, "Special" })
      end
    elseif field.multiline then
      -- Multiline field: show multiple lines for the value
      local display_lines = field.lines or 3
      local value_lines = {}
      -- Split value by newlines if any
      for line in (value .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(value_lines, line)
      end
      -- Render each line
      for j = 1, display_lines do
        local line_value = value_lines[j] or ""
        local value_line
        if j == 1 and line_value == "" and field.placeholder then
          value_line = "     " .. field.placeholder
          table.insert(lines, value_line)
          table.insert(highlights, { #lines, 5, 5 + #field.placeholder, "Comment" })
        else
          value_line = "     " .. line_value
          table.insert(lines, value_line)
        end
        if is_current then
          table.insert(highlights, { #lines, 5, math.max(#value_line, 6), "Visual" })
        end
      end
    else
      -- Single line field
      local value_line
      if value == "" and field.placeholder then
        value_line = "     " .. field.placeholder
        table.insert(lines, value_line)
        table.insert(highlights, { #lines, 5, 5 + #field.placeholder, "Comment" })
      else
        value_line = "     " .. value
        table.insert(lines, value_line)
      end
      if is_current then
        table.insert(highlights, { #lines, 5, #value_line, "Visual" })
      end
    end

    table.insert(lines, "")
  end

  -- Footer (directly after last field, no extra padding)
  table.insert(lines, separator_line)
  local footer_text
  if state.on_submit then
    footer_text = " j/k: Navigate  Enter: Edit  Tab: Next/Cycle  S: Save  q: Cancel"
  else
    footer_text = " q/Esc/Enter: Close"
  end
  table.insert(lines, footer_text)
  table.insert(highlights, { #lines, 0, #footer_text, "Comment" })

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

--- Create a floating input window positioned near the form
---@param prompt string The prompt text
---@param default string Default value
---@param callback function Callback with input value
---@param multiline boolean|nil If true, create a multiline input
---@param height number|nil Height for multiline input (default 8)
local function floating_input(prompt, default, callback, multiline, height)
  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].buftype = "nofile"
  vim.bo[input_buf].bufhidden = "wipe"

  -- Position input just below the form window
  local input_width = state.win_width - 4
  local input_height = multiline and (height or 8) or 1
  local input_row = state.win_row + state.win_height + 1
  local input_col = state.win_col + 2

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    width = input_width,
    height = input_height,
    row = input_row,
    col = input_col,
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. (multiline and " (Ctrl+S to save, Esc to cancel) " or " "),
    title_pos = "left",
  })

  -- Set initial value
  if multiline then
    -- Split by newlines for multiline
    local lines = {}
    for line in ((default or "") .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, line)
    end
    if #lines == 0 then
      lines = { "" }
    end
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, lines)
  else
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { default or "" })
  end
  vim.cmd("startinsert!")
  vim.api.nvim_win_set_cursor(input_win, { 1, #(default or ""):match("^[^\n]*") })

  -- Handle submit/cancel
  local function close_input(submit)
    local value = nil
    if submit then
      local lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
      if multiline then
        value = table.concat(lines, "\n")
      else
        value = lines[1] or ""
      end
    end
    if vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_close(input_win, true)
    end
    vim.cmd("stopinsert")
    -- Refocus form window
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    callback(value)
  end

  if multiline then
    -- For multiline: Ctrl+S to save, Esc to cancel, Enter creates new line
    vim.keymap.set({ "i", "n" }, "<C-s>", function()
      close_input(true)
    end, { buffer = input_buf, silent = true })
  else
    -- For single line: Enter to save
    vim.keymap.set({ "i", "n" }, "<CR>", function()
      close_input(true)
    end, { buffer = input_buf, silent = true })
  end
  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    close_input(false)
  end, { buffer = input_buf, silent = true })
  vim.keymap.set("n", "q", function()
    close_input(false)
  end, { buffer = input_buf, silent = true })
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

  -- Text input with floating window near the form
  local current_value = field.value or field.default or ""
  local is_multiline = field.multiline or false
  local input_height = field.lines or 8
  floating_input(field.label, current_value, function(input)
    if input ~= nil then
      field.value = input
    end
    render_form()
  end, is_multiline, input_height)
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

  -- Save callback before close (close clears state.on_submit)
  local callback = state.on_submit

  -- Close form
  M.close()

  -- Call submit callback
  if callback then
    callback(data)
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

  -- Calculate window size based on content
  local width = 83
  -- Calculate height: fields + footer (2 lines)
  local content_height = 2  -- Footer only (title is in window border)
  for _, field in ipairs(state.fields) do
    if field.multiline then
      content_height = content_height + 1 + (field.lines or 3) + 1  -- label + lines + spacing
    else
      content_height = content_height + 3  -- label + value + spacing
    end
  end
  local height = content_height
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Store position for input box positioning
  state.win_row = row
  state.win_col = col
  state.win_width = width
  state.win_height = height

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
  vim.wo[state.win].list = false

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

--- Open a view-only form to display event/task details
---@param form_type string "event" or "task"
---@param data table Pre-filled data to display
function M.open_view(form_type, data)
  -- Close existing form
  M.close()

  state.form_type = form_type
  state.on_submit = nil  -- View-only, no submit
  state.current_field = 1

  -- Copy field definitions and populate with data
  local field_defs = form_type == "event" and event_fields or task_fields
  state.fields = {}
  for _, def in ipairs(field_defs) do
    local field = vim.tbl_extend("force", {}, def)
    -- Populate with data
    if data[field.name] then
      field.value = data[field.name]
    end
    -- For calendar field in view mode, just show the value
    if field.name == "calendar" then
      field.type = nil  -- Not a select in view mode
      field.value = data.calendar or "(unknown)"
    end
    table.insert(state.fields, field)
  end

  -- Add status field for tasks
  if form_type == "task" and data.status then
    table.insert(state.fields, {
      name = "status",
      label = "Status",
      value = data.status,
      required = false,
    })
  end

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "ical-form"

  -- Calculate window size based on content
  local width = 83
  local content_height = 2  -- Footer only
  for _, field in ipairs(state.fields) do
    if field.multiline then
      content_height = content_height + 1 + (field.lines or 3) + 1
    else
      content_height = content_height + 3
    end
  end
  local height = content_height
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Store position
  state.win_row = row
  state.win_col = col
  state.win_width = width
  state.win_height = height

  -- Create window
  local title = form_type == "event" and " Event Details " or " Task Details "
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  vim.wo[state.win].cursorline = false
  vim.wo[state.win].wrap = true
  vim.wo[state.win].list = false

  -- Render form (view-only)
  render_form()

  -- Setup view-only keymaps (just close)
  local buf = state.buf
  vim.keymap.set("n", "q", M.close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<CR>", M.close, { buffer = buf, silent = true })
end

return M
