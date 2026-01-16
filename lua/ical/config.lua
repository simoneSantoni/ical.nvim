-- Default configuration for ical
local M = {}

M.defaults = {
  -- Paths to .ics files or directories containing them
  -- Supports:
  --   - Single .ics/.ical files
  --   - Directories (scans for .ics/.ical files)
  --   - Git repo clones with `recursive = true` to search subdirectories
  --
  -- Examples:
  -- calendars = {
  --   { name = "Personal", path = "~/calendars/personal.ics", color = "#87CEEB" },
  --   { name = "Work", path = "~/calendars/work", color = "#FFD700" },
  --   { name = "GitHub Cal", path = "~/repos/my-calendar-repo", color = "#98FB98", recursive = true },
  -- }
  calendars = {},

  -- UI Settings (opens in a new tab with tasks sidebar)
  window = {
    width = 60, -- Minimum width hint for content
    title = " iCal Agenda ",
  },

  -- Display options
  display = {
    date_format = "%a %b %d", -- e.g., "Mon Jan 15"
    time_format = "%H:%M", -- e.g., "14:30"
    show_past_events = false,
    days_ahead = 14,
    group_by_date = true,
    show_all_day = true,
    show_tasks = true,
    show_completed_tasks = false,
  },

  -- Highlight groups
  highlights = {
    date_header = "Title",
    event_time = "Number",
    event_title = "Normal",
    event_location = "Comment",
    today = "CursorLine",
    task_pending = "Todo",
    task_completed = "Comment",
    overdue = "ErrorMsg",
    calendar_color = "Special",
  },

  -- Keymaps within the agenda window
  keymaps = {
    close = { "q", "<Esc>" },
    refresh = "r",
    next_week = "<C-d>",
    prev_week = "<C-u>",
    goto_today = "t",
    toggle_tasks = "T",
    open_calendar = "c",
  },

  -- Auto-refresh settings
  refresh = {
    on_focus = false,
    interval = 0,
  },

  -- Icons (set to empty strings to disable)
  icons = {
    event = "",
    task = "☐",
    task_done = "☑",
    location = "@",
    recurring = "↻",
    all_day = "◷",
  },
}

return M
