# Todoist.nvim

A Neovim plugin that integrates Todoist with markdown editing, providing seamless synchronization between your Todoist projects and markdown files.

## Features

- **Project Management**: List and create Todoist projects directly from Neovim
- **Markdown Rendering**: Convert Todoist projects to editable markdown format
- **Bidirectional Sync**: Automatically sync changes between markdown and Todoist
- **Task Management**: Mark/unmark tasks with keyboard shortcuts
- **Real-time Updates**: Auto-sync with configurable intervals
- **Extmark Tracking**: Uses Neovim's extmarks for precise change tracking

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/todoist.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("todoist").setup({
      api_token = "your_todoist_api_token", -- Get from https://todoist.com/prefs/integrations
      auto_sync = true,
      sync_interval = 30000, -- 30 seconds
      debug = false,
    })
  end,
}
```
### Using packer.nvim

```lua
use {
  "your-username/todoist.nvim",
  requires = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("todoist").setup({
      api_token = "your_todoist_api_token",
      auto_sync = true,
      sync_interval = 30000,
      debug = false,
    })
  end,
}
```
## Configuration

```lua
require("todoist").setup({
  api_token = "your_api_token",    -- Required: Your Todoist API token
  auto_sync = true,                -- Auto-sync on buffer write
  sync_interval = 30000,           -- Auto-sync interval in milliseconds
  debug = false,                   -- Enable debug logging
})
```

## Usage
### Commands

    :TodoistProjects - List all Todoist projects
    :TodoistCreateProject <name> - Create a new project
    :TodoistOpen <project_name> - Open a project as markdown
    :TodoistSync - Manually sync current buffer
    :TodoistToggle - Toggle task completion

### Key Mappings (in Todoist buffers)

    <C-t> - Toggle task completion (Normal and Insert mode)
    <leader>ts - Sync current buffer

## Markdown Format

The plugin renders Todoist projects using the following markdown structure:
Markdown

```markdown

# Project Name

## Section Name

- [ ] Task content
  Task description goes here
  
  - [ ] Subtask content
    Subtask description
    
- [x] Completed task

## Another Section

- [ ] Another task
```

## Workflow

    Use :TodoistProjects to see available projects
    Select a project to open it as a markdown file
    Edit the markdown file:
        Add new tasks with - [ ] Task content
        Add new sections with ## Section Name
        Mark tasks complete with - [x] or use <C-t>
        Add task descriptions on the line below the task
    Save the file (:w) to auto-sync with Todoist
    Use :TodoistSync for manual sync

## API Token

    Go to Todoist Integrations
    Scroll down to "API token"
    Copy your token and add it to your configuration

## Requirements

    Neovim >= 0.7.0
    plenary.nvim
    Internet connection for Todoist API
    Valid Todoist API token

## Troubleshooting
### Common Issues
    "API token not provided": Make sure to set your API token in the setup configuration
    "Not a Todoist buffer": The sync commands only work in buffers with .todoist.md extension
    Sync failures: Check your internet connection and API token validity

### Debug Mode

Enable debug mode in your configuration to see detailed logging:

```lua
require("todoist").setup({
  debug = true,
  -- ... other options
})
```

## Contributing

    Fork the repository
    Create a feature branch
    Make your changes
    Add tests if applicable
    Submit a pull request

