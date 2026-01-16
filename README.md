# ical.nvim

A Neovim plugin for viewing and managing calendar events and tasks from local iCal (.ics/.ical) files.

## Features

- **Multiple calendar sources**: Load from single files, directories, or git repos with recursive scanning
- **Multiple views**: Agenda (list), Daily, Weekly, Monthly, Yearly
- **Task management**: View and create VTODO items with due dates and priorities
- **Recurring events**: Full RRULE support for repeating events
- **Create events/tasks**: Popup form for creating new calendar items
- **Tab-based UI**: Opens in a dedicated tab with tasks sidebar

Perfect for viewing calendars from:
- Local git repositories syncing calendar data
- Exported .ics files from Google Calendar, Outlook, etc.
- CalDAV synced directories (vdirsyncer, khal, etc.)

## Requirements

- Neovim >= 0.8.0
- Optional: [calendar.vim](https://github.com/itchyny/calendar.vim) for visual calendar integration

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/ical.nvim",
  keys = {
    { "<leader>ca", "<cmd>IcalAgenda<cr>", desc = "iCal Agenda" },
    { "<leader>ce", "<cmd>IcalNewEvent<cr>", desc = "New Event" },
    { "<leader>ct", "<cmd>IcalNewTask<cr>", desc = "New Task" },
  },
  opts = {
    calendars = {
      { name = "Personal", path = "~/calendars/personal", color = "#87CEEB" },
      { name = "Work", path = "~/calendars/work", color = "#FFD700" },
    },
  },
}
```

## Configuration

```lua
require("ical").setup({
  -- Calendar sources (directories or files containing .ics/.ical)
  calendars = {
    { name = "Personal", path = "~/calendars/personal", color = "#87CEEB" },
    { name = "Work", path = "~/calendars/work", color = "#FFD700", recursive = true },
  },

  -- Display options
  display = {
    days_ahead = 14,
    show_tasks = true,
    show_completed_tasks = false,
    date_format = "%a %b %d",
    time_format = "%H:%M",
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:IcalAgenda [view]` | Open agenda (view: agenda/daily/weekly/monthly/yearly) |
| `:IcalDaily` | Open daily view |
| `:IcalWeekly` | Open weekly view |
| `:IcalMonthly` | Open monthly view |
| `:IcalYearly` | Open yearly view |
| `:IcalNewEvent` | Create a new event |
| `:IcalNewTask` | Create a new task |
| `:IcalAddCalendar <path> [name] [--recursive]` | Add a calendar source |
| `:IcalRemoveCalendar <name>` | Remove a calendar source |
| `:IcalListCalendars` | List configured calendars |

## Keymaps (in agenda view)

| Key | Action |
|-----|--------|
| `h` / `<` | Navigate previous |
| `l` / `>` | Navigate next |
| `t` | Go to today |
| `a/d/w/m/y` | Switch view mode |
| `n` / `e` | New event |
| `N` | New task |
| `T` | Toggle tasks |
| `q` | Close |

## License

MIT
