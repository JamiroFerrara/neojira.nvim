# neojira.nvim

Jira integration inside Neovim. Browse, search, transition, comment, and log time on issues without leaving the editor.

## Features

- **Issue list** — fetch issues via JQL from the `jira` CLI, displayed in a formatted scratch buffer
- **Sort & filter** — toggle sort order (status / recently updated), toggle all assignees, toggle all statuses
- **Fast startup** — rendered list is cached to disk; cache is shown instantly and refreshed asynchronously
- **Issue detail** — `<cr>` on any row opens the full issue view (key, summary, status, assignee, priority, dates, labels, comments)
- **Browser open** — `o` opens the selected issue in your system browser
- **Commenting** — `c` opens a scratch buffer; write your comment and press `<cr>` to submit
- **Transitions** — `m` opens an interactive terminal to move / transition an issue
- **Time tracking** — `t` opens a per-day time log UI with preset durations; logged time is persisted locally and synced to Jira; `H`/`L` navigates days; `R` resets a day; `d` deletes one entry
- **Quick time log** — press `1`–`9` to log 1–9 hours on the issue under the cursor without opening the time UI
- **Pinning** — `F` toggles a favourite / pin on the selected issue; pinned issues always appear at the top of the list regardless of filters, styled with a distinct highlight
- **Search** — `/` opens a text search prompt; results appear in a scratch buffer where `<cr>` opens the detail view, `F` pins, `q` closes
- **Cached back navigation** — `<bs>`, `<C-o>`, `<M-o>` return to the previously cached task list after viewing a detail
- **Async refresh** — `r` / `<C-r>` re-fetches the issue list in the background

## Requirements

- Neovim >= 0.7.0
- [`jira` CLI](https://github.com/ankitpokhrel/jira-cli) installed and authenticated
- `JIRA_API_TOKEN` environment variable set (for REST API calls: worklog CRUD, search)
- `base64` utility (for REST API auth header)

## Installation

```lua
-- lazy.nvim
{
  'JamiroFerrara/neojira.nvim',
  event = 'VeryLazy',
  config = function()
    require('neojira').setup({
      browser = 'chrome.exe',
      company_name = 'novigo',
      username = 'Jamiro Ferrara',
    })
  end,
}
```

## Configuration

`setup()` accepts a table with these fields:

| Key             | Required | Default                | Description                     |
|-----------------|----------|------------------------|---------------------------------|
| `browser`       | yes      | —                      | Browser executable for opening issues |
| `company_name`  | yes      | —                      | Your Atlassian domain (subdomain) |
| `username`      | yes      | —                      | Your Jira display name (used for assignee filtering) |
| `email`         | no       | `j.ferrara@novigo-consulting.it` | Email for REST API Basic auth (paired with `JIRA_API_TOKEN`) |

## Usage

Run `:Neojira` (or `require('neojira').run()`) to open the issue list.

The JQL query defaults to issues assigned to you, ordered by status, excluding closed/resolved statuses.

### Keymaps (issue list buffer)

| Key | Action |
|-----|--------|
| `<cr>` | Open issue detail view |
| `o` | Open issue in browser |
| `c` | Add comment (opens scratch buffer, `<cr>` to submit) |
| `m` | Transition issue (opens terminal with `jira issue move`) |
| `t` | Open time log UI |
| `F` | Toggle pin / favourite |
| `/` | Search all issues by text |
| `r` / `<C-r>` | Refresh issue list (async) |
| `<bs>` / `<C-o>` / `<M-o>` | Return to cached task list |
| `<leader>q` | Close task list buffer |
| `1`–`9` | Quick-log N hours on the issue under cursor |
| `O` | Toggle sort order (status ↔ recently updated) |
| `a` | Toggle show all assignees (current user ↔ all) |
| `s` | Toggle show all statuses (filtered ↔ all) |

### Time log UI

Opened with `t` on an issue row.

| Key | Action |
|-----|--------|
| `<cr>` | Log selected preset duration (with optional comment) |
| `1`–`8` | Quick-select N hours with comment prompt |
| `d` | Delete selected entry (remote + local) |
| `R` | Reset all entries for the current day |
| `H` / `L` | Previous / next day |
| `q` | Close time log window |

## Architecture

```
plugin/neojira.lua       — runtimepath marker; :Neojira command created by setup()
lua/neojira/
  init.lua                — entry point, wires modules, exposes setup() and run()
  jira.lua                — JiraDataSource: all Jira CLI and REST API calls
  tasks.lua               — fetch, cache, display, and navigate the issue list
  display.lua             — scratch buffer creation, column formatting, keymap helpers
  comments.lua            — comment submission via scratch buffer
  time.lua                — worklog tracking: interactive UI and quick-log
  favs.lua                — pin/unpin issues with per-session persistence
  persist.lua             — namespaced JSON key-value store (~/.local/share/nvim/neojira/)
```

All feature modules receive their dependencies explicitly (`init.lua` injects them), making each unit testable in isolation.

## License

MIT
