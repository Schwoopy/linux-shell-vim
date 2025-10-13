
" >>> DEV_BOOTSTRAP_VIM_START >>>
" Managed by install_vimrc_etc.sh
execute pathogen#infect()
syntax on
filetype plugin indent on
set number
set norelativenumber
set tabstop=2 shiftwidth=2 expandtab
set cursorline
set termguicolors
set background=dark
silent! colorscheme shades_of_purple
let mapleader=","
let g:airline#extensions#tabline#enabled = 1
let g:airline_powerline_fonts = 1
nnoremap <leader>n :NERDTreeToggle<CR>
set rtp+=~/.fzf
nnoremap <C-p> :Files<CR>
let g:ale_sign_column_always = 1
let g:indentLine_char = '│'
" <<< DEV_BOOTSTRAP_VIM_END <<<
