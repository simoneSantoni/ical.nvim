-- Date/time utilities for ical
local M = {}

--- Get start of day (midnight) for a timestamp
---@param timestamp number Unix timestamp
---@return number Unix timestamp at midnight
function M.start_of_day(timestamp)
  local date = os.date("*t", timestamp)
  date.hour, date.min, date.sec = 0, 0, 0
  return os.time(date)
end

--- Get end of day for a timestamp
---@param timestamp number Unix timestamp
---@return number Unix timestamp at 23:59:59
function M.end_of_day(timestamp)
  return M.start_of_day(timestamp) + 86400 - 1
end

--- Add days to a timestamp
---@param timestamp number Unix timestamp
---@param days number Number of days to add (can be negative)
---@return number New timestamp
function M.add_days(timestamp, days)
  return timestamp + (days * 86400)
end

--- Check if timestamp is today
---@param timestamp number Unix timestamp
---@return boolean
function M.is_today(timestamp)
  local today = M.start_of_day(os.time())
  local ts_day = M.start_of_day(timestamp)
  return today == ts_day
end

--- Check if timestamp is in the past
---@param timestamp number Unix timestamp
---@return boolean
function M.is_past(timestamp)
  return timestamp < os.time()
end

--- Format date for display
---@param timestamp number Unix timestamp
---@param format string strftime format string
---@return string Formatted date
function M.format_date(timestamp, format)
  return os.date(format, timestamp)
end

--- Get day of week (1=Monday, 7=Sunday, ISO standard)
---@param timestamp number Unix timestamp
---@return number Day of week (1-7)
function M.day_of_week(timestamp)
  local dow = tonumber(os.date("%w", timestamp))
  return dow == 0 and 7 or dow
end

--- Parse iCal date/datetime string to timestamp
--- Handles formats: 20250115, 20250115T090000, 20250115T090000Z
---@param datestr string iCal date string
---@return number Unix timestamp
---@return boolean is_date_only (all-day event)
function M.parse_ical_date(datestr)
  if not datestr or datestr == "" then
    return os.time(), false
  end

  local year = tonumber(datestr:sub(1, 4))
  local month = tonumber(datestr:sub(5, 6))
  local day = tonumber(datestr:sub(7, 8))

  if not year or not month or not day then
    return os.time(), false
  end

  local hour, min, sec = 0, 0, 0
  local is_date_only = true

  -- Check for time component (T separator at position 9)
  if #datestr >= 15 and datestr:sub(9, 9) == "T" then
    hour = tonumber(datestr:sub(10, 11)) or 0
    min = tonumber(datestr:sub(12, 13)) or 0
    sec = tonumber(datestr:sub(14, 15)) or 0
    is_date_only = false
  end

  local timestamp = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
  })

  -- Handle UTC indicator (Z suffix) - convert to local time
  if datestr:sub(-1) == "Z" then
    -- Get local timezone offset
    local now = os.time()
    local utc = os.time(os.date("!*t", now))
    local offset = now - utc
    timestamp = timestamp + offset
  end

  return timestamp, is_date_only
end

--- Convert day abbreviation to number (MO=1, TU=2, etc.)
---@param day string Two-letter day abbreviation
---@return number|nil Day number (1-7) or nil if invalid
function M.day_abbrev_to_num(day)
  local map = {
    MO = 1,
    TU = 2,
    WE = 3,
    TH = 4,
    FR = 5,
    SA = 6,
    SU = 7,
  }
  return map[day:upper()]
end

--- Convert day number to abbreviation
---@param num number Day number (1-7)
---@return string Two-letter day abbreviation
function M.day_num_to_abbrev(num)
  local map = { "MO", "TU", "WE", "TH", "FR", "SA", "SU" }
  return map[num] or "MO"
end

--- Get the next occurrence of a specific weekday from a date
---@param timestamp number Starting timestamp
---@param target_day number Target day of week (1-7)
---@return number Timestamp of next occurrence
function M.next_weekday(timestamp, target_day)
  local current_day = M.day_of_week(timestamp)
  local days_ahead = target_day - current_day
  if days_ahead <= 0 then
    days_ahead = days_ahead + 7
  end
  return M.add_days(timestamp, days_ahead)
end

--- Decode iCal escaped text
---@param text string Escaped text
---@return string Decoded text
function M.decode_ical_text(text)
  if not text then
    return ""
  end
  -- Handle common escape sequences
  text = text:gsub("\\n", "\n")
  text = text:gsub("\\,", ",")
  text = text:gsub("\\;", ";")
  text = text:gsub("\\\\", "\\")
  return text
end

--- Read file contents
---@param filepath string Path to file
---@return string|nil content File contents or nil on error
function M.read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

return M
