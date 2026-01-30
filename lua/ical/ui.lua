-- Tab-based UI for ical agenda view
local utils = require("ical.utils")

local M = {}

-- UI state
local state = {
  main_buf = nil,
  main_win = nil,
  desc_buf = nil,
  desc_win = nil,
  tasks_buf = nil,
  tasks_win = nil,
  tab = nil,
  events = {},
  tasks = {},
  show_tasks = true,
  -- Current view date (center of the view)
  view_date = nil,
  -- Callback for window resize
  on_resize_callback = nil,
  -- Line to item mapping for main buffer (line_num -> {type="event"|"task", item=...})
  line_items = {},
  -- Line to item mapping for tasks buffer
  tasks_line_items = {},
}

--- Check if window is open
---@return boolean
function M.is_open()
  return state.main_win ~= nil and vim.api.nvim_win_is_valid(state.main_win)
end

--- Toggle task visibility
function M.toggle_tasks()
  state.show_tasks = not state.show_tasks
end

--- Get current task visibility
---@return boolean
function M.get_show_tasks()
  return state.show_tasks
end

--- Get view date
---@return number timestamp
function M.get_view_date()
  return state.view_date or os.time()
end

--- Set view date
---@param timestamp number
function M.set_view_date(timestamp)
  state.view_date = timestamp
end

--- Set callback for window resize
---@param callback function
function M.set_resize_callback(callback)
  state.on_resize_callback = callback
end

--- Get item at current cursor position
---@return table|nil item The event or task at cursor, or nil
---@return string|nil type "event" or "task"
function M.get_item_at_cursor()
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line_num = cursor[1]

  -- Check if in tasks buffer
  if win == state.tasks_win and state.tasks_line_items[line_num] then
    local item_info = state.tasks_line_items[line_num]
    return item_info.item, item_info.type
  end

  -- Check if in main buffer
  if win == state.main_win and state.line_items[line_num] then
    local item_info = state.line_items[line_num]
    return item_info.item, item_info.type
  end

  return nil, nil
end

--- Open the description preview pane below the main window (20% height)
local function open_desc_pane()
  if state.desc_win and vim.api.nvim_win_is_valid(state.desc_win) then
    return state.desc_buf, state.desc_win
  end

  -- Must be called while main_win is focused
  if not state.main_win or not vim.api.nvim_win_is_valid(state.main_win) then
    return nil, nil
  end

  vim.api.nvim_set_current_win(state.main_win)

  -- Create description buffer
  state.desc_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.desc_buf].buftype = "nofile"
  vim.bo[state.desc_buf].bufhidden = "wipe"
  vim.bo[state.desc_buf].swapfile = false
  vim.bo[state.desc_buf].filetype = "ical-desc"

  -- Horizontal split below
  vim.cmd("belowright split")
  state.desc_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.desc_win, state.desc_buf)

  -- Set height to 20% of total editor height
  local desc_height = math.max(math.floor(vim.o.lines * 0.2), 3)
  vim.api.nvim_win_set_height(state.desc_win, desc_height)

  -- Window settings
  vim.wo[state.desc_win].wrap = true
  vim.wo[state.desc_win].cursorline = false
  vim.wo[state.desc_win].number = false
  vim.wo[state.desc_win].relativenumber = false
  vim.wo[state.desc_win].signcolumn = "no"
  vim.wo[state.desc_win].winfixheight = true
  vim.wo[state.desc_win].list = false

  -- Go back to main window
  vim.api.nvim_set_current_win(state.main_win)

  return state.desc_buf, state.desc_win
end

--- Close description pane
local function close_desc_pane()
  if state.desc_win and vim.api.nvim_win_is_valid(state.desc_win) then
    vim.api.nvim_win_close(state.desc_win, true)
  end
  state.desc_win = nil
  state.desc_buf = nil
end

