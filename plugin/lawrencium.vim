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

if !exists('g:lawrencium_auto_cd')
    let g:lawrencium_auto_cd = 1
endif

if !exists('g:lawrencium_trace')
    let g:lawrencium_trace = 0
endif

if !exists('g:lawrencium_define_mappings')
    let g:lawrencium_define_mappings = 1
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

" Like tempname() but with some control over the filename.
function! s:tempname(name, ...)
    let l:path = tempname()
    let l:result = fnamemodify(l:path, ':h') . '/' . a:name . fnamemodify(l:path, ':t')
    if a:0 > 0
        let l:result = l:result . a:1
    endif
    return l:result
endfunction

" Delete a temporary file if it exists.
function! s:clean_tempfile(path)
    if filewritable(a:path)
        call s:trace("Cleaning up temporary file: " . a:path)
        call delete(a:path)
    endif
endfunction

" Prints a message if debug tracing is enabled.
function! s:trace(message, ...)
   if g:lawrencium_trace || (a:0 && a:1)
       let l:message = "lawrencium: " . a:message
       echom l:message
   endif
endfunction

" Prints an error message with 'lawrencium error' prefixed to it.
function! s:error(message)
    echom "lawrencium error: " . a:message
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

" Given a Lawrencium path (e.g: 'lawrencium:///repo/root_dir@foo/bar/file.py//34'), extract
" the repository root, relative file path and revision number/changeset ID.
function! s:parse_lawrencium_path(lawrencium_path)
    let l:repo_path = a:lawrencium_path
    if l:repo_path =~? '^lawrencium://'
        let l:repo_path = strpart(l:repo_path, strlen('lawrencium://'))
    endif

    let l:root_dir = ''
    let l:at_idx = stridx(l:repo_path, '@')
    if l:at_idx >= 0
        let l:root_dir = strpart(l:repo_path, 0, l:at_idx)
        let l:repo_path = strpart(l:repo_path, l:at_idx + 1)
    endif
    
    let l:rev = matchstr(l:repo_path, '\v//[0-9a-f]+$')
    if l:rev !=? ''
        let l:repo_path = strpart(l:repo_path, 0, strlen(l:repo_path) - strlen(l:rev))
        let l:rev = strpart(l:rev, 2)
    endif

    let l:result = { 'root': l:root_dir, 'path': l:repo_path, 'rev': l:rev }
    return l:result
endfunction

" }}}

" Mercurial Repository {{{

" Let's define a Mercurial repo 'class' using prototype-based object-oriented
" programming.
"
" The prototype dictionary.
let s:HgRepo = {}

" Constructor.
function! s:HgRepo.New(path) abort
    let l:newRepo = copy(self)
    let l:newRepo.root_dir = s:find_repo_root(a:path)
    call s:trace("Built new Mercurial repository object at : " . l:newRepo.root_dir)
    return l:newRepo
endfunction

" Gets a full path given a repo-relative path.
function! s:HgRepo.GetFullPath(path) abort
    let l:root_dir = self.root_dir
    if a:path =~# '\v^[/\\]'
        let l:root_dir = s:stripslash(l:root_dir)
    endif
    return l:root_dir . a:path
endfunction

