# Todoist.nvim

A comprehensive Neovim plugin that integrates Todoist with markdown editing, providing seamless bidirectional synchronization between your Todoist projects and markdown files.

## Features

- **🗂️ Project Management**: List and create Todoist projects directly from Neovim
- **📝 Markdown Rendering**: Convert Todoist projects to editable markdown format with proper hierarchy
- **🔄 Bidirectional Sync**: Automatically sync changes between markdown and Todoist
- **✅ Task Management**: Mark/unmark tasks with keyboard shortcuts and instant sync
- **⏰ Real-time Updates**: Auto-sync with configurable intervals
- **🎯 Extmark Tracking**: Uses Neovim's extmarks for precise change tracking
- **🔍 Debug Mode**: Comprehensive logging for troubleshooting
- **🌳 Hierarchical Tasks**: Support for subtasks with proper indentation
- **📋 Sections**: Organize tasks into sections with markdown headers

## Installation

### Prerequisites

- Neovim >= 0.7.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (required dependency)
- Internet connection for Todoist API access
- Valid Todoist API token

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "henrique-smr/todoist.nvim",
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

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "henrique-smr/todoist.nvim",
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

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'henrique-smr/todoist.nvim'

" Add to your init.vim or init.lua
lua << EOF
require("todoist").setup({
  api_token = "your_todoist_api_token",
  auto_sync = true,
  sync_interval = 30000,
  debug = false,
})
EOF
```

## Configuration

### Basic Configuration

```lua
require("todoist").setup({
  api_token = "your_api_token",    -- Required: Your Todoist API token
  auto_sync = true,                -- Auto-sync on buffer write and intervals
  sync_interval = 30000,           -- Auto-sync interval in milliseconds (30 seconds)
  debug = false,                   -- Enable debug logging
})
```

### Advanced Configuration

```lua
require("todoist").setup({
  api_token = os.getenv("TODOIST_API_TOKEN"), -- Use environment variable
  auto_sync = true,
  sync_interval = 60000, -- 1 minute
  debug = vim.fn.exists("$DEBUG") == 1, -- Enable debug if DEBUG env var is set
})
```

### Environment Variables

You can set your API token as an environment variable for security:

```bash
# Add to your .bashrc, .zshrc, etc.
export TODOIST_API_TOKEN="your_actual_api_token_here"
```

Then use it in your config:

```lua
require("todoist").setup({
  api_token = os.getenv("TODOIST_API_TOKEN"),
  -- ... other options
})
```

## Getting Your API Token

1. Go to [Todoist Integrations Settings](https://todoist.com/prefs/integrations)
2. Scroll down to the "API token" section
3. Copy your API token
4. Add it to your configuration (preferably as an environment variable)

**⚠️ Important**: Keep your API token secure and never commit it to version control!

## Usage

### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `:TodoistProjects` | List all Todoist projects in a selection menu | `:TodoistProjects` |
| `:TodoistCreateProject <name>` | Create a new project | `:TodoistCreateProject "Work Tasks"` |
| `:TodoistOpen <project_name>` | Open a project as markdown | `:TodoistOpen "Personal"` |
| `:TodoistSync` | Manually sync current buffer | `:TodoistSync` |
| `:TodoistToggle` | Toggle task completion on current line | `:TodoistToggle` |

### Key Mappings

#### Global Mappings
None by default. You can add your own:

```lua
vim.keymap.set('n', '<leader>tp', ':TodoistProjects<CR>', { desc = 'Todoist Projects' })
vim.keymap.set('n', '<leader>ts', ':TodoistSync<CR>', { desc = 'Sync Todoist' })
```

#### Todoist Buffer Mappings (automatic)
These are automatically set when you open a `.todoist.md` file:

| Key | Mode | Action |
|-----|------|--------|
| `<C-t>` | Normal, Insert | Toggle task completion |
| `<leader>ts` | Normal | Sync current buffer |

### Markdown Format

The plugin renders Todoist projects using this markdown structure:

```markdown
# Project Name

## Section Name

- [ ] Task content
  Task description goes here on the next line
  Multiple lines are supported
  
  - [ ] Subtask content
    Subtask description
    
    - [ ] Sub-subtask (nested)
    
- [x] Completed task
  This task is done

## Another Section

- [ ] Another task
  - [ ] Nested task in different section
```

### Workflow Examples

#### Basic Workflow

1. **List projects**: Use `:TodoistProjects` to see all your projects
2. **Select a project**: Choose from the list to open it as markdown
3. **Edit tasks**: 
   - Add new tasks: `- [ ] New task content`
   - Add descriptions: Write on the line below the task
   - Mark complete: Change `[ ]` to `[x]` or use `<C-t>`
   - Add sections: `## New Section Name`
4. **Save and sync**: Save the file (`:w`) to auto-sync with Todoist

#### Creating New Content

```markdown
# My Project

## Today's Tasks

- [ ] Review pull requests
  Check the main repository for any pending reviews
  
- [ ] Update documentation
  - [ ] Fix typos in README
  - [ ] Add examples to API docs
  
- [x] Morning standup
  Discussed current sprint progress

## Later This Week

- [ ] Plan next sprint
- [ ] Code review session
```

#### Working with Existing Projects

