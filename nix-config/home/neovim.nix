{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    # Essential plugins for a good experience
    plugins = with pkgs.vimPlugins; [
      # File explorer
      nvim-tree-lua
      nvim-web-devicons  # for file icons

      # Visual enhancements
      vim-nix  # Nix syntax highlighting
      vim-devicons
      indent-blankline-nvim  # Show indentation guides
      lualine-nvim  # Status line
      nvim-colorizer-lua  # Color highlighter

      # Quality of life improvements
      vim-sensible  # Sensible defaults
      vim-commentary  # Easy commenting
      vim-surround  # Handle surroundings
      vim-repeat  # Better repeat
      vim-unimpaired  # Handy bracket mappings
      vim-fugitive  # Git integration
      vim-airline  # Status bar
      vim-airline-themes

      # Autocompletion
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline
      luasnip  # Snippets
      friendly-snippets
    ];

    # Basic configuration
    extraConfig = ''
      " Set leader key to space
      let mapleader = " "

      " Enable mouse support
      set mouse=a

      " Line numbers
      set number
      set relativenumber

      " Tab settings
      set tabstop=2
      set shiftwidth=2
      set expandtab
      set smartindent

      " Search settings
      set ignorecase
      set smartcase
      set hlsearch
      set incsearch

      " Better splitting
      set splitbelow
      set splitright

      " Persistent undo
      set undofile
      set undodir=~/.vim/undodir

      " Enable true colors
      set termguicolors

      " Enable hidden buffers
      set hidden

      " Enable clipboard
      set clipboard+=unnamedplus

      " Basic key mappings
      nnoremap <leader>h :wincmd h<CR>
      nnoremap <leader>j :wincmd j<CR>
      nnoremap <leader>k :wincmd k<CR>
      nnoremap <leader>l :wincmd l<CR>
      nnoremap <leader>pv :NvimTreeToggle<CR>
      nnoremap <leader>ff :NvimTreeFindFile<CR>
      nnoremap <silent> <leader>+ :vertical resize +5<CR>
      nnoremap <silent> <leader>- :vertical resize -5<CR>

      " Clear search highlights
      nnoremap <silent> <leader>nh :nohl<CR>

      " Better window navigation
      tnoremap <Esc> <C-\><C-n>
      tnoremap <C-h> <C-\><C-n><C-w>h
      tnoremap <C-j> <C-\><C-n><C-w>j
      tnoremap <C-k> <C-\><C-n><C-w>k
      tnoremap <C-l> <C-\><C-n><C-w>l

      " Plugin setup
      lua << EOF
      -- Set up nvim-tree
      require'nvim-tree'.setup {
        view = {
          width = 30,
        },
        renderer = {
          icons = {
            glyphs = {
              default = "",
              symlink = "",
            },
          },
        },
      }

      -- Set up lualine
      require('lualine').setup {
        options = {
          theme = 'auto',
        },
      }

      -- Set up colorizer
      require('colorizer').setup()

      -- Set up indent blankline
      require("indent_blankline").setup {
        show_current_context = true,
      }

      -- Set up completion
      local cmp = require'cmp'
      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
        }, {
          { name = 'buffer' },
          { name = 'path' },
        })
      })
      EOF
    '';
  };

  # Additional dependencies
  home.packages = with pkgs; [
    # Language servers
    nil  # Nix LSP
    nodePackages.bash-language-server
    nodePackages.vscode-langservers-extracted  # HTML, CSS, JSON
    nodePackages.typescript-language-server

    # Tools
    ripgrep  # Better grep
    fd  # Better find
    tree-sitter  # Better syntax highlighting
  ];
}