" Gets a list of files matching a root-relative pattern.
" If a flag is passed and is TRUE, a slash will be appended to all
" directories.
function! s:HgRepo.Glob(pattern, ...) abort
    let l:root_dir = self.root_dir
    if (a:pattern =~# '\v^[/\\]')
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

" Gets a full Mercurial command.
function! s:HgRepo.GetCommand(command, ...) abort
    " If there's only one argument, and it's a list, then use that as the
    " argument list.
    let l:arg_list = a:000
    if a:0 == 1 && type(a:1) == type([])
        let l:arg_list = a:1
    endif
    let l:hg_command = g:lawrencium_hg_executable . ' --repository ' . shellescape(s:stripslash(self.root_dir))
    let l:hg_command = l:hg_command . ' ' . a:command . ' ' . join(l:arg_list, ' ')
    return l:hg_command
endfunction

" Runs a Mercurial command in the repo.
function! s:HgRepo.RunCommand(command, ...) abort
    let l:all_args = [a:command] + a:000
    let l:hg_command = call(self['GetCommand'], l:all_args, self)
    call s:trace("Running Mercurial command: " . l:hg_command)
    return system(l:hg_command)
endfunction

" Repo cache map.
let s:buffer_repos = {}

" Get a cached repo.
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
        if b:mercurial_dir =~# '\v^\s*$'
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

" Buffer Commands Management {{{

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

" }}}

" Commands Auto-Complete {{{

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

" }}}

" Hg {{{

function! s:Hg(bang, ...) abort
    let l:repo = s:hg_repo()
    if g:lawrencium_auto_cd
        " Temporary set the current directory to the root of the repo
        " to make auto-completed paths work magically.
        execute 'cd! ' . l:repo.root_dir
    endif
    let l:output = call(l:repo.RunCommand, a:000, l:repo)
    if g:lawrencium_auto_cd
        execute 'cd! -'
    endif
    if a:bang
        " Open the output of the command in a temp file.
        let l:temp_file = s:tempname('hg-output-', '.txt')
        execute 'pedit ' . l:temp_file
        wincmd p
        call append(0, split(l:output, '\n'))
    else
        " Just print out the output of the command.
        echo l:output
    endif
endfunction

" Include the generated HG usage file.
let s:usage_file = expand("<sfile>:h:h") . "/resources/hg_usage.vim"
if filereadable(s:usage_file)
    execute "source " . s:usage_file
else
    call s:error("Can't find the Mercurial usage file. Auto-completion will be disabled in Lawrencium.")
endif

function! s:CompleteHg(ArgLead, CmdLine, CursorPos)
    " Don't do anything if the usage file was not sourced.
    if !exists('g:lawrencium_hg_commands') || !exists('g:lawrencium_hg_options')
        return []
    endif

    " a:ArgLead seems to be the number 0 when completing a minus '-'.
    " Gotta find out why...
    let l:arglead = a:ArgLead
    if type(a:ArgLead) == type(0)
        let l:arglead = '-'
    endif

    " Try completing a global option, before any command name.
    if a:CmdLine =~# '\v^Hg(\s+\-[a-zA-Z0-9\-_]*)+$'
        return filter(copy(g:lawrencium_hg_options), "v:val[0:strlen(l:arglead)-1] ==# l:arglead")
    endif

    " Try completing a command (note that there could be global options before
    " the command name).
    if a:CmdLine =~# '\v^Hg\s+(\-[a-zA-Z0-9\-_]+\s+)*[a-zA-Z]+$'
        echom " - matched command"
        return filter(keys(g:lawrencium_hg_commands), "v:val[0:strlen(l:arglead)-1] ==# l:arglead")
    endif
    
    " Try completing a command's options.
    let l:cmd = matchstr(a:CmdLine, '\v(^Hg\s+(\-[a-zA-Z0-9\-_]+\s+)*)@<=[a-zA-Z]+')
    if strlen(l:cmd) > 0
        echom " - matched command option for " . l:cmd . " with : " . l:arglead
    endif
    if strlen(l:cmd) > 0 && l:arglead[0] ==# '-'
        if has_key(g:lawrencium_hg_commands, l:cmd)
            " Return both command options and global options together.
            let l:copts = filter(copy(g:lawrencium_hg_commands[l:cmd]), "v:val[0:strlen(l:arglead)-1] ==# l:arglead")
            let l:gopts = filter(copy(g:lawrencium_hg_options), "v:val[0:strlen(l:arglead)-1] ==# l:arglead")
            return l:copts + l:gopts
        endif
    endif
    
    " Just auto-complete with filenames unless it's an option.
    if l:arglead[0] ==# '-'
        return []
    else
        return s:ListRepoFiles(a:ArgLead, a:CmdLine, a:CursorPos)
endfunction

call s:AddMainCommand("-bang -complete=customlist,s:CompleteHg -nargs=* Hg :call s:Hg(<bang>0, <f-args>)")

" }}}

" Hgstatus {{{

function! s:HgStatus() abort
    " Get the repo and the `hg status` output.
    let l:repo = s:hg_repo()
    let l:status_text = l:repo.RunCommand('status')
    if l:status_text ==# '\v%^\s*%$'
        echo "Nothing modified."
    endif

    " Open a new temp buffer in the preview window, jump to it,
    " and paste the `hg status` output in there.
    let l:temp_file = s:tempname('hg-status-', '.txt')
    let l:preview_height = &previewheight
    let l:status_lines = split(l:status_text, '\n')
    execute "setlocal previewheight=" . (len(l:status_lines) + 1)
    execute "pedit " . l:temp_file
    wincmd p
    call append(0, l:status_lines)
    call cursor(1, 1)
    " Make it a nice size. 
    execute "setlocal previewheight=" . l:preview_height
    " Make sure it's deleted when we exit the window.
    setlocal bufhidden=delete
    
    " Setup the buffer correctly: readonly, and with the correct repo linked
    " to it.
    let b:mercurial_dir = l:repo.root_dir
    setlocal buftype=nofile
    setlocal syntax=hgstatus

    " Make commands available.
    call s:DefineMainCommands()

    " Add some nice commands.
    command! -buffer          Hgstatusedit      :call s:HgStatus_FileEdit()
    command! -buffer          Hgstatusdiff      :call s:HgStatus_Diff(0)
    command! -buffer          Hgstatusvdiff     :call s:HgStatus_Diff(1)
    command! -buffer          Hgstatusrefresh   :call s:HgStatus_Refresh()
    command! -buffer -range   Hgstatusaddremove :call s:HgStatus_AddRemove(<line1>, <line2>)
    command! -buffer -range=% -bang Hgstatuscommit  :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 0)
    command! -buffer -range=% -bang Hgstatusvcommit :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 1)
    command! -buffer -range=% -nargs=+ Hgstatusqnew :call s:HgStatus_QNew(<line1>, <line2>, <f-args>)
    command! -buffer -range=% Hgstatusqrefresh      :call s:HgStatus_QRefresh(<line1>, <line2>)

    " Add some handy mappings.
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <cr>  :Hgstatusedit<cr>
        nnoremap <buffer> <silent> <C-N> :call search('^[MARC\!\?I ]\s.', 'We')<cr>
        nnoremap <buffer> <silent> <C-P> :call search('^[MARC\!\?I ]\s.', 'Wbe')<cr>
        nnoremap <buffer> <silent> <C-D> :Hgstatusdiff<cr>
        nnoremap <buffer> <silent> <C-V> :Hgstatusvdiff<cr>
        nnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        nnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
        nnoremap <buffer> <silent> <C-R> :Hgstatusrefresh<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>

        vnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        vnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
    endif

    " Make sure the file is deleted with the buffer.
    autocmd BufDelete <buffer> call s:clean_tempfile(expand('<afile>:p'))
