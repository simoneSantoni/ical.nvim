# ical.nvim

A Neovim plugin for displaying and creating calendar events and tasks from local iCal (.ics/.ical) files.

## Features

- **Multiple calendar sources** - files, directories, or git repos with recursive scanning
- **Recurring events** - full RRULE support (daily, weekly, monthly, yearly)
- **Tasks/Todos** - VTODO support with due dates and priorities
- **Multiple views** - Agenda, Daily, Weekly, Monthly, Yearly
- **Create events & tasks** - Popup form with multiline description support
- **UUID filenames** - Events saved with unique identifiers

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
    "IcalDaily",
    "IcalWeekly",
    "IcalMonthly",
    "IcalYearly",
    "IcalNewEvent",
    "IcalNewTask",
  },
  keys = {
    { "<leader>ca", "<cmd>IcalAgenda<cr>", desc = "iCal Agenda" },
    { "<leader>cd", "<cmd>IcalDaily<cr>", desc = "iCal Daily" },
    { "<leader>cW", "<cmd>IcalWeekly<cr>", desc = "iCal Weekly" },
    { "<leader>cM", "<cmd>IcalMonthly<cr>", desc = "iCal Monthly" },
    { "<leader>cY", "<cmd>IcalYearly<cr>", desc = "iCal Yearly" },
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

3. Navigate with `h`/`l`, switch views with `a`/`d`/`w`/`m`/`y`

## Commands

| Command | Description |
|---------|-------------|
| `:IcalAgenda [view]` | Open agenda (optional: daily, weekly, monthly, yearly) |
| `:IcalDaily` | Open daily view |
| `:IcalWeekly` | Open weekly view |
| `:IcalMonthly` | Open monthly view |
| `:IcalYearly` | Open yearly view |
| `:IcalNewEvent` | Create new event |
| `:IcalNewTask` | Create new task |
| `:IcalAddCalendar {path} [name] [--recursive]` | Add calendar source |
| `:IcalRemoveCalendar {name}` | Remove calendar source |
| `:IcalListCalendars` | List configured calendars |

## Keymaps

### Agenda View

| Key | Action |
|-----|--------|
| `h` / `<` | Previous period |
| `l` / `>` | Next period |
| `t` | Go to today |
| `a` | Agenda view |
| `d` | Daily view |
| `w` | Weekly view |
| `m` | Monthly view |
| `y` | Yearly view |
| `r` | Refresh |
| `T` | Toggle tasks |
| `n` / `e` | New event |
| `N` | New task |
| `q` | Close |

### Event/Task Form

| Key | Action |
|-----|--------|
| `j` / `k` | Navigate fields |
| `Enter` | Edit field |
| `Tab` | Cycle options / Next field |
| `S` / `Ctrl+S` | Save |
| `q` / `Esc` | Cancel |

### Description Field (Multiline)

| Key | Action |
|-----|--------|
| `Enter` | New line |
| `Ctrl+S` | Save description |
| `Esc` | Cancel |

## Configuration

```lua
opts = {
  -- Calendar sources
  calendars = {
    { name = "Work", path = "~/calendars/work.ics", color = "#FFD700" },
    { name = "Personal", path = "~/calendars/personal/", color = "#87CEEB" },
    { name = "Shared", path = "~/repos/calendar", color = "#98FB98", recursive = true },
  },

  -- Display options
  display = {
    days_ahead = 14,
    show_tasks = true,
    show_completed_tasks = false,
    date_format = "%a %b %d",
    time_format = "%H:%M",
  },

  -- Icons
  icons = {
    event = "",
    task = "☐",
    task_done = "☑",
    recurring = "↻",
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
