" lawrencium.vim - A Mercurial wrapper
" Maintainer:   Ludovic Chabant <http://ludovic.chabant.com>
" Version:      0.1

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

if !exists('g:lawrencium_trace')
    let g:lawrencium_trace = 0
endif

" }}}

" Utility {{{

" Strips the ending slash in a path.
function! s:stripslash(path)
    return fnamemodify(a:path, ':s?[/\\]$??')
endfunction

" Normalizes the slashes in a path.
function! s:normalizepath(path)
    if exists('+shellslash') && &shellslash
        return substitute(a:path, '\\', '/', '')
    elseif has('win32')
        return substitute(a:path, '/', '\\', '')
    else
        return a:path
    endif
endfunction

" Prints a message if debug tracing is enabled.
function! s:trace(message, ...)
   if g:lawrencium_trace || (a:0 && a:1)
       let l:message = "lawrencium: " . a:message
       echom l:message
   endif
endfunction

" Throw a Lawrencium exception message.
function! s:throw(message)
    let v:errmsg = "lawrencium: " . a:message
    throw v:errmsg
endfunction

" Finds the repository root given a path inside that repository.
" Throw an error if not repository is found.
function! s:find_repo_root(path)
    let l:path = s:stripslash(a:path)
    let l:previous_path = ""
    while l:path != l:previous_path
        if isdirectory(l:path . '/.hg/store')
            return simplify(fnamemodify(l:path, ':p'))
        endif
        let l:previous_path = l:path
        let l:path = fnamemodify(l:path, ':h')
    endwhile
    call s:throw("No Mercurial repository found above: " . a:path)
endfunction

" }}}

" Mercurial Repository {{{

" Let's define a Mercurial repo 'class' using prototype-based object-oriented
" programming.
"
" The prototype dictionary.
let s:HgRepo = {}

" Constructor
function! s:HgRepo.New(path) abort
    let l:newRepo = copy(self)
    let l:newRepo.root_dir = s:find_repo_root(a:path)
    call s:trace("Built new Mercurial repository object at : " . l:newRepo.root_dir)
    return l:newRepo
endfunction

" Gets a full path given a repo-relative path
function! s:HgRepo.GetFullPath(path) abort
    let l:root_dir = self.root_dir
    if a:path =~# '^[/\\]'
        let l:root_dir = s:stripslash(l:root_dir)
    endif
    return l:root_dir . a:path
endfunction