endfunction

function! s:HgStatus_Refresh() abort
    " Get the repo and the `hg status` output.
    let l:repo = s:hg_repo()
    let l:status_text = l:repo.RunCommand('status')

    " Replace the contents of the current buffer with it, and refresh.
    echo "Writing to " . expand('%:p')
    let l:path = expand('%:p')
    let l:status_lines = split(l:status_text, '\n')
    call writefile(l:status_lines, l:path)
    edit
endfunction

function! s:HgStatus_FileEdit() abort
    " Get the path of the file the cursor is on.
    let l:filename = s:HgStatus_GetSelectedFile()
   
    " If the file is already open in a window, jump to that window.
    " Otherwise, jump to the previous window and open it there.
    for nr in range(1, winnr('$'))
        let l:br = winbufnr(nr)
        let l:bpath = fnamemodify(bufname(l:br), ':p')
        if l:bpath ==# l:filename
            execute nr . 'wincmd w'
            return
        endif
    endfor
    wincmd p
    execute 'edit ' . l:filename
endfunction

function! s:HgStatus_AddRemove(linestart, lineend) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['!', '?'])
    if len(l:filenames) == 0
        call s:error("No files to add or remove in selection or current line.")
    endif

    " Run `addremove` on those paths.
    let l:repo = s:hg_repo()
    call l:repo.RunCommand('addremove', l:filenames)

    " Refresh the status window.
    call s:HgStatus_Refresh()