--- Create the tab-based UI
---@param opts table Window options
function M.open_window(opts)
  -- Close existing if open
  M.close_window()

  -- Initialize view date to today if not set
  if not state.view_date then
    state.view_date = utils.start_of_day(os.time())
  end

  -- Create new tab
  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()

  -- Create main buffer
  state.main_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.main_buf].buftype = "nofile"
  vim.bo[state.main_buf].bufhidden = "wipe"
  vim.bo[state.main_buf].swapfile = false
  vim.bo[state.main_buf].filetype = "ical"

  -- Set the buffer in current window
  state.main_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.main_win, state.main_buf)

  -- Window settings
  vim.wo[state.main_win].wrap = false
  vim.wo[state.main_win].cursorline = true
  vim.wo[state.main_win].number = false
  vim.wo[state.main_win].relativenumber = false
  vim.wo[state.main_win].signcolumn = "no"
  vim.wo[state.main_win].foldcolumn = "0"
  vim.wo[state.main_win].list = false
  vim.wo[state.main_win].statusline = " q:close  r:refresh  t:today  </>:nav  n:event  N:task  x:done  d:delete  Enter:edit"

  -- Set tab label
  vim.api.nvim_buf_set_name(state.main_buf, "iCal Agenda")

  -- Create description pane (20% height, below main)
  open_desc_pane()

  -- Create tasks sidebar if enabled
  if state.show_tasks then
    M.open_tasks_sidebar()
  end

  -- Setup resize handler to re-render on window resize
  local augroup = vim.api.nvim_create_augroup("IcalResize", { clear = true })
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
      if M.is_open() then
        vim.schedule(function()
          -- Re-adjust description pane height
          if state.desc_win and vim.api.nvim_win_is_valid(state.desc_win) then
            local desc_height = math.max(math.floor(vim.o.lines * 0.2), 3)
            vim.api.nvim_win_set_height(state.desc_win, desc_height)
          end
          if state.on_resize_callback then
            state.on_resize_callback()
          end
        end)
      end
    end,
  })

  return state.main_buf, state.main_win
end

--- Open or refresh tasks sidebar (1/3 of screen width)
function M.open_tasks_sidebar()
  if state.tasks_win and vim.api.nvim_win_is_valid(state.tasks_win) then
    -- Update width to 1/3 on refresh
    local tasks_width = math.floor(vim.o.columns / 3)
    vim.api.nvim_win_set_width(state.tasks_win, tasks_width)
    return state.tasks_buf, state.tasks_win
  end

  -- Create tasks buffer
  state.tasks_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.tasks_buf].buftype = "nofile"
  vim.bo[state.tasks_buf].bufhidden = "wipe"
  vim.bo[state.tasks_buf].swapfile = false
  vim.bo[state.tasks_buf].filetype = "ical-tasks"

  -- Focus main window first so the split is in the right place
  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    vim.api.nvim_set_current_win(state.main_win)
  end

  -- Create vertical split on the right
  vim.cmd("vsplit")
  vim.cmd("wincmd L")
  state.tasks_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.tasks_win, state.tasks_buf)

  -- Set width to 1/3 of screen
  local tasks_width = math.floor(vim.o.columns / 3)
  vim.api.nvim_win_set_width(state.tasks_win, tasks_width)

  -- Window settings
  vim.wo[state.tasks_win].wrap = true
  vim.wo[state.tasks_win].cursorline = true
  vim.wo[state.tasks_win].number = false
  vim.wo[state.tasks_win].relativenumber = false
  vim.wo[state.tasks_win].signcolumn = "no"
  vim.wo[state.tasks_win].winfixwidth = true
  vim.wo[state.tasks_win].list = false

  -- Go back to main window
  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    vim.api.nvim_set_current_win(state.main_win)
  end

  return state.tasks_buf, state.tasks_win
end

--- Close tasks sidebar
function M.close_tasks_sidebar()
  if state.tasks_win and vim.api.nvim_win_is_valid(state.tasks_win) then
    vim.api.nvim_win_close(state.tasks_win, true)
  end
  state.tasks_win = nil
  state.tasks_buf = nil
end

--- Close the agenda window
function M.close_window()
  M.close_tasks_sidebar()
  close_desc_pane()
  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    -- Close the tab
    local current_tab = vim.api.nvim_get_current_tabpage()
    if state.tab and state.tab == current_tab then
      -- Only close if there are other tabs
      if #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd("tabclose")
      else
        vim.api.nvim_win_close(state.main_win, true)
      end
    else
      vim.api.nvim_win_close(state.main_win, true)
    end
  end
  state.main_win = nil
  state.main_buf = nil
  state.tab = nil
