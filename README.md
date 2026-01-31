# ical.nvim

A Neovim plugin for displaying and creating calendar events and tasks from local iCal (.ics/.ical) files.

## Features

- **Multiple calendar sources** - files, directories, or git repos with recursive scanning
- **Recurring events** - full RRULE support (daily, weekly, monthly, yearly)
- **Tasks/Todos** - VTODO support with due dates and priorities
- **Create events & tasks** - Popup form with multiline description support
- **UUID filenames** - Events saved with unique identifiers
- **calendar.vim integration** - Optional visual calendar sidebar

## Requirements

- Neovim 0.8+
- Optional: [calendar.vim](https://github.com/itchyny/calendar.vim) for visual calendar integration

## Installation

### lazy.nvim

```lua
{
  "simoneSantoni/ical.nvim",
  cmd = {
    "IcalAgenda",
    "IcalNewEvent",
    "IcalNewTask",
  },
  keys = {
    { "<leader>ca", "<cmd>IcalAgenda<cr>", desc = "iCal Agenda" },
    { "<leader>ce", "<cmd>IcalNewEvent<cr>", desc = "New Event" },
    { "<leader>ct", "<cmd>IcalNewTask<cr>", desc = "New Task" },
  },
  opts = {
    calendars = {
      { name = "Personal", path = "~/calendars/personal", color = "#87CEEB" },
      { name = "Work", path = "~/calendars/work.ics", color = "#FFD700" },
    },
  },
}
```

## Quick Start

1. Add a calendar source:
   ```vim
   :IcalAddCalendar ~/path/to/calendar.ics MyCalendar
   ```

2. Open the agenda:
   ```vim
   :IcalAgenda
   ```

3. Navigate with `h`/`l`, edit items with `Enter`, manage tasks with `x`/`d`

## Commands

| Command | Description |
|---------|-------------|
| `:IcalAgenda` | Open agenda view |
| `:IcalAgendaRefresh` | Refresh agenda data |
| `:IcalAgendaClose` | Close agenda window |
| `:IcalNewEvent` | Create new event |
| `:IcalNewTask` | Create new task |
| `:IcalAddCalendar {path} [name] [--recursive]` | Add calendar source |
| `:IcalRemoveCalendar {name}` | Remove calendar source by name or index |
| `:IcalListCalendars` | List configured calendars |

## Keymaps

### Agenda View

| Key | Action |
|-----|--------|
| `h` / `<` | Previous period |
| `l` / `>` | Next period |
| `t` | Go to today |
| `r` | Refresh |
| `T` | Toggle tasks sidebar |
| `c` | Open calendar.vim |
| `n` | New event |
| `N` | New task |
| `Enter` | Edit item at cursor |
| `x` | Complete task at cursor |
| `d` | Delete item at cursor |
| `q` / `Esc` | Close |

### Event/Task Form

| Key | Action |
|-----|--------|
| `j` / `k` / `Down` / `Up` | Navigate fields |
| `Enter` / `e` | Edit field |
| `Tab` | Cycle options / Next field |
| `S` / `Ctrl+S` | Save |
| `q` / `Esc` | Cancel |

### Description Field (Multiline)

| Key | Action |
|-----|--------|
| `Enter` | New line |
| `Ctrl+S` | Save description |
| `Esc` / `q` | Cancel |

## Configuration

```lua
opts = {
  -- Calendar sources
  calendars = {
    { name = "Work", path = "~/calendars/work.ics", color = "#FFD700" },
    { name = "Personal", path = "~/calendars/personal/", color = "#87CEEB" },
    { name = "Shared", path = "~/repos/calendar", color = "#98FB98", recursive = true },
  },

  -- Window settings
  window = {
    width = 60,
    title = " iCal Agenda ",
  },

  -- Display options
  display = {
    date_format = "%a %b %d",
    time_format = "%H:%M",
    show_past_events = false,
    days_ahead = 14,
    group_by_date = true,
    show_all_day = true,
    show_tasks = true,
    show_completed_tasks = false,
    delete_completed_tasks = true,
  },

  -- Keymaps within the agenda window
  keymaps = {
    close = { "q", "<Esc>" },
    refresh = "r",
    goto_today = "t",
    toggle_tasks = "T",
    open_calendar = "c",
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
```

## Calendar Sources

Supports multiple source types:

- **Single files**: `~/calendars/work.ics`
- **Directories**: `~/calendars/personal/` (scans for .ics files)
- **Git repos**: `~/repos/calendar` with `recursive = true`

Works with:
- vdirsyncer (CalDAV sync)
- Exported Google Calendar / Outlook files
- Any .ics/.ical files

## License

MIT