endfunction

function! s:HgStatus_Commit(linestart, lineend, bang, vertical) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(l:filenames) == 0
        call s:error("No files to commit in selection or file.")
    endif

    " Run `Hgcommit` on those paths.
    call s:HgCommit(a:bang, a:vertical, l:filenames)
endfunction

function! s:HgStatus_Diff(vertical) abort
    " Open the file and run `Hgdiff` on it.
    call s:HgStatus_FileEdit()
    call s:HgDiff('%:p', a:vertical)
endfunction

function! s:HgStatus_QNew(linestart, lineend, patchname, ...) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(l:filenames) == 0
        call s:error("No files in selection or file to create patch.")
    endif

    " Run `Hg qnew` on those paths.
    let l:repo = s:hg_repo()
    call insert(l:filenames, a:patchname, 0)
    if a:0 > 0
        call insert(l:filenames, '-m', 0)
        let l:message = '"' . join(a:000, ' ') . '"'
        call insert(l:filenames, l:message, 1)
    endif
    call l:repo.RunCommand('qnew', l:filenames)
endfunction

function! s:HgStatus_QRefresh(linestart, lineend) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(l:filenames) == 0
        call s:error("No files in selection or file to refresh the patch.")
    endif

    " Run `Hg qrefresh` on those paths.
    let l:repo = s:hg_repo()
    call insert(l:filenames, '-s', 0)
    call l:repo.RunCommand('qrefresh', l:filenames)
endfunction


function! s:HgStatus_GetSelectedFile() abort
    let l:filenames = s:HgStatus_GetSelectedFiles()
    return l:filenames[0]
endfunction

function! s:HgStatus_GetSelectedFiles(...) abort
    if a:0 >= 2
        let l:lines = getline(a:1, a:2)
    else
        let l:lines = []
        call add(l:lines, getline('.'))
    endif
    let l:filenames = []
    let l:repo = s:hg_repo()
    for line in l:lines
        if a:0 >= 3
            let l:status = s:HgStatus_GetFileStatus(line)
            if index(a:3, l:status) < 0
                continue
            endif
        endif
        " Yay, awesome, Vim's regex syntax is fucked up like shit, especially for
        " look-aheads and look-behinds. See for yourself:
        let l:filename = matchstr(l:line, '\v(^[MARC\!\?I ]\s)@<=.*')
        let l:filename = l:repo.GetFullPath(l:filename)
        call add(l:filenames, l:filename)
    endfor
    return l:filenames
endfunction

function! s:HgStatus_GetFileStatus(...) abort
    let l:line = a:0 ? a:1 : getline('.')
    return matchstr(l:line, '\v^[MARC\!\?I ]')
endfunction

call s:AddMainCommand("Hgstatus :call s:HgStatus()")

" }}}

" Hgcd, Hglcd {{{

call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hgcd :cd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")
call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoDirs Hglcd :lcd<bang> `=s:hg_repo().GetFullPath(<q-args>)`")

" }}}

" Hgedit {{{

function! s:HgEdit(bang, filename) abort
    let l:full_path = s:hg_repo().GetFullPath(a:filename)
    if a:bang
        execute "edit! " . l:full_path
    else
        execute "edit " . l:full_path
    endif
endfunction

call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:ListRepoFiles Hgedit :call s:HgEdit(<bang>0, <f-args>)")

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
        " Make it part of the diff group.
        call s:HgDiff_DiffThis()
    else
        let l:temp_file = tempname()
        call l:repo.RunCommand('cat', '-r', '"'.l:rev1.'"', '-o', '"'.l:temp_file.'"', '"'.l:path.'"')
        execute 'edit ' . fnameescape(l:temp_file)
        " Make it part of the diff group.
        call s:HgDiff_DiffThis()
        " Remember the repo it belongs to.
        let b:mercurial_dir = l:repo.root_dir
        " Make sure it's deleted when we move away from it.
        setlocal bufhidden=delete
        " Make commands available.
        call s:DefineMainCommands()
    endif

    " Get the second file and open it too.
    let l:diffsplit = 'diffsplit'
    if a:vertical
        let l:diffsplit = 'vertical diffsplit'
    endif
    if l:rev2 == 'lawrencium#_wdir_'
        execute l:diffsplit . ' ' . fnameescape(l:path)
    else
        let l:temp_file = tempname()
        call l:repo.RunCommand('cat', '-r', '"'.l:rev2.'"', '-o', '"'.l:temp_file.'"', '"'.l:path.'"')
        execute l:diffsplit . ' ' . fnameescape(l:temp_file)
        " Remember the repo it belongs to.
        let b:mercurial_dir = l:repo.root_dir
        " Make sure it's deleted when we move away from it.
        setlocal bufhidden=delete
        " Make commands available.
        call s:DefineMainCommands()
    endif
