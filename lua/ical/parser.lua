-- iCal file parser for ical
local utils = require("ical.utils")

local M = {}

--- Unfold continuation lines in iCal content
--- Lines starting with space or tab are continuations of the previous line
---@param content string Raw iCal content
---@return string[] Array of unfolded lines
local function unfold_lines(content)
  local lines = {}
  local current_line = ""

  for line in content:gmatch("[^\r\n]+") do
    -- Check if line starts with whitespace (continuation)
    if line:match("^[ \t]") then
      -- Append to current line (strip leading whitespace)
      current_line = current_line .. line:sub(2)
    else
      -- New line - save previous if exists
      if current_line ~= "" then
        table.insert(lines, current_line)
      end
      current_line = line
    end
  end

  -- Don't forget the last line
  if current_line ~= "" then
    table.insert(lines, current_line)
  end

  return lines
end

--- Parse a property line into name, value, and parameters
--- Example: "DTSTART;TZID=America/New_York:20250115T090000"
--- Returns: "DTSTART", "20250115T090000", { TZID = "America/New_York" }
---@param line string Property line
---@return string name Property name
---@return string value Property value
---@return table params Property parameters
local function parse_property(line)
  local params = {}

  -- Find the colon that separates name/params from value
  local colon_pos = line:find(":")
  if not colon_pos then
    return "", "", {}
  end

  local name_and_params = line:sub(1, colon_pos - 1)
  local value = line:sub(colon_pos + 1)

  -- Check for parameters (separated by semicolons)
  local semicolon_pos = name_and_params:find(";")
  local name

  if semicolon_pos then
    name = name_and_params:sub(1, semicolon_pos - 1)
    local params_str = name_and_params:sub(semicolon_pos + 1)

    -- Parse each parameter
    for param in params_str:gmatch("[^;]+") do
      local eq_pos = param:find("=")
      if eq_pos then
        local param_name = param:sub(1, eq_pos - 1)
        local param_value = param:sub(eq_pos + 1)
        -- Remove quotes if present
        param_value = param_value:gsub('^"', ""):gsub('"$', "")
        params[param_name] = param_value
      end
    end
  else
    name = name_and_params
  end

  return name:upper(), value, params
end

--- Parse a VEVENT component into an event table
---@param lines string[] Array of property lines within the VEVENT
---@return table Event structure
local function parse_vevent(lines)
  local event = {
    uid = "",
    summary = "",
    description = "",
    location = "",
    dtstart = 0,
    dtend = 0,
    all_day = false,
    rrule = nil,
    exdate = {},
    categories = {},
    status = "CONFIRMED",
    is_recurring = false,
  }

  for _, line in ipairs(lines) do
    local name, value, params = parse_property(line)

    if name == "UID" then
      event.uid = value
    elseif name == "SUMMARY" then
      event.summary = utils.decode_ical_text(value)
    elseif name == "DESCRIPTION" then
      event.description = utils.decode_ical_text(value)
    elseif name == "LOCATION" then
      event.location = utils.decode_ical_text(value)
    elseif name == "DTSTART" then
      local ts, is_date = utils.parse_ical_date(value)
      event.dtstart = ts
      if is_date or params.VALUE == "DATE" then
        event.all_day = true
      end
    elseif name == "DTEND" then
      event.dtend = utils.parse_ical_date(value)
    elseif name == "RRULE" then
      event.rrule = value
      event.is_recurring = true
    elseif name == "EXDATE" then
      -- EXDATE can have multiple dates separated by comma
      for date_str in value:gmatch("[^,]+") do
        local ts = utils.parse_ical_date(date_str:match("%d+T?%d*Z?"))
        table.insert(event.exdate, utils.start_of_day(ts))
      end
    elseif name == "CATEGORIES" then
      for cat in value:gmatch("[^,]+") do
        table.insert(event.categories, cat)
      end
    elseif name == "STATUS" then
      event.status = value:upper()
    end
  end

  -- If no end time, default to start time (or start + 1 day for all-day)
  if event.dtend == 0 then
    if event.all_day then
      event.dtend = utils.add_days(event.dtstart, 1)
    else
      event.dtend = event.dtstart
    end
  end

  return event
end

--- Parse a VTODO component into a task table
---@param lines string[] Array of property lines within the VTODO
---@return table Task structure
local function parse_vtodo(lines)
  local task = {
    uid = "",
    summary = "",
    description = "",
    due = nil,
    priority = 0,
    status = "NEEDS-ACTION",
    percent_complete = 0,
    categories = {},
    completed = nil,
  }

  for _, line in ipairs(lines) do
    local name, value, _ = parse_property(line)

    if name == "UID" then
      task.uid = value
    elseif name == "SUMMARY" then
      task.summary = utils.decode_ical_text(value)
    elseif name == "DESCRIPTION" then
      task.description = utils.decode_ical_text(value)
    elseif name == "DUE" then
      task.due = utils.parse_ical_date(value)
    elseif name == "PRIORITY" then
      task.priority = tonumber(value) or 0
    elseif name == "STATUS" then
      task.status = value:upper()
    elseif name == "PERCENT-COMPLETE" then
      task.percent_complete = tonumber(value) or 0
    elseif name == "COMPLETED" then
      task.completed = utils.parse_ical_date(value)
    elseif name == "CATEGORIES" then
      for cat in value:gmatch("[^,]+") do
        table.insert(task.categories, cat)
      end
    end
  end

  return task