1. Open an existing project: `:TodoistOpen "Work"`
2. The markdown will show current state from Todoist
3. Edit as needed - add tasks, modify content, change completion status
4. Save to sync changes back to Todoist

### Advanced Features

#### Automatic Synchronization

- **On save**: Changes sync automatically when you save the buffer
- **Periodic**: Auto-sync every `sync_interval` milliseconds
- **Manual**: Use `:TodoistSync` anytime

#### Task Hierarchy

```markdown
- [ ] Parent task
  - [ ] Child task
    - [ ] Grandchild task
  - [ ] Another child task
```

#### Sections and Organization

```markdown
# Project Name

## Urgent
- [ ] Critical bug fix

## This Week  
- [ ] Feature development
- [ ] Code review

## Someday/Maybe
- [ ] Research new tools
```

## Troubleshooting

### Common Issues

#### "API token not provided"
**Solution**: Make sure to set your API token in the setup configuration:
```lua
require("todoist").setup({
  api_token = "your_actual_token_here"
})
```

#### "Not a Todoist buffer" 
**Cause**: Sync commands only work in buffers with `.todoist.md` extension  
**Solution**: Only use sync commands in project files opened via `:TodoistOpen`

#### Sync failures
**Possible causes**: 
- No internet connection
- Invalid/expired API token  
- Todoist API rate limits

**Solutions**:
- Check internet connection
- Verify API token at [Todoist integrations](https://todoist.com/prefs/integrations)
- Wait a moment and try again

#### Tasks not rendering
**Cause**: API response might contain `null` values  
**Solution**: Enable debug mode to see what data is received:
```lua
require("todoist").setup({
  debug = true,
  -- ... other options
})
```

#### Extmark errors
**Cause**: Buffer manipulation while extmarks are being set  
**Solution**: The plugin handles this automatically with `pcall` wrappers

### Debug Mode

Enable debug mode to see detailed logging:

```lua
require("todoist").setup({
  debug = true,
  -- ... other options
})
```

Debug output includes:
- API requests and responses
- Task processing steps  
- Markdown generation details
- Sync operations
- Extmark management

### Performance Tips

- **Large projects**: Consider splitting very large projects into smaller ones
- **Sync frequency**: Adjust `sync_interval` based on your needs (longer = less API calls)
- **Auto-sync**: Disable `auto_sync` if you prefer manual control

### File Locations

- Project files are stored in: `~/todoist/`
- File naming: `{project_name}.todoist.md`
- Directory is created automatically

## API Reference

### Setup Options

```lua
{
  api_token = string,        -- Required: Todoist API token
  auto_sync = boolean,       -- Default: true
  sync_interval = number,    -- Default: 30000 (30 seconds)  
  debug = boolean,           -- Default: false
}
```

### Public Functions

```lua
-- Get the main module
local todoist = require("todoist")

-- List all projects (opens selection UI)
todoist.list_projects()

-- Create a new project
todoist.create_project("Project Name")

-- Open a specific project
todoist.open_project("Project Name") 

-- Sync current buffer
todoist.sync_current_buffer()

-- Toggle task on current line
todoist.toggle_task()

-- Start/stop auto-sync
todoist.start_auto_sync()
todoist.stop_auto_sync()
```

## Contributing

We welcome contributions! Here's how to get started:

### Development Setup

1. **Fork and clone**:
```bash
git clone https://github.com/henrique-smr/todoist.nvim.git
cd todoist.nvim
```

2. **Install in development mode**:
```lua
-- In your Neovim config
vim.opt.rtp:prepend("~/path/to/todoist.nvim")
```

3. **Enable debug mode**:
```lua
require("todoist").setup({
  debug = true,
  api_token = "your_token"
})
```

### Making Changes

1. **Create a feature branch**: `git checkout -b feature/amazing-feature`
2. **Make your changes**: Follow the existing code style
3. **Test thoroughly**: Test with real Todoist data
4. **Add documentation**: Update README if needed
5. **Submit a pull request**: Describe your changes clearly

### Code Style

- Use 2 spaces for indentation
- Follow existing naming conventions
- Add comments for complex logic
- Use the centralized config module for all configuration access
- Always check for `vim.NIL` when handling API responses

### Testing

- Test with various project structures
- Test sync operations (create, update, delete)
- Test error conditions (network issues, invalid tokens)
- Test with empty projects and projects with many tasks

## License

MIT License

Copyright (c) 2025 henrique-smr

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Acknowledgments

- **Todoist**: For providing an excellent API
- **Neovim community**: For the amazing editor and Lua ecosystem
- **plenary.nvim**: For HTTP client functionality
- **Contributors**: Everyone who helps improve this plugin

## Changelog

### v1.0.0 (2025-05-29)
- Initial release
- Full Todoist API integration
- Bidirectional markdown sync
- Extmark-based change tracking
- Auto-sync functionality
- Hierarchical task support
- Section organization
- Comprehensive error handling
- Debug mode
- vim.NIL safety checks

## Support

- **Issues**: [GitHub Issues](https://github.com/henrique-smr/todoist.nvim/issues)
- **Discussions**: [GitHub Discussions](https://github.com/henrique-smr/todoist.nvim/discussions)
- **Wiki**: [Project Wiki](https://github.com/henrique-smr/todoist.nvim/wiki)

---

**Happy task management with Neovim! 🚀**