endfunction

function! s:HgDiff_DiffThis() abort
    " Store some commands to run when we exit diff mode.
    " It's needed because `diffoff` reverts those settings to their default
    " values, instead of their previous ones.
    if !&diff
        call s:trace('Enabling diff mode on ' . bufname('%'))
        let w:lawrencium_diffoff = {}
        let w:lawrencium_diffoff['&diff'] = 0
        let w:lawrencium_diffoff['&wrap'] = &l:wrap
        let w:lawrencium_diffoff['&scrollopt'] = &l:scrollopt
        let w:lawrencium_diffoff['&scrollbind'] = &l:scrollbind
        let w:lawrencium_diffoff['&cursorbind'] = &l:cursorbind
        let w:lawrencium_diffoff['&foldmethod'] = &l:foldmethod
        let w:lawrencium_diffoff['&foldcolumn'] = &l:foldcolumn
        diffthis
    endif
endfunction

function! s:HgDiff_DiffOff(...) abort
    " Get the window name (given as a paramter, or current window).
    let l:nr = a:0 ? a:1 : winnr()

    " Run the commands we saved in `HgDiff_DiffThis`, or just run `diffoff`.
    let l:backup = getwinvar(l:nr, 'lawrencium_diffoff')
    if type(l:backup) == type({}) && len(l:backup) > 0
        call s:trace('Disabling diff mode on ' . l:nr)
        for key in keys(l:backup)
            call setwinvar(l:nr, key, l:backup[key])
        endfor
        call setwinvar(l:nr, 'lawrencium_diffoff', {})
    else
        call s:trace('Disabling diff mode on ' . l:nr . ' (but no true restore)')
        diffoff
    endif
endfunction

function! s:HgDiff_GetDiffWindows() abort
    let l:result = []
    for nr in range(1, winnr('$'))
        if getwinvar(nr, '&diff')
            call add(l:result, nr)
        endif
    endfor
    return l:result
endfunction

function! s:HgDiff_CleanUp() abort
    " If we're not leaving a diff window, do nothing.
    if !&diff
        return
    endif

    " If there will be only one diff window left (plus the one we're leaving),
    " turn off diff everywhere.
    let l:nrs = s:HgDiff_GetDiffWindows()
    if len(l:nrs) <= 2
        call s:trace('Disabling diff mode in ' . len(l:nrs) . ' windows.')
        for nr in l:nrs
            if getwinvar(nr, '&diff')
                call s:HgDiff_DiffOff(nr)
            endif
        endfor
    else
        call s:trace('Still ' . len(l:nrs) . ' diff windows open.')
    endif
endfunction

augroup lawrencium_diff
  autocmd!
  autocmd BufWinLeave * call s:HgDiff_CleanUp()
augroup end

call s:AddMainCommand("-nargs=* -complete=customlist,s:ListRepoFiles Hgdiff :call s:HgDiff('%:p', 0, <f-args>)")
call s:AddMainCommand("-nargs=* -complete=customlist,s:ListRepoFiles Hgvdiff :call s:HgDiff('%:p', 1, <f-args>)")

" }}}

" Hgcommit {{{

