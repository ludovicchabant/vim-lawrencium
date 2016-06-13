" lawrencium.vim - A Mercurial wrapper
" Maintainer:   Ludovic Chabant <http://ludovic.chabant.com>
" Version:      0.4.0


" Globals {{{

if !exists('g:lawrencium_debug')
    let g:lawrencium_debug = 0
endif

if (exists('g:loaded_lawrencium') || &cp) && !g:lawrencium_debug
    finish
endif
if (exists('g:loaded_lawrencium') && g:lawrencium_debug)
    echom "Reloaded Lawrencium."
endif
let g:loaded_lawrencium = 1

if !exists('g:lawrencium_hg_executable')
    let g:lawrencium_hg_executable = 'hg'
endif

if !exists('g:lawrencium_auto_cd')
    let g:lawrencium_auto_cd = 1
endif

if !exists('g:lawrencium_trace')
    let g:lawrencium_trace = 0
endif

if !exists('g:lawrencium_define_mappings')
    let g:lawrencium_define_mappings = 1
endif

if !exists('g:lawrencium_auto_close_buffers')
    let g:lawrencium_auto_close_buffers = 1
endif

if !exists('g:lawrencium_annotate_width_offset')
    let g:lawrencium_annotate_width_offset = 0
endif

if !exists('g:lawrencium_status_win_split_above')
    let g:lawrencium_status_win_split_above = 0
endif

if !exists('g:lawrencium_status_win_split_even')
    let g:lawrencium_status_win_split_even = 0
endif

if !exists('g:lawrencium_record_start_in_working_buffer')
    let g:lawrencium_record_start_in_working_buffer = 0
endif

if !exists('g:lawrencium_extensions')
    let g:lawrencium_extensions = []
endif

" }}}

" Setup {{{

call lawrencium#init()

augroup lawrencium_detect
    autocmd!
    autocmd BufNewFile,BufReadPost *     call lawrencium#setup_buffer_commands()
    autocmd VimEnter               *     if expand('<amatch>')==''|call lawrencium#setup_buffer_commands()|endif
augroup end

augroup lawrencium_files
    autocmd!
    autocmd BufReadCmd  lawrencium://**//**//* exe lawrencium#read_lawrencium_file(expand('<amatch>'))
    autocmd BufWriteCmd lawrencium://**//**//* exe lawrencium#write_lawrencium_file(expand('<amatch>'))
augroup END

" }}}

