#  नियोJira.nvim 🚀

A Neovim plugin to interact with Jira.

## ✨ Features

*   Open Jira issues in your browser.
*   View Jira issue details within Neovim.
*   ... and more to come!

## 📋 Requirements

*   Neovim >= 0.7.0

## 📦 Installation

Using `lazy.nvim`:

```lua
return {
  'JamiroFerrara/neojira.nvim',
  event = 'VeryLazy',
  config = function()
    require('neojira').setup({
      browser = 'chrome.exe',
      company_name = 'novigo',
      username = 'Jamiro Ferrara'
    })
    vim.keymap.set('n', '<leader>ji', '<cmd>lua require("neojira").run()<cr>', { noremap = true, silent = true })
  end,
}
```

## ⚙️ Configuration

You can configure the plugin by passing a table to the `setup` function.

Available options:

*   `browser`: The browser to open Jira issues in.
*   `company_name`: Your company's Jira domain name.
*   `username`: Your Jira username.

## 🚀 Usage

Run the `:lua require("neojira").run()` command to open the Jira issue corresponding to the current git branch.

## ⌨️ Keybindings

The plugin does not come with any default keybindings. You can set your own keybindings like this:

```lua
vim.keymap.set('n', '<leader>ji', '<cmd>lua require("neojira").run()<cr>', { noremap = true, silent = true })
```

## 💪 Contributing

Contributions are welcome! Please open an issue or a pull request.

## 📄 License

This plugin is licensed under the MIT License.