function! s:HgCommit(bang, vertical, ...) abort
    " Get the repo we'll be committing into.
    let l:repo = s:hg_repo()

    " Get the list of files to commit.
    " It can either be several files passed as extra parameters, or an
    " actual list passed as the first extra parameter.
    let l:filenames = []
    if a:0
        let l:filenames = a:000
        if a:0 == 1 && type(a:1) == type([])
            let l:filenames = a:1
        endif
    endif

    " Open a commit message file.
    let l:commit_path = s:tempname('hg-editor-', '.txt')
    let l:split = a:vertical ? 'vsplit' : 'split'
    execute l:split . ' ' . l:commit_path
    call append(0, ['', ''])
    call append(2, split(s:HgCommit_GenerateMessage(l:repo, l:filenames), '\n'))
    call cursor(1, 1)

    " Setup the auto-command that will actually commit on write/exit,
    " and make the buffer delete itself on exit.
    let b:mercurial_dir = l:repo.root_dir
    let b:lawrencium_commit_files = l:filenames
    setlocal bufhidden=delete
    setlocal syntax=hgcommit
    if a:bang
        autocmd BufDelete <buffer> call s:HgCommit_Execute(expand('<afile>:p'), 0)
    else
        autocmd BufDelete <buffer> call s:HgCommit_Execute(expand('<afile>:p'), 1)
    endif
    " Make commands available.
    call s:DefineMainCommands()
endfunction

let s:hg_status_messages = { 
    \'M': 'modified',
    \'A': 'added',
    \'R': 'removed',
    \'C': 'clean',
    \'!': 'missing',
    \'?': 'not tracked',
    \'I': 'ignored',
    \' ': '',
    \}

function! s:HgCommit_GenerateMessage(repo, filenames) abort
    let l:msg  = "HG: Enter commit message. Lines beginning with 'HG:' are removed.\n"
    let l:msg .= "HG: Leave message empty to abort commit.\n"
    let l:msg .= "HG: Write and quit buffer to proceed.\n"
    let l:msg .= "HG: --\n"
    let l:msg .= "HG: user: " . split(a:repo.RunCommand('showconfig ui.username'), '\n')[0] . "\n"
    let l:msg .= "HG: branch '" . split(a:repo.RunCommand('branch'), '\n')[0] . "'\n"

    if len(a:filenames)
        let l:status_lines = split(a:repo.RunCommand('status', a:filenames), "\n")
    else
        let l:status_lines = split(a:repo.RunCommand('status'), "\n")
    endif
    for l:line in l:status_lines
        if l:line ==# ''
            continue
        endif
        let l:type = matchstr(l:line, '\v^[MARC\!\?I ]')
        let l:path = l:line[2:]
        let l:msg .= "HG: " . s:hg_status_messages[l:type] . ' ' . l:path . "\n"
    endfor

    return l:msg
endfunction

function! s:HgCommit_Execute(log_file, show_output) abort
    " Check if the user actually saved a commit message.
    if !filereadable(a:log_file)
        call s:error("abort: Commit message not saved")
        return
    endif

    call s:trace("Committing with log file: " . a:log_file)

    " Clean up all the 'HG:' lines from the commit message, and see if there's
    " any message left (Mercurial does this automatically, usually, but
    " apparently not when you feed it a log file...).
    let l:lines = readfile(a:log_file)
    call filter(l:lines, "v:val !~# '\\v^HG:'")
    if len(filter(copy(l:lines), "v:val !~# '\\v^\\s*$'")) == 0
        call s:error("abort: Empty commit message")
        return
    endif
    call writefile(l:lines, a:log_file)

    " Get the repo and commit with the given message.
    let l:repo = s:hg_repo()
    let l:hg_args = ['-l', a:log_file]
    call extend(l:hg_args, b:lawrencium_commit_files)
    let l:output = l:repo.RunCommand('commit', l:hg_args)
    if a:show_output && l:output !~# '\v%^\s*%$'
        call s:trace("Output from hg commit:", 1)
        for l:output_line in split(l:output, '\n')
            echom l:output_line
        endfor
    endif
endfunction

call s:AddMainCommand("-bang -nargs=* -complete=customlist,s:ListRepoFiles Hgcommit :call s:HgCommit(<bang>0, 0, <f-args>)")
call s:AddMainCommand("-bang -nargs=* -complete=customlist,s:ListRepoFiles Hgvcommit :call s:HgCommit(<bang>0, 1, <f-args>)")

