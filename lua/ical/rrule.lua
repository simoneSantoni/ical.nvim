-- Recurrence rule (RRULE) parser and expander for ical
local utils = require("ical.utils")

local M = {}

--- Parse RRULE property value into components
--- Example: "FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20251231T235959Z"
---@param rrule_str string RRULE value
---@return table Parsed rule components
function M.parse(rrule_str)
  local rule = {
    freq = nil, -- DAILY, WEEKLY, MONTHLY, YEARLY
    interval = 1,
    count = nil,
    until_date = nil,
    byday = {},
    bymonthday = {},
    bymonth = {},
    wkst = "MO",
  }

  for part in rrule_str:gmatch("[^;]+") do
    local key, value = part:match("([^=]+)=(.+)")
    if key and value then
      key = key:upper()

      if key == "FREQ" then
        rule.freq = value:upper()
      elseif key == "INTERVAL" then
        rule.interval = tonumber(value) or 1
      elseif key == "COUNT" then
        rule.count = tonumber(value)
      elseif key == "UNTIL" then
        rule.until_date = utils.parse_ical_date(value)
      elseif key == "BYDAY" then
        for day in value:gmatch("[^,]+") do
          -- Handle optional position prefix (e.g., "2MO" for second Monday)
          local pos, dayname = day:match("^(-?%d*)(%a+)$")
          table.insert(rule.byday, {
            day = dayname:upper(),
            pos = pos ~= "" and tonumber(pos) or nil,
          })
        end
      elseif key == "BYMONTHDAY" then
        for d in value:gmatch("[^,]+") do
          table.insert(rule.bymonthday, tonumber(d))
        end
      elseif key == "BYMONTH" then
        for m in value:gmatch("[^,]+") do
          table.insert(rule.bymonth, tonumber(m))
        end
      elseif key == "WKST" then
        rule.wkst = value:upper()
      end
    end
  end

  return rule
end

--- Check if a date is in the exception list
---@param timestamp number Date to check
---@param exdates table[] Array of exception date timestamps
---@return boolean
local function is_excluded(timestamp, exdates)
  local date_start = utils.start_of_day(timestamp)
  for _, exdate in ipairs(exdates) do
    if utils.start_of_day(exdate) == date_start then
      return true
    end
  end
  return false
end

--- Create an event instance from base event at a new time
---@param base_event table Original event
---@param new_start number New start timestamp
---@return table Event instance
local function create_instance(base_event, new_start)
  local duration = base_event.dtend - base_event.dtstart
  return vim.tbl_extend("force", base_event, {
    dtstart = new_start,
    dtend = new_start + duration,
    is_instance = true,
    original_start = base_event.dtstart,
  })
end

--- Expand DAILY recurrence
---@param event table Base event
---@param rule table Parsed RRULE
---@param range_start number Range start timestamp
---@param range_end number Range end timestamp
---@return table[] Array of event instances
local function expand_daily(event, rule, range_start, range_end)
  local instances = {}
  local current = event.dtstart
  local count = 0
  local max_count = rule.count or 365 * 2 -- Safety limit

  while current <= range_end and count < max_count do
    -- Check UNTIL
    if rule.until_date and current > rule.until_date then
      break
    end

    -- Check COUNT
    if rule.count and #instances >= rule.count then
      break
    end

    -- Add if within range and not excluded
    if current >= range_start and not is_excluded(current, event.exdate or {}) then
      table.insert(instances, create_instance(event, current))
    end

    -- Advance by interval
    current = utils.add_days(current, rule.interval)
    count = count + 1
  end

  return instances
end

--- Expand WEEKLY recurrence
---@param event table Base event
---@param rule table Parsed RRULE
---@param range_start number Range start timestamp
---@param range_end number Range end timestamp
---@return table[] Array of event instances
local function expand_weekly(event, rule, range_start, range_end)
  local instances = {}
  local instance_count = 0
  local max_iterations = 52 * 2 * 7 -- 2 years of days

  -- Determine which days of the week
  local days_of_week = {}
  if #rule.byday > 0 then
    for _, bd in ipairs(rule.byday) do
      local day_num = utils.day_abbrev_to_num(bd.day)
      if day_num then
        days_of_week[day_num] = true
      end
    end
  else
    -- Default to the day of the original event
    days_of_week[utils.day_of_week(event.dtstart)] = true
  end

  -- Start from the beginning of the week containing the event
  local event_dow = utils.day_of_week(event.dtstart)
  local week_start = utils.add_days(utils.start_of_day(event.dtstart), 1 - event_dow)

  local current_week = week_start
  local iteration = 0

  while iteration < max_iterations do
    -- Check each day of this week
    for day_num = 1, 7 do
      if days_of_week[day_num] then
        local current = utils.add_days(current_week, day_num - 1)

        -- Preserve original time of day
        local date_parts = os.date("*t", current)
        local time_parts = os.date("*t", event.dtstart)
        date_parts.hour = time_parts.hour
        date_parts.min = time_parts.min
        date_parts.sec = time_parts.sec
        current = os.time(date_parts)

        -- Skip if before original event start
        if current < event.dtstart then
          goto continue
        end

        -- Check UNTIL
        if rule.until_date and current > rule.until_date then
          return instances
        end

        -- Check COUNT
        if rule.count then
          instance_count = instance_count + 1
          if instance_count > rule.count then
            return instances
          end
        end

        -- Check if past range end
        if current > range_end then
          return instances
        end

        -- Add if within range and not excluded
        if current >= range_start and not is_excluded(current, event.exdate or {}) then
          table.insert(instances, create_instance(event, current))
        end

        ::continue::
      end
    end

    -- Advance to next interval week
    current_week = utils.add_days(current_week, 7 * rule.interval)
    iteration = iteration + 1
  end

  return instances