end

--- Generate header line
---@param view_date number Current view date timestamp
---@param width number Available width
---@return string header line
---@return table highlights Array of {col_start, col_end, hl_group}
local function generate_header(view_date, width)
  local highlights = {}

  local title = "Agenda"
  local date_str = os.date("%B %Y", view_date)
  local padding = width - #title - #date_str - 2
  if padding < 2 then
    padding = 2
  end

  local header = title .. string.rep(" ", padding) .. date_str
  table.insert(highlights, { 0, #title, "IcalAgendaTitle" })
  table.insert(highlights, { #title + padding, #header, "IcalAgendaDateHeader" })

  return header, highlights
end

--- Generate agenda view (list of upcoming events)
---@param events table[] Sorted events
---@param opts table Display options
---@param icons table Icon configuration
---@param width number Available width
---@return string[] lines
---@return table[] highlights
---@return table line_items Line to item mapping
local function render_agenda_view(events, opts, icons, width)
  local lines = {}
  local highlights = {}
  local line_items = {}

  if #events == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No upcoming events")
    return lines, highlights, line_items
  end

  local current_date = nil

  for _, event in ipairs(events) do
    local event_date = os.date("%Y-%m-%d", event.dtstart)

    -- Date header when date changes
    if opts.group_by_date and event_date ~= current_date then
      current_date = event_date
      table.insert(lines, "")

      local date_str = os.date(opts.date_format, event.dtstart)
      if utils.is_today(event.dtstart) then
        date_str = date_str .. " (Today)"
      end

      local line_num = #lines + 1
      table.insert(lines, date_str)
      table.insert(highlights, { line_num, 0, #date_str, "IcalAgendaDateHeader" })
    end

    -- Event line
    local time_str
    if event.all_day then
      time_str = icons.all_day .. " All day"
    else
      time_str = os.date(opts.time_format, event.dtstart)
    end

    local prefix = event.is_recurring and (icons.recurring .. " ") or "  "
    local event_line = prefix .. time_str .. "  " .. event.summary

    if event.location and event.location ~= "" then
      event_line = event_line .. " " .. icons.location .. " " .. event.location
    end

    -- Truncate if too long
    local max_width = width - 2
    if vim.fn.strdisplaywidth(event_line) > max_width then
      event_line = vim.fn.strcharpart(event_line, 0, max_width - 3) .. "..."
    end

    local line_num = #lines + 1
    table.insert(lines, event_line)
    line_items[line_num] = { type = "event", item = event }

    local time_end = #prefix + #time_str
    table.insert(highlights, { line_num, #prefix, time_end, "IcalAgendaEventTime" })
  end

  return lines, highlights, line_items
end

--- Map iCal STATUS to display label
---@param ical_status string
---@return string
local function display_status(ical_status)
  local map = {
    ["NEEDS-ACTION"] = "pending",
    ["IN-PROCESS"] = "overdue",
    ["COMPLETED"] = "complete",
  }
  return map[ical_status] or "pending"
end

--- Build a display line for a task
---@param task table Task data
---@param icons table Icon configuration
---@param indent string Leading whitespace
---@return string line
local function build_task_line(task, icons, indent)
  local checkbox = task.status == "COMPLETED" and icons.task_done or icons.task
  local line = indent .. checkbox .. " " .. task.summary
  -- Status badge
  local status_label = display_status(task.status)
  line = line .. " {" .. status_label .. "}"
  -- Tags
  if task.categories and #task.categories > 0 then
    for _, tag in ipairs(task.categories) do
      line = line .. " [" .. tag .. "]"
    end
  end
  return line
end

--- Render tasks into the sidebar buffer
---@param tasks table[] Array of tasks
---@param opts table Display options
---@param icons table Icon configuration
function M.render_tasks(tasks, opts, icons)
  if not state.tasks_buf or not vim.api.nvim_buf_is_valid(state.tasks_buf) then
    return
  end

  -- Get actual sidebar width
  local tasks_width = math.floor(vim.o.columns / 3)
  if state.tasks_win and vim.api.nvim_win_is_valid(state.tasks_win) then
    tasks_width = vim.api.nvim_win_get_width(state.tasks_win)
  end

  local lines = {}
  local highlights = {}
  local now = os.time()
  local separator = " " .. string.rep("─", tasks_width - 3)

  -- Reset tasks line items mapping
  state.tasks_line_items = {}

  -- Group tasks by date (declared early to avoid goto scope issues)
  local overdue_tasks = {}
  local today_tasks = {}
  local upcoming_tasks = {}
  local no_date_tasks = {}

  local today_start = utils.start_of_day(now)
  local today_end = utils.end_of_day(now)

  -- Header
  table.insert(lines, " Tasks")
  table.insert(highlights, { 1, 0, 6, "IcalAgendaTitle" })
  table.insert(lines, separator)
  table.insert(lines, "")

  if #tasks == 0 then
    table.insert(lines, " No tasks")
    goto write_buffer
  end

  for _, task in ipairs(tasks) do
    if task.status == "COMPLETED" and not opts.show_completed_tasks then
      goto continue
    end

    if not task.due then
      table.insert(no_date_tasks, task)
    elseif task.due < today_start and task.status ~= "COMPLETED" then
      table.insert(overdue_tasks, task)
    elseif task.due >= today_start and task.due <= today_end then
      table.insert(today_tasks, task)
    else
      table.insert(upcoming_tasks, task)
    end

    ::continue::
  end

  -- Overdue section
  if #overdue_tasks > 0 then
    table.insert(lines, " Overdue")
    table.insert(highlights, { #lines, 0, 8, "IcalAgendaOverdue" })

    for _, task in ipairs(overdue_tasks) do
      local line = build_task_line(task, icons, "  ")
      if task.due then
        line = line .. " (" .. os.date(opts.date_format, task.due) .. ")"
      end
      if vim.fn.strdisplaywidth(line) > tasks_width - 2 then
        line = vim.fn.strcharpart(line, 0, tasks_width - 5) .. "..."
      end
      local task_line_num = #lines + 1
      table.insert(lines, line)
      state.tasks_line_items[task_line_num] = { type = "task", item = task }
      table.insert(highlights, { task_line_num, 0, #line, "IcalAgendaOverdue" })
    end
    table.insert(lines, "")
  end

  -- Today section
  if #today_tasks > 0 then
    table.insert(lines, " Today")
    table.insert(highlights, { #lines, 0, 6, "IcalAgendaToday" })

    for _, task in ipairs(today_tasks) do
      local line = build_task_line(task, icons, "  ")
      if vim.fn.strdisplaywidth(line) > tasks_width - 2 then
        line = vim.fn.strcharpart(line, 0, tasks_width - 5) .. "..."
      end
      local task_line_num = #lines + 1
      table.insert(lines, line)
      state.tasks_line_items[task_line_num] = { type = "task", item = task }
      local hl = task.status == "COMPLETED" and "IcalAgendaTaskCompleted" or "IcalAgendaTaskPending"
      table.insert(highlights, { task_line_num, 0, #line, hl })
    end
    table.insert(lines, "")
  end

  -- Upcoming section
  if #upcoming_tasks > 0 then
    table.insert(lines, " Upcoming")
    table.insert(highlights, { #lines, 0, 9, "IcalAgendaDateHeader" })

    -- Group by date
    local by_date = {}
    for _, task in ipairs(upcoming_tasks) do
      local date_key = os.date("%Y-%m-%d", task.due)
      if not by_date[date_key] then
        by_date[date_key] = { date = task.due, tasks = {} }
      end
      table.insert(by_date[date_key].tasks, task)
    end

    -- Sort dates
    local sorted_dates = {}
    for k, v in pairs(by_date) do
      table.insert(sorted_dates, { key = k, data = v })
    end
    table.sort(sorted_dates, function(a, b)
      return a.data.date < b.data.date
    end)

    for _, date_entry in ipairs(sorted_dates) do
      local date_label = os.date(opts.date_format, date_entry.data.date)
      table.insert(lines, " " .. date_label)
      table.insert(highlights, { #lines, 0, #date_label + 1, "Comment" })

      for _, task in ipairs(date_entry.data.tasks) do
        local line = build_task_line(task, icons, "   ")
        if vim.fn.strdisplaywidth(line) > tasks_width - 2 then
          line = vim.fn.strcharpart(line, 0, tasks_width - 5) .. "..."
        end
        local task_line_num = #lines + 1
        table.insert(lines, line)
        state.tasks_line_items[task_line_num] = { type = "task", item = task }
        local hl = task.status == "COMPLETED" and "IcalAgendaTaskCompleted" or "IcalAgendaTaskPending"
        table.insert(highlights, { task_line_num, 0, #line, hl })
      end
    end
    table.insert(lines, "")
  end

  -- No date section
  if #no_date_tasks > 0 then
    table.insert(lines, " No Due Date")
    table.insert(highlights, { #lines, 0, 12, "Comment" })

    for _, task in ipairs(no_date_tasks) do
      local line = build_task_line(task, icons, "  ")
      if vim.fn.strdisplaywidth(line) > tasks_width - 2 then
        line = vim.fn.strcharpart(line, 0, tasks_width - 5) .. "..."
      end
      local task_line_num = #lines + 1
      table.insert(lines, line)
      state.tasks_line_items[task_line_num] = { type = "task", item = task }
      local hl = task.status == "COMPLETED" and "IcalAgendaTaskCompleted" or "IcalAgendaTaskPending"
      table.insert(highlights, { task_line_num, 0, #line, hl })
    end
  end

  ::write_buffer::

  -- Write to buffer
  vim.bo[state.tasks_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.tasks_buf, 0, -1, false, lines)
  vim.bo[state.tasks_buf].modifiable = false

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("ical-tasks")
  vim.api.nvim_buf_clear_namespace(state.tasks_buf, ns_id, 0, -1)

  for _, hl in ipairs(highlights) do
    local line, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    pcall(vim.api.nvim_buf_add_highlight, state.tasks_buf, ns_id, hl_group, line - 1, col_start, col_end)
  end
end

--- Update the description preview pane content
---@param description string|nil The description to display
local function update_description_preview(description)
  if not state.desc_buf or not vim.api.nvim_buf_is_valid(state.desc_buf) then
    return
  end

  local width = 60
  if state.desc_win and vim.api.nvim_win_is_valid(state.desc_win) then
    width = vim.api.nvim_win_get_width(state.desc_win)
  end

  local desc_lines = {}
  local desc_highlights = {}

  if description and description ~= "" then
    table.insert(desc_lines, "Description:")
    table.insert(desc_highlights, { 1, 0, 12, "IcalAgendaDateHeader" })

    -- Word-wrap the description
    for paragraph in (description .. "\n"):gmatch("([^\n]*)\n") do
      if paragraph == "" then
        table.insert(desc_lines, "")
      else
        local max_w = width - 4
        local current_line = "  "
        for word in paragraph:gmatch("%S+") do
          if #current_line + #word + 1 > max_w and current_line ~= "  " then
            table.insert(desc_lines, current_line)
            current_line = "  " .. word
          else
            if current_line == "  " then
              current_line = current_line .. word
            else
              current_line = current_line .. " " .. word
            end
          end
        end
        if current_line ~= "  " then
          table.insert(desc_lines, current_line)
        end
      end
    end
  else
    table.insert(desc_lines, "  (select an event to see its description)")
    table.insert(desc_highlights, { 1, 0, 43, "Comment" })
  end

  -- Write to description buffer
  vim.bo[state.desc_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.desc_buf, 0, -1, false, desc_lines)
  vim.bo[state.desc_buf].modifiable = false

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("ical-desc")
  vim.api.nvim_buf_clear_namespace(state.desc_buf, ns_id, 0, -1)
  for _, hl in ipairs(desc_highlights) do
    local line, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    pcall(vim.api.nvim_buf_add_highlight, state.desc_buf, ns_id, hl_group, line - 1, col_start, col_end)
  end
end

--- Render events and tasks into buffer
---@param events table[] Array of events (sorted)
---@param tasks table[] Array of tasks
---@param opts table Display options
---@param icons table Icon configuration
function M.render(events, tasks, opts, icons)
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end

  state.events = events
  state.tasks = tasks

  local width = vim.api.nvim_win_get_width(state.main_win)
  local view_date = state.view_date or os.time()

  local lines = {}
  local highlights = {}

  -- Generate header
  local header, header_hl = generate_header(view_date, width)
  table.insert(lines, header)
  for _, hl in ipairs(header_hl) do
    table.insert(highlights, { 1, hl[1], hl[2], hl[3] })
  end
  table.insert(lines, string.rep("═", width - 2))
  table.insert(lines, "")

  -- Render agenda view
  local content_lines, content_hl, content_line_items = render_agenda_view(events, opts, icons, width)

  -- Append content
  local line_offset = #lines
  for _, line in ipairs(content_lines) do
    table.insert(lines, line)
  end
  for _, hl in ipairs(content_hl) do
    table.insert(highlights, { hl[1] + line_offset, hl[2], hl[3], hl[4] })
  end

  -- Store line-to-item mapping (adjusted for line offset)
  state.line_items = {}
  for line_num, item_info in pairs(content_line_items or {}) do
    state.line_items[line_num + line_offset] = item_info
  end

  -- Write to buffer
  vim.bo[state.main_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
  vim.bo[state.main_buf].modifiable = false

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("ical")
  vim.api.nvim_buf_clear_namespace(state.main_buf, ns_id, 0, -1)

  for _, hl in ipairs(highlights) do
    local line, col_start, col_end, hl_group = hl[1], hl[2], hl[3], hl[4]
    pcall(vim.api.nvim_buf_add_highlight, state.main_buf, ns_id, hl_group, line - 1, col_start, col_end)
  end

  -- Ensure description pane exists
  if not state.desc_win or not vim.api.nvim_win_is_valid(state.desc_win) then
    open_desc_pane()
  end

  -- Initial description content
  update_description_preview(nil)

  -- Render tasks sidebar
  if state.show_tasks then
    if not state.tasks_win or not vim.api.nvim_win_is_valid(state.tasks_win) then
      M.open_tasks_sidebar()
    end
    M.render_tasks(tasks, opts, icons)
  else
    M.close_tasks_sidebar()
  end

  -- Setup CursorMoved autocmd for description preview + dynamic header
  local desc_augroup = vim.api.nvim_create_augroup("IcalDescPreview", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = desc_augroup,
    buffer = state.main_buf,
    callback = function()
      if not state.main_win or not vim.api.nvim_win_is_valid(state.main_win) then
        return
      end
      local cursor = vim.api.nvim_win_get_cursor(state.main_win)
      local cursor_line = cursor[1]
      local item_info = state.line_items[cursor_line]

      -- Update description preview
      if item_info and item_info.item then
        update_description_preview(item_info.item.description)
      else
        update_description_preview(nil)
      end

      -- Update header month/year based on selected item
      local header_date = state.view_date or os.time()
      if item_info and item_info.item and item_info.item.dtstart then
        header_date = item_info.item.dtstart
      end
      local cur_width = vim.api.nvim_win_get_width(state.main_win)
      local new_header, new_header_hl = generate_header(header_date, cur_width)
      vim.bo[state.main_buf].modifiable = true
      vim.api.nvim_buf_set_lines(state.main_buf, 0, 1, false, { new_header })
      vim.bo[state.main_buf].modifiable = false
      local ns_id = vim.api.nvim_create_namespace("ical-header")
      vim.api.nvim_buf_clear_namespace(state.main_buf, ns_id, 0, 1)
      for _, hl in ipairs(new_header_hl) do
        pcall(vim.api.nvim_buf_add_highlight, state.main_buf, ns_id, hl[3], 0, hl[1], hl[2])
      end
    end,
  })
end

--- Setup keymaps for the agenda buffer
---@param keymaps table Keymap configuration
---@param callbacks table Callback functions
function M.setup_keymaps(keymaps, callbacks)
  if not state.main_buf or not vim.api.nvim_buf_is_valid(state.main_buf) then
    return
  end

  local buf = state.main_buf

  -- Close keymaps
  local close_keys = type(keymaps.close) == "table" and keymaps.close or { keymaps.close }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, callbacks.close, { buffer = buf, silent = true, desc = "Close agenda" })
  end

  -- Navigation and actions
  vim.keymap.set("n", keymaps.refresh, callbacks.refresh, { buffer = buf, silent = true, desc = "Refresh agenda" })
  vim.keymap.set("n", keymaps.goto_today, callbacks.goto_today, { buffer = buf, silent = true, desc = "Go to today" })
  vim.keymap.set(
    "n",
    keymaps.toggle_tasks,
    callbacks.toggle_tasks,
    { buffer = buf, silent = true, desc = "Toggle tasks" }
  )
  vim.keymap.set(
    "n",
    keymaps.open_calendar,
    callbacks.open_calendar,
    { buffer = buf, silent = true, desc = "Open calendar.vim" }
  )

  -- Navigation keys
  vim.keymap.set("n", "<", callbacks.nav_prev, { buffer = buf, silent = true, desc = "Navigate previous" })
  vim.keymap.set("n", ">", callbacks.nav_next, { buffer = buf, silent = true, desc = "Navigate next" })
  vim.keymap.set("n", "h", callbacks.nav_prev, { buffer = buf, silent = true, desc = "Navigate previous" })
  vim.keymap.set("n", "l", callbacks.nav_next, { buffer = buf, silent = true, desc = "Navigate next" })

  -- Create new event/task keys
  if callbacks.new_event then
    vim.keymap.set("n", "n", callbacks.new_event, { buffer = buf, silent = true, desc = "New event" })
  end
  if callbacks.new_task then
    vim.keymap.set("n", "N", callbacks.new_task, { buffer = buf, silent = true, desc = "New task" })
  end

  -- Edit item on Enter
  if callbacks.edit_item then
    vim.keymap.set("n", "<CR>", callbacks.edit_item, { buffer = buf, silent = true, desc = "Edit item" })
  end

  -- Complete task
  if callbacks.complete_task then
    vim.keymap.set("n", "x", callbacks.complete_task, { buffer = buf, silent = true, desc = "Complete task" })
  end

  -- Delete item
  if callbacks.delete_item then
    vim.keymap.set("n", "d", callbacks.delete_item, { buffer = buf, silent = true, desc = "Delete item" })
  end

  -- Also set keymaps on tasks buffer if it exists
  if state.tasks_buf and vim.api.nvim_buf_is_valid(state.tasks_buf) then
    for _, key in ipairs(close_keys) do
      vim.keymap.set("n", key, callbacks.close, { buffer = state.tasks_buf, silent = true, desc = "Close agenda" })
    end
    if callbacks.edit_item then
      vim.keymap.set(
        "n",
        "<CR>",
        callbacks.edit_item,
        { buffer = state.tasks_buf, silent = true, desc = "Edit item" }
      )
    end
    if callbacks.complete_task then
      vim.keymap.set(
        "n",
        "x",
        callbacks.complete_task,
        { buffer = state.tasks_buf, silent = true, desc = "Complete task" }
      )
    end
    if callbacks.delete_item then
      vim.keymap.set(
        "n",
        "d",
        callbacks.delete_item,
        { buffer = state.tasks_buf, silent = true, desc = "Delete item" }
      )
    end
  end

  -- Set close keymaps on description buffer too
  if state.desc_buf and vim.api.nvim_buf_is_valid(state.desc_buf) then
    for _, key in ipairs(close_keys) do
      vim.keymap.set("n", key, callbacks.close, { buffer = state.desc_buf, silent = true, desc = "Close agenda" })
    end
  end
end

--- Create highlight groups
---@param highlights table Highlight configuration
function M.create_highlights(highlights)
  vim.api.nvim_set_hl(0, "IcalAgendaTitle", { link = highlights.date_header, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaDateHeader", { link = highlights.date_header, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaEventTime", { link = highlights.event_time, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaEventTitle", { link = highlights.event_title, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaEventLocation", { link = highlights.event_location, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaToday", { link = highlights.today, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaTaskPending", { link = highlights.task_pending, default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaTaskCompleted", { link = highlights.task_completed, default = true })
  -- Overdue tasks: bold + inherit color from overdue highlight
  local overdue_hl = vim.api.nvim_get_hl(0, { name = highlights.overdue, link = false })
  vim.api.nvim_set_hl(0, "IcalAgendaOverdue", {
    fg = overdue_hl.fg,
    bold = true,
    italic = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "IcalAgendaFooter", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaTagBracket", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "IcalAgendaTag", { link = "Special", default = true })
end

return M