" }}}

" Hgrevert {{{

function! s:HgRevert(bang, ...) abort
    " Get the files to revert.
    let l:filenames = a:000
    if a:0 == 0
        let l:filenames = [ expand('%:p') ]
    endif
    if a:bang
        call insert(l:filenames, '--no-backup', 0)
    endif

    " Get the repo and run the command.
    let l:repo = s:hg_repo()
    call l:repo.RunCommand('revert', l:filenames)
endfunction

call s:AddMainCommand("-bang -nargs=* -complete=customlist,s:ListRepoFiles Hgrevert :call s:HgRevert(<bang>0, <f-args>)")

" }}}

" Hglog {{{

function! s:HgLog(...) abort
    let l:filepath = expand('%:p')
    if a:0 == 1
        let l:filepath = a:1
    endif

    " Get the repo and get the command.
    let l:repo = s:hg_repo()
    let l:log_command = l:repo.GetCommand('log', l:filepath, '--template', '"{rev}\t{desc|firstline}\n"')

    " Open a new temp buffer in the preview window, jump to it,
    " and paste the `hg log` output in there.
    let l:temp_file = s:tempname('hg-log-', '.txt')
    execute "pedit " . l:temp_file
    wincmd p
    execute "read !" . escape(l:log_command, '%#\')

    " Setup the buffer correctly: readonly, and with the correct repo linked
    " to it, and deleted on close.
    let b:mercurial_dir = l:repo.root_dir
    let b:mercurial_logged_file = l:filepath
    setlocal bufhidden=delete
    setlocal buftype=nofile
    setlocal syntax=hglog

    " Make commands available.
    call s:DefineMainCommands()

    " Add some other nice commands and mappings.
    command! -buffer -nargs=? Hglogrevedit :call s:HgLog_FileRevEdit(<f-args>)
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <cr>  :Hglogrevedit<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>
    endif

    " Make sure the file is deleted with the buffer.
    autocmd BufDelete <buffer> call s:clean_tempfile(expand('<afile>:p'))
endfunction

function! s:HgLog_FileRevEdit(...)
    if a:0 > 0
        " Revision was given manually.
        let l:rev = a:1
    else
        " Revision should be parsed from the current line in the log.
        let l:rev = s:HgLog_GetSelectedRev()
    endif
    let l:path = 'lawrencium://' . b:mercurial_dir . '@' . b:mercurial_logged_file . '//' . l:rev
    execute 'edit ' . l:path
endfunction

function! s:HgLog_GetSelectedRev() abort
    let l:line = getline('.')
    " Behold, Vim's look-ahead regex syntax again! WTF.
    let l:rev = matchstr(l:line, '\v^(\d+)(\s)@=')
    if l:rev == ''
        call s:throw("Can't parse revision number from line: " . l:line)
    endif
    return l:rev
endfunction

call s:AddMainCommand("-nargs=? -complete=customlist,s:ListRepoFiles Hglog :call s:HgLog(<f-args>)")

" }}}

" Lawrencium files {{{

function! s:ReadFileRevision(path) abort
    let l:comps = s:parse_lawrencium_path(a:path)
    if l:comps['root'] == ''
        call s:throw("Can't get repository root from: " . a:path)
    endif
    let l:repo = s:HgRepo.New(l:comps['root'])
    if l:comps['rev'] == ''
        execute 'read !' . escape(l:repo.GetCommand('cat', l:comps['path']), '%#\')
    else
        execute 'read !' . escape(l:repo.GetCommand('cat', '-r', l:comps['rev'], l:comps['path']), '%#\')
    endif
    return ''
endfunction

augroup lawrencium_files
  autocmd!
  autocmd BufReadCmd  lawrencium://**//[0-9a-f][0-9a-f]* exe s:ReadFileRevision(expand('<amatch>'))
augroup END

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
    let l:branch = 'default'
    let l:branch_file = s:hg_repo().GetFullPath('.hg/branch')
    if filereadable(l:branch_file)
        let l:branch = readfile(l:branch_file)[0]
    endif
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