end

--- Expand MONTHLY recurrence
---@param event table Base event
---@param rule table Parsed RRULE
---@param range_start number Range start timestamp
---@param range_end number Range end timestamp
---@return table[] Array of event instances
local function expand_monthly(event, rule, range_start, range_end)
  local instances = {}
  local instance_count = 0
  local max_iterations = 24 * 2 -- 2 years of months

  local start_date = os.date("*t", event.dtstart)
  local current_year = start_date.year
  local current_month = start_date.month

  for _ = 1, max_iterations do
    -- Determine the day(s) in this month
    local days = {}

    if #rule.bymonthday > 0 then
      -- Specific days of month
      for _, d in ipairs(rule.bymonthday) do
        table.insert(days, d)
      end
    else
      -- Same day as original event
      table.insert(days, start_date.day)
    end

    for _, day in ipairs(days) do
      -- Handle months with fewer days
      local month_days = os.date("*t", os.time({ year = current_year, month = current_month + 1, day = 0 })).day
      if day > month_days then
        day = month_days
      end

      local current = os.time({
        year = current_year,
        month = current_month,
        day = day,
        hour = start_date.hour,
        min = start_date.min,
        sec = start_date.sec,
      })

      -- Skip if before original event
      if current < event.dtstart then
        goto continue
      end

      -- Check UNTIL
      if rule.until_date and current > rule.until_date then
        return instances
      end

      -- Check COUNT
      if rule.count then
        instance_count = instance_count + 1
        if instance_count > rule.count then
          return instances
        end
      end

      -- Check if past range end
      if current > range_end then
        return instances
      end

      -- Add if within range and not excluded
      if current >= range_start and not is_excluded(current, event.exdate or {}) then
        table.insert(instances, create_instance(event, current))
      end

      ::continue::
    end

    -- Advance by interval months
    current_month = current_month + rule.interval
    while current_month > 12 do
      current_month = current_month - 12
      current_year = current_year + 1
    end
  end

  return instances
end

--- Expand YEARLY recurrence
---@param event table Base event
---@param rule table Parsed RRULE
---@param range_start number Range start timestamp
---@param range_end number Range end timestamp
---@return table[] Array of event instances
local function expand_yearly(event, rule, range_start, range_end)
  local instances = {}
  local instance_count = 0
  local max_iterations = 10 -- 10 years

  local start_date = os.date("*t", event.dtstart)
  local current_year = start_date.year

  for _ = 1, max_iterations do
    local current = os.time({
      year = current_year,
      month = start_date.month,
      day = start_date.day,
      hour = start_date.hour,
      min = start_date.min,
      sec = start_date.sec,
    })

    -- Skip if before original event
    if current >= event.dtstart then
      -- Check UNTIL
      if rule.until_date and current > rule.until_date then
        return instances
      end

      -- Check COUNT
      if rule.count then
        instance_count = instance_count + 1
        if instance_count > rule.count then
          return instances
        end
      end

      -- Check if past range end
      if current > range_end then
        return instances
      end

      -- Add if within range and not excluded
      if current >= range_start and not is_excluded(current, event.exdate or {}) then
        table.insert(instances, create_instance(event, current))
      end
    end

    -- Advance by interval years
    current_year = current_year + rule.interval
  end

  return instances
end

--- Expand a recurring event into instances within a date range
---@param event table Event with rrule property
---@param range_start number Start of range (timestamp)
---@param range_end number End of range (timestamp)
---@return table[] Array of event instances
function M.expand(event, range_start, range_end)
  if not event.rrule then
    return { event }
  end

  local rule = M.parse(event.rrule)

  if not rule.freq then
    return { event }
  end

  if rule.freq == "DAILY" then
    return expand_daily(event, rule, range_start, range_end)
  elseif rule.freq == "WEEKLY" then
    return expand_weekly(event, rule, range_start, range_end)
  elseif rule.freq == "MONTHLY" then
    return expand_monthly(event, rule, range_start, range_end)
  elseif rule.freq == "YEARLY" then
    return expand_yearly(event, rule, range_start, range_end)
  end

  -- Unsupported frequency - return original event if in range
  if event.dtstart >= range_start and event.dtstart <= range_end then
    return { event }
  end

  return {}
end

return M