end

--- Parse a single .ics file content into structured data
---@param content string Raw .ics file content
---@return table Calendar data with events and todos
function M.parse_ics(content)
  local calendar = {
    events = {},
    todos = {},
    name = "",
  }

  local lines = unfold_lines(content)

  local in_vevent = false
  local in_vtodo = false
  local component_lines = {}

  for _, line in ipairs(lines) do
    if line == "BEGIN:VEVENT" then
      in_vevent = true
      component_lines = {}
    elseif line == "END:VEVENT" then
      in_vevent = false
      local event = parse_vevent(component_lines)
      if event.summary ~= "" then
        table.insert(calendar.events, event)
      end
    elseif line == "BEGIN:VTODO" then
      in_vtodo = true
      component_lines = {}
    elseif line == "END:VTODO" then
      in_vtodo = false
      local task = parse_vtodo(component_lines)
      if task.summary ~= "" then
        table.insert(calendar.todos, task)
      end
    elseif in_vevent or in_vtodo then
      table.insert(component_lines, line)
    else
      -- Parse calendar-level properties
      local name, value, _ = parse_property(line)
      if name == "X-WR-CALNAME" then
        calendar.name = value
      end
    end
  end

  return calendar
end

--- Parse a single .ics/.ical file
---@param filepath string File path
---@param cal_info table Calendar info (name, color)
---@return table[] events Array of events
---@return table[] todos Array of tasks
function M.parse_file(filepath, cal_info)
  local events = {}
  local todos = {}

  filepath = vim.fn.expand(filepath)

  local ok, content = pcall(function()
    return table.concat(vim.fn.readfile(filepath), "\n")
  end)

  if ok and content then
    local parsed = M.parse_ics(content)

    for _, event in ipairs(parsed.events) do
      event.calendar = cal_info.name or parsed.name or "Calendar"
      event.color = cal_info.color
      event.source_file = filepath
      table.insert(events, event)
    end

    for _, task in ipairs(parsed.todos) do
      task.calendar = cal_info.name or parsed.name or "Calendar"
      task.color = cal_info.color
      task.source_file = filepath
      table.insert(todos, task)
    end
  end

  return events, todos
end

--- Parse all .ics files in a directory (optionally recursive)
---@param path string Directory or file path
---@param cal_info table Calendar info (name, color, recursive)
---@return table[] events Array of events
---@return table[] todos Array of tasks
function M.parse_directory(path, cal_info)
  local events = {}
  local todos = {}

  -- Expand path
  path = vim.fn.expand(path)

  -- Check if path is a single file
  if vim.fn.filereadable(path) == 1 then
    return M.parse_file(path, cal_info)
  end

  -- Check if directory exists
  if vim.fn.isdirectory(path) ~= 1 then
    vim.notify("ical: Path not found: " .. path, vim.log.levels.WARN)
    return events, todos
  end

  -- Get .ics and .ical files
  local glob_pattern
  if cal_info.recursive then
    -- Recursive: search all subdirectories (useful for git repos)
    glob_pattern = path .. "/**/*.ics"
  else
    glob_pattern = path .. "/*.ics"
  end

  local ics_files = vim.fn.glob(glob_pattern, false, true)

  -- Also get .ical files
  if cal_info.recursive then
    glob_pattern = path .. "/**/*.ical"
  else
    glob_pattern = path .. "/*.ical"
  end
  local ical_files = vim.fn.glob(glob_pattern, false, true)

  local files = vim.list_extend(ics_files, ical_files)

  -- Also check for webcal exports (some services use .ics inside folders)
  if cal_info.recursive then
    -- Look for common calendar folder structures
    local caldav_files = vim.fn.glob(path .. "/**/calendar.ics", false, true)
    files = vim.list_extend(files, caldav_files)
  end

  -- Deduplicate files
  local seen = {}
  local unique_files = {}
  for _, file in ipairs(files) do
    if not seen[file] then
      seen[file] = true
      table.insert(unique_files, file)
    end
  end

  for _, file in ipairs(unique_files) do
    local file_events, file_todos = M.parse_file(file, cal_info)
    vim.list_extend(events, file_events)
    vim.list_extend(todos, file_todos)
  end

  return events, todos
end

return M
