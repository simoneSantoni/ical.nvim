-- Bridge module: sync ical.nvim events to calendar.vim's local cache
local parser = require("ical.parser")
local utils = require("ical.utils")

local M = {}

-- Sync range defaults (months)
local MONTHS_BACK = 3
local MONTHS_AHEAD = 12

--- Percent-encode a string the same way calendar.vim's cache.vim does
--- Matches: substitute(key, '[^a-zA-Z0-9_.-]', printf("%%%02X", char2nr(...)), 'g')
---@param str string
---@return string
local function percent_encode(str)
  return str:gsub("[^%w_.-]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

--- Get the calendar.vim local cache base directory
--- Respects g:calendar_cache_directory if set
---@return string
local function get_cache_base()
  local cache_dir = vim.g.calendar_cache_directory
  if cache_dir then
    cache_dir = vim.fn.expand(cache_dir)
  else
    cache_dir = vim.fn.expand("~/.cache/calendar.vim")
  end
  if cache_dir:sub(-1) ~= "/" then
    cache_dir = cache_dir .. "/"
  end
  return cache_dir .. "local/"
end

--- Ensure a directory exists with 700 permissions
---@param path string
local function ensure_dir(path)
  if vim.fn.isdirectory(path) ~= 1 then
    vim.fn.mkdir(path, "p")
  end
  vim.fn.setfperm(path, "rwx------")
end

--- Write a JSON file with 600 permissions (single-line, matching calendar.vim's writefile format)
---@param path string
---@param data table
---@return boolean success
local function write_json_file(path, data)
  local json_str = vim.fn.json_encode(data)
  local file, err = io.open(path, "w")
  if not file then
    vim.notify("ical bridge: failed to write " .. path .. ": " .. (err or "unknown"), vim.log.levels.ERROR)
    return false
  end
  file:write(json_str)
  file:close()
  vim.fn.setfperm(path, "rw-------")
  return true
end

--- Build a safe calendar ID from a calendar name
---@param name string
---@return string
local function make_calendar_id(name)
  return "ical_" .. name:gsub("[^%w_.-]", "_")
end

--- Generate a deterministic event ID from start time + UID hash
--- Format: YYYYMMDDHHMMSScccc (matching calendar.vim's calendar#util#id())
---@param event table
---@return string
local function generate_event_id(event)
  local dt = os.date("*t", event.dtstart)
  local uid_hash = 0
  for i = 1, #(event.uid or "") do
    uid_hash = (uid_hash * 31 + string.byte(event.uid, i)) % 10000
  end
  return string.format(
    "%04d%02d%02d%02d%02d%02d%04d",
    dt.year, dt.month, dt.day,
    dt.hour or 0, dt.min or 0, dt.sec or 0,
    uid_hash
  )
end

--- Transform an ical.nvim event into a calendar.vim event item
---@param event table Parsed ical.nvim event
---@return table calendar.vim event item
local function transform_event(event)
  local item = {
    id = generate_event_id(event),
    summary = event.summary or "",
  }

  if event.all_day then
    item.start = { date = os.date("%Y-%m-%d", event.dtstart) }
    item["end"] = { date = os.date("%Y-%m-%d", event.dtend) }
  else
    item.start = { dateTime = os.date("%Y-%m-%dT%H:%M:%S", event.dtstart) }
    item["end"] = { dateTime = os.date("%Y-%m-%dT%H:%M:%S", event.dtend) }
  end

  return item
end

--- Group events by year/month for calendar.vim's per-month cache files
---@param events table[] Array of ical.nvim events
---@return table<string, table[]> Map of "YYYY/MM" -> array of calendar.vim event items
local function group_events_by_month(events)
  local months = {}

  for _, event in ipairs(events) do
    local dt = os.date("*t", event.dtstart)
    local key = string.format("%04d/%02d", dt.year, dt.month)
    if not months[key] then
      months[key] = {}
    end
    table.insert(months[key], transform_event(event))

    -- Multi-day events: also add to subsequent months they span
    if event.dtend and event.dtend > event.dtstart then
      local end_dt = os.date("*t", event.dtend)
      local end_key = string.format("%04d/%02d", end_dt.year, end_dt.month)
      if end_key ~= key then
        local cur_year, cur_month = dt.year, dt.month
        while true do
          cur_month = cur_month + 1
          if cur_month > 12 then
            cur_month = 1
            cur_year = cur_year + 1
          end
          local cur_key = string.format("%04d/%02d", cur_year, cur_month)
          if not months[cur_key] then
            months[cur_key] = {}
          end
          table.insert(months[cur_key], transform_event(event))
          if cur_key == end_key then
            break
          end
        end
      end
    end
  end

  return months
end

--- Build calendarList data from ical.nvim calendar configs
---@param calendars table[] Array of ical.nvim calendar configs
---@return table calendarList JSON structure
local function build_calendar_list(calendars)
  local items = {}
  for _, cal in ipairs(calendars) do
    table.insert(items, {
      id = make_calendar_id(cal.name),
      summary = cal.name,
      backgroundColor = cal.color or "#87CEEB",
      foregroundColor = "#000000",
    })
  end
  return { items = items }
end

--- Write calendarList, merging with any existing non-ical entries
---@param data table calendarList data
---@return boolean success
local function write_calendar_list(data)
  local base = get_cache_base()
  ensure_dir(base)

  local existing_path = base .. "calendarList"
  if vim.fn.filereadable(existing_path) == 1 then
    local ok, content = pcall(function()
      local lines = vim.fn.readfile(existing_path)
      return vim.fn.json_decode(table.concat(lines, ""))
    end)
    if ok and type(content) == "table" and type(content.items) == "table" then
      -- Preserve non-ical entries
      local preserved = {}
      for _, item in ipairs(content.items) do
        if not vim.startswith(item.id or "", "ical_") then
          table.insert(preserved, item)
        end
      end
      for _, item in ipairs(data.items) do
        table.insert(preserved, item)
      end
      data = { items = preserved }
    end
  end

  return write_json_file(existing_path, data)
end

--- Write events for a single month
---@param calendar_id string
---@param year_str string
---@param month_str string
---@param items table[] Array of calendar.vim event items
---@return boolean success
local function write_month_events(calendar_id, year_str, month_str, items)
  local base = get_cache_base()
  local dir = base
    .. "event/"
    .. percent_encode(calendar_id) .. "/"
    .. percent_encode(year_str) .. "/"
    .. percent_encode(month_str) .. "/"
  ensure_dir(dir)
  return write_json_file(dir .. "0", { items = items })
end

--- Clear all cached events for a calendar
---@param calendar_id string
local function clear_calendar_cache(calendar_id)
  local cal_dir = get_cache_base() .. "event/" .. percent_encode(calendar_id)
  if vim.fn.isdirectory(cal_dir) == 1 then
    vim.fn.delete(cal_dir, "rf")
  end
end

--- Sync ical.nvim events to calendar.vim's local cache
---@param ical_config table ical.nvim configuration (must have .calendars)
function M.sync(ical_config)
  local calendars = ical_config.calendars
  if not calendars or #calendars == 0 then
    vim.notify("ical bridge: no calendars configured", vim.log.levels.WARN)
    return
  end

  local ok_rrule, rrule = pcall(require, "ical.rrule")

  -- Calculate sync range
  local now = os.time()
  local range_start_t = os.date("*t", now)
  range_start_t.month = range_start_t.month - MONTHS_BACK
  range_start_t.hour, range_start_t.min, range_start_t.sec = 0, 0, 0
  local range_start = os.time(range_start_t)

  local range_end_t = os.date("*t", now)
  range_end_t.month = range_end_t.month + MONTHS_AHEAD
  range_end_t.hour, range_end_t.min, range_end_t.sec = 23, 59, 59
  local range_end = os.time(range_end_t)

  -- Build and write calendarList
  local cal_list = build_calendar_list(calendars)
  write_calendar_list(cal_list)

  local total_events = 0

  for i, cal in ipairs(calendars) do
    local calendar_id = cal_list.items[i].id

    -- Parse all .ics files
    local events, _ = parser.parse_directory(cal.path, cal)

    -- Expand recurring events and filter to sync range
    local expanded = {}
    for _, event in ipairs(events) do
      if event.rrule and ok_rrule then
        local instances = rrule.expand(event, range_start, range_end)
        for _, instance in ipairs(instances) do
          table.insert(expanded, instance)
        end
      else
        -- Include if event overlaps with the sync range
        local ev_end = event.dtend or event.dtstart
        if event.dtstart <= range_end and ev_end >= range_start then
          table.insert(expanded, event)
        end
      end
    end

    -- Clear old cache and write fresh data
    clear_calendar_cache(calendar_id)

    local monthly = group_events_by_month(expanded)
    for key, items in pairs(monthly) do
      local year_str, month_str = key:match("(%d+)/(%d+)")
      write_month_events(calendar_id, year_str, month_str, items)
    end

    total_events = total_events + #expanded
  end

  vim.notify(
    string.format("ical bridge: synced %d events from %d calendar(s)", total_events, #calendars),
    vim.log.levels.INFO
  )
end

return M