" Gets a list of files matching a root-relative pattern.
" If a flag is passed and is TRUE, a slash will be appended to all
" directories.
function! s:HgRepo.Glob(pattern, ...) abort
    let l:root_dir = self.root_dir
    if (a:pattern =~# '^[/\\]')
        let l:root_dir = s:stripslash(l:root_dir)
    endif
    let l:matches = split(glob(l:root_dir . a:pattern), '\n')
    if a:0 && a:1
        for l:idx in range(len(l:matches))
            if !filereadable(l:matches[l:idx])
                let l:matches[l:idx] = l:matches[l:idx] . '/'
            endif
        endfor
    endif
    let l:strip_len = len(l:root_dir)
    call map(l:matches, 'v:val[l:strip_len : -1]')
    return l:matches
endfunction

" Runs a Mercurial command in the repo
function! s:HgRepo.RunCommand(command, ...) abort
    let l:hg_command = g:lawrencium_hg_executable . ' --repository ' . shellescape(s:stripslash(self.root_dir))
    let l:hg_command = l:hg_command . ' ' . a:command . ' ' . join(a:000, ' ')
    call s:trace("Running Mercurial command: " . l:hg_command)
    return system(l:hg_command)
endfunction

" Repo cache map
let s:buffer_repos = {}

" Get a cached repo
function! s:hg_repo(...) abort
    " Use the given path, or the mercurial directory of the current buffer.
    if a:0 == 0
        if exists('b:mercurial_dir')
            let l:path = b:mercurial_dir
        else
            let l:path = s:find_repo_root(expand('%:p'))
        endif
    else
        let l:path = a:1
    endif
    " Find a cache repo instance, or make a new one.
    if has_key(s:buffer_repos, l:path)
        return get(s:buffer_repos, l:path)
    else
        let l:repo = s:HgRepo.New(l:path)
        let s:buffer_repos[l:path] = l:repo
        return l:repo
    endif
endfunction

" Sets up the current buffer with Lawrencium commands if it contains a file from a Mercurial repo.
" If the file is not in a Mercurial repo, just exit silently.
function! s:setup_buffer_commands() abort
    call s:trace("Scanning buffer '" . bufname('%') . "' for Lawrencium setup...")
    let l:do_setup = 1
    if exists('b:mercurial_dir')
        if b:mercurial_dir =~# '/^\s*$/'
            unlet b:mercurial_dir
        else
            let l:do_setup = 0
        endif
    endif
    try
        let l:repo = s:hg_repo()
    catch /^lawrencium\:/
        return
    endtry
    let b:mercurial_dir = l:repo.root_dir
    if exists('b:mercurial_dir') && l:do_setup
        call s:trace("Setting Mercurial commands for buffer '" . bufname('%'))
        call s:trace("  with repo : " . expand(b:mercurial_dir))
        silent doautocmd User Lawrencium
    endif
endfunction

augroup lawrencium_detect
    autocmd!
    autocmd BufNewFile,BufReadPost *     call s:setup_buffer_commands()
    autocmd VimEnter               *     if expand('<amatch>')==''|call s:setup_buffer_commands()|endif
augroup end

" }}}

" Main Buffer Commands {{{

" Store the commands for Lawrencium-enabled buffers so that we can add them in
" batch when we need to.
let s:main_commands = []

function! s:AddMainCommand(command) abort
    let s:main_commands += [a:command]
endfunction

function! s:DefineMainCommands()
    for l:command in s:main_commands
        execute 'command! -buffer ' . l:command
    endfor
endfunction

augroup lawrencium_main
    autocmd!
    autocmd User Lawrencium call s:DefineMainCommands()
augroup end

" Auto-complete function for commands that take repo-relative file paths.
function! s:ListRepoFiles(ArgLead, CmdLine, CursorPos) abort
    let l:matches = s:hg_repo().Glob(a:ArgLead . '*', 1)
    call map(l:matches, 's:normalizepath(v:val)')
    return l:matches
endfunction

" Auto-complete function for commands that take repo-relative directory paths.
function! s:ListRepoDirs(ArgLead, CmdLine, CursorPos) abort
    let l:matches = s:hg_repo().Glob(a:ArgLead . '*/')
    call map(l:matches, 's:normalizepath(v:val)')
    return l:matches
endfunction

" Hg {{{

function! s:Hg(bang, ...) abort
    let l:repo = s:hg_repo()
    let l:output = call(l:repo.RunCommand, a:000, l:repo)
    if a:bang
        " Open the output of the command in a temp file.
        let l:temp_file = tempname()
        execute 'pedit ' . l:temp_file
        wincmd p
        call append(0, l:output)
    else
        " Just print out the output of the command.
        echo l:output
    endif
endfunction

call s:AddMainCommand("-bang -nargs=* Hg :execute s:Hg(<bang>0, <f-args>)")

" }}}

" Hgstatus {{{

let s:hg_status_messages = { 
    \'M': 'modified',
    \'A': 'added',
    \'R': 'removed',
    \'C': 'clean',
    \'!': 'missing',
    \'?': 'not tracked',
    \'I': 'ignored',
    \}

function! s:HgStatus() abort
    " Get the repo and the `hg status` output.
    let l:repo = s:hg_repo()
    let l:status_text = l:repo.RunCommand('status')
    let l:status_lines = split(l:status_text, '\n')

    " Open a new temp buffer in the preview window, jump to it,
    " and paste the `hg status` output in there.
    " Also, make it a nice size, but restore the `previewheight` setting after
    " we're done.
    let l:temp_file = tempname()
    let l:temp_file = fnamemodify(l:temp_file, ':h') . 'hg-status-' . fnamemodify(l:temp_file, ':t') . '.txt'
    let l:preview_height = &previewheight
    execute "setlocal previewheight=" . (len(l:status_lines) + 1)
    execute "pedit " . l:temp_file
    wincmd p
    call append(0, l:status_lines)
    execute "setlocal previewheight=" . l:preview_height
    
    " Setup the buffer correctly: readonly, and with the correct repo linked
    " to it.
    let b:mercurial_dir = l:repo.root_dir
    setlocal buftype=nofile
    setlocal nomodified
    setlocal nomodifiable
    setlocal readonly
    setlocal syntax=hgstatus
    
    " Add some handy mappings.
    nnoremap <buffer> <silent> <C-N> :call search('^[MARC\!\?I ]\s.', 'We')<cr>
    nnoremap <buffer> <silent> <C-P> :call search('^[MARC\!\?I ]\s.','Wbe')<cr>
    nnoremap <buffer> <silent> <cr>  :execute <SID>HgStatus_FileEdit()<cr>
    nnoremap <buffer> <silent> q     :bdelete<cr>
endfunction

function! s:HgStatus_FileEdit() abort
    let l:repo = s:hg_repo()
    let l:line = getline('.')
    " Yay, awesome, Vim's regex syntax is fucked up like shit, especially for
    " look-aheads and look-behinds. See for yourself:
    let l:filename = matchstr(l:line, '\([MARC\!\?I ]\s\)\@<=.*')
    let l:filename = l:repo.GetFullPath(l:filename)
    " Go back to the previous window and open the file there, or open an
    " existing buffer.
    wincmd p
    if bufexists(l:filename)
        execute 'buffer ' . l:filename
    else
        execute 'edit ' . l:filename
    endif
endfunction

call s:AddMainCommand("Hgstatus :execute s:HgStatus()")

" }}}

" Hgcd, Hglcd {{{

call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hgcd :cd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")
call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hglcd :lcd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")

" }}}

" Hgedit {{{

call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoFiles Hgedit :edit<bang> `=s:hg_repo().GetFullPath(<q-args>)`")

" }}}

" Hgdiff {{{

function! s:HgDiff(filename, vertical, ...) abort
    " Default revisions to diff: the working directory (special Lawrencium 
    " hard-coded syntax) and the parent of the working directory (using 
    " Mercurial's revsets syntax).
    let l:rev1 = 'lawrencium#_wdir_'
    let l:rev2 = 'p1()'
    if a:0 == 1
        let l:rev2 = a:1
    elseif a:0 == 2
        let l:rev1 = a:1
        let l:rev2 = a:2
    endif

    " Get the current repo, and expand the given filename in case it contains
    " fancy filename modifiers.
    let l:repo = s:hg_repo()
    let l:path = expand(a:filename)
    call s:trace("Diff'ing '".l:rev1."' and '".l:rev2."' on file: ".l:path)

    " We'll keep a list of buffers in this diff, so when one exits, the
    " others' 'diff' flag is turned off.
    let l:diff_buffers = []

    " Get the first file and open it.
    if l:rev1 == 'lawrencium#_wdir_'
        if bufexists(l:path)
            execute 'buffer ' . fnameescape(l:path)
        else
            execute 'edit ' . fnameescape(l:path)
        endif
    else
        let l:temp_file = tempname()
        call l:repo.RunCommand('cat', '-r', '"'.l:rev1.'"', '-o', l:temp_file, l:path)
        execute 'edit ' . fnameescape(l:temp_file)
    endif
    " Set it up to be part of the diff windows, set its repo dir.
    diffthis
    let b:mercurial_dir = l:repo.root_dir

    " Get the second file and open it too.
    let l:diffsplit = 'diffsplit'
    if a:vertical
        let l:diffsplit = 'vertical diffsplit'
    endif
    if l:rev2 == 'lawrencium#_wdir_'
        execute l:diffsplit . ' ' . fnameescape(l:path)
    else
        let l:temp_file = tempname()
        call l:repo.RunCommand('cat', '-r', '"'.l:rev2.'"', '-o', l:temp_file, l:path)
        execute l:diffsplit . ' ' . fnameescape(l:temp_file)
    endif
    " Set its repo dir.
    let b:mercurial_dir = l:repo.root_dir
endfunction

call s:AddMainCommand("-nargs=* -complete=customlist,s:ListRepoFiles Hgdiff :execute s:HgDiff('%:p', 0, <f-args>)")
call s:AddMainCommand("-nargs=* -complete=customlist,s:ListRepoFiles Hgvdiff :execute s:HgDiff('%:p', 1, <f-args>)")

" }}}

" }}}

" Autoload Functions {{{

" Prints a summary of the current repo (if any) that's appropriate for
" displaying on the status line.
function! lawrencium#statusline(...)
    if !exists('b:mercurial_dir')
        return ''
    endif
    let l:prefix = (a:0 > 0 ? a:1 : '')
    let l:suffix = (a:0 > 1 ? a:2 : '')
    let l:branch_file = s:hg_repo().GetFullPath('.hg/branch')
    let l:branch = readfile(l:branch_file)[0]
    return l:prefix . l:branch .  l:suffix
endfunction

" Rescans the current buffer for setting up Mercurial commands.
" Passing '1' as the parameter enables debug traces temporarily.
function! lawrencium#rescan(...)
    if exists('b:mercurial_dir')
        unlet b:mercurial_dir
    endif
    if a:0 && a:1
        let l:trace_backup = g:lawrencium_trace
        let g:lawrencium_trace = 1
    endif
    call s:setup_buffer_commands()
    if a:0 && a:1
        let g:lawrencium_trace = l:trace_backup
    endif
endfunction

" Enables/disables the debug trace.
function! lawrencium#debugtrace(...)
    let g:lawrencium_trace = (a:0 == 0 || (a:0 && a:1))
    echom "Lawrencium debug trace is now " . (g:lawrencium_trace ? "enabled." : "disabled.")
endfunction

" }}}

