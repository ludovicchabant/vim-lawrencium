
" Path Utility {{{

" Strips the ending slash in a path.
function! lawrencium#stripslash(path)
    return fnamemodify(a:path, ':s?[/\\]$??')
endfunction

" Returns whether a path is absolute.
function! lawrencium#isabspath(path)
    return a:path =~# '\v^(\w\:)?[/\\]'
endfunction

" Normalizes the slashes in a path.
function! lawrencium#normalizepath(path)
    if exists('+shellslash') && &shellslash
        return substitute(a:path, '\v/', '\\', 'g')
    elseif has('win32')
        return substitute(a:path, '\v/', '\\', 'g')
    else
        return a:path
    endif
endfunction

" Shell-slashes the path (opposite of `normalizepath`).
function! lawrencium#shellslash(path)
  if exists('+shellslash') && !&shellslash
    return substitute(a:path, '\v\\', '/', 'g')
  else
    return a:path
  endif
endfunction

" Like tempname() but with some control over the filename.
function! lawrencium#tempname(name, ...)
    let l:path = tempname()
    let l:result = fnamemodify(l:path, ':h') . '/' . a:name . fnamemodify(l:path, ':t')
    if a:0 > 0
        let l:result = l:result . a:1
    endif
    return l:result
endfunction

" Delete a temporary file if it exists.
function! lawrencium#clean_tempfile(path)
    if filewritable(a:path)
        call lawrencium#trace("Cleaning up temporary file: " . a:path)
        call delete(a:path)
    endif
endfunction

" }}}

" Logging {{{

" Prints a message if debug tracing is enabled.
function! lawrencium#trace(message, ...)
   if g:lawrencium_trace || (a:0 && a:1)
       let l:message = "lawrencium: " . a:message
       echom l:message
   endif
endfunction

" Prints an error message with 'lawrencium error' prefixed to it.
function! lawrencium#error(message)
    echom "lawrencium error: " . a:message
endfunction

" Throw a Lawrencium exception message.
function! lawrencium#throw(message)
    throw "lawrencium: " . a:message
endfunction

" Throw a Lawrencium exception message and set Vim's error message.
function! lawrencium#throwerr(message)
    let v:errmsg = "lawrencium: " . a:message
    throw v:errmsg
endfunction

" }}}

" Repositories {{{

" Finds the repository root given a path inside that repository.
" Throw an error if not repository is found.
function! lawrencium#find_repo_root(path)
    let l:path = lawrencium#stripslash(a:path)
    let l:previous_path = ""
    while l:path != l:previous_path
        if isdirectory(l:path . '/.hg')
            return lawrencium#normalizepath(simplify(fnamemodify(l:path, ':p')))
        endif
        let l:previous_path = l:path
        let l:path = fnamemodify(l:path, ':h')
    endwhile
    call lawrencium#throw("No Mercurial repository found above: " . a:path)
endfunction

" Given a Lawrencium path (e.g: 'lawrencium:///repo/root_dir//foo/bar/file.py//rev=34'), extract
" the repository root, relative file path and revision number/changeset ID.
"
" If a second argument exists, it must be:
" - `relative`: to make the file path relative to the repository root.
" - `absolute`: to make the file path absolute.
"
function! lawrencium#parse_lawrencium_path(lawrencium_path, ...)
    let l:repo_path = lawrencium#shellslash(a:lawrencium_path)
    let l:repo_path = substitute(l:repo_path, '\\ ', ' ', 'g')
    if l:repo_path =~? '\v^lawrencium://'
        let l:repo_path = strpart(l:repo_path, strlen('lawrencium://'))
    endif

    let l:root_dir = ''
    let l:at_idx = stridx(l:repo_path, '//')
    if l:at_idx >= 0
        let l:root_dir = strpart(l:repo_path, 0, l:at_idx)
        let l:repo_path = strpart(l:repo_path, l:at_idx + 2)
    endif

    let l:value = ''
    let l:action = ''
    let l:actionidx = stridx(l:repo_path, '//')
    if l:actionidx >= 0
        let l:action = strpart(l:repo_path, l:actionidx + 2)
        let l:repo_path = strpart(l:repo_path, 0, l:actionidx)

        let l:equalidx = stridx(l:action, '=')
        if l:equalidx >= 0
            let l:value = strpart(l:action, l:equalidx + 1)
            let l:action = strpart(l:action, 0, l:equalidx)
        endif
    endif

    if a:0 > 0
        execute 'cd! ' . fnameescape(l:root_dir)
        if a:1 == 'relative'
            let l:repo_path = fnamemodify(l:repo_path, ':.')
        elseif a:1 == 'absolute'
            let l:repo_path = fnamemodify(l:repo_path, ':p')
        endif
        execute 'cd! -'
    endif
    
    let l:result = { 'root': l:root_dir, 'path': l:repo_path, 'action': l:action, 'value': l:value }
    return l:result
endfunction

" Clean up all the 'HG:' lines from a commit message, and see if there's
" any message left (Mercurial does this automatically, usually, but
" apparently not when you feed it a log file...).
function! lawrencium#clean_commit_file(log_file) abort
    let l:lines = readfile(a:log_file)
    call filter(l:lines, "v:val !~# '\\v^HG:'")
    if len(filter(copy(l:lines), "v:val !~# '\\v^\\s*$'")) == 0
        return 0
    endif
    call writefile(l:lines, a:log_file)
    return 1
endfunction

" }}}

" Vim Utility {{{

" Finds a window whose displayed buffer has a given variable
" set to the given value.
function! lawrencium#find_buffer_window(varname, varvalue) abort
    for wnr in range(1, winnr('$'))
        let l:bnr = winbufnr(wnr)
        if getbufvar(l:bnr, a:varname) == a:varvalue
            return l:wnr
        endif
    endfor
    return -1
endfunction

" Opens a buffer in a way that makes it easy to delete it later:
" - if the about-to-be previous buffer doesn't have a given variable,
"   just open the new buffer.
" - if the about-to-be previous buffer has a given variable, open the
"   new buffer with the `keepalt` option to make it so that the
"   actual previous buffer (returned by things like `bufname('#')`)
"   is the original buffer that was there before the first deletable
"   buffer was opened.
function! lawrencium#edit_deletable_buffer(varname, varvalue, path) abort
    let l:edit_cmd = 'edit '
    if getbufvar('%', a:varname) != ''
        let l:edit_cmd = 'keepalt edit '
    endif
    execute l:edit_cmd . fnameescape(a:path)
    call setbufvar('%', a:varname, a:varvalue)
endfunction

" Deletes all buffers that have a given variable set to a given value.
" For each buffer, if it is not shown in any window, it will be just deleted.
" If it is shown in a window, that window will be switched to the alternate
" buffer before the buffer is deleted, unless the `lawrencium_quit_on_delete`
" variable is set to `1`, in which case the window is closed too.
function! lawrencium#delete_dependency_buffers(varname, varvalue) abort
    let l:cur_winnr = winnr()
    for bnr in range(1, bufnr('$'))
        if getbufvar(bnr, a:varname) == a:varvalue
            " Delete this buffer if it is not shown in any window.
            " Otherwise, display the alternate buffer before deleting
            " it so the window is not closed.
            let l:bwnr = bufwinnr(bnr)
            if l:bwnr < 0 || getbufvar(bnr, 'lawrencium_quit_on_delete') == 1
                if bufloaded(l:bnr)
                    call lawrencium#trace("Deleting dependency buffer " . bnr)
                    execute "bdelete! " . bnr
                else
                    call lawrencium#trace("Dependency buffer " . bnr . " is already unladed.")
                endif
            else
                execute l:bwnr . "wincmd w"
                " TODO: better handle case where there's no previous/alternate buffer?
                let l:prev_bnr = bufnr('#')
                if l:prev_bnr > 0 && bufloaded(l:prev_bnr)
                    execute "buffer " . l:prev_bnr
                    if bufloaded(l:bnr)
                        call lawrencium#trace("Deleting dependency buffer " . bnr . " after switching to " . l:prev_bnr . " in window " . l:bwnr)
                        execute "bdelete! " . bnr
                    else
                        call lawrencium#trace("Dependency buffer " . bnr . " is unladed after switching to " . l:prev_bnr)
                    endif
                else
                    call lawrencium#trace("Deleting dependency buffer " . bnr . " and window.")
                    bdelete!
                endif
            endif
        endif
    endfor
    if l:cur_winnr != winnr()
        call lawrencium#trace("Returning to window " . l:cur_winnr)
        execute l:cur_winnr . "wincmd w"
    endif
endfunction

" }}}

" Mercurial Repository Object {{{

" Let's define a Mercurial repo 'class' using prototype-based object-oriented
" programming.
"
" The prototype dictionary.
let s:HgRepo = {}

" Constructor.
function! s:HgRepo.New(path) abort
    let l:newRepo = copy(self)
    let l:newRepo.root_dir = lawrencium#find_repo_root(a:path)
    call lawrencium#trace("Built new Mercurial repository object at : " . l:newRepo.root_dir)
    return l:newRepo
endfunction

" Gets a full path given a repo-relative path.
function! s:HgRepo.GetFullPath(path) abort
    let l:root_dir = self.root_dir
    if lawrencium#isabspath(a:path)
        call lawrencium#throwerr("Expected relative path, got absolute path: " . a:path)
    endif
    return lawrencium#normalizepath(l:root_dir . a:path)
endfunction

" Gets a repo-relative path given any path.
function! s:HgRepo.GetRelativePath(path) abort
    execute 'lcd! ' . fnameescape(self.root_dir)
    let l:relative_path = fnamemodify(a:path, ':.')
    execute 'lcd! -'
    return l:relative_path
endfunction

" Gets, and optionally creates, a temp folder for some operation in the `.hg`
" directory.
function! s:HgRepo.GetTempDir(path, ...) abort
    let l:tmp_dir = self.GetFullPath('.hg/lawrencium/' . a:path)
    if !isdirectory(l:tmp_dir)
        if a:0 > 0 && !a:1
            return ''
        endif
        call mkdir(l:tmp_dir, 'p')
    endif
    return l:tmp_dir
endfunction

" Gets a list of files matching a root-relative pattern.
" If a flag is passed and is TRUE, a slash will be appended to all
" directories.
function! s:HgRepo.Glob(pattern, ...) abort
    let l:root_dir = self.root_dir
    if (a:pattern =~# '\v^[/\\]')
        let l:root_dir = lawrencium#stripslash(l:root_dir)
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
    let l:prev_shellslash = &shellslash
    setlocal noshellslash
    let l:hg_command = g:lawrencium_hg_executable . ' --repository ' . shellescape(lawrencium#stripslash(self.root_dir))
    let l:hg_command = l:hg_command . ' ' . a:command
    for l:arg in l:arg_list
        let l:hg_command = l:hg_command . ' ' . shellescape(l:arg)
    endfor
    if l:prev_shellslash
        setlocal shellslash
    endif
    return l:hg_command
endfunction

" Runs a Mercurial command in the repo.
function! s:HgRepo.RunCommand(command, ...) abort
    let l:all_args = [1, a:command] + a:000
    return call(self['RunCommandEx'], l:all_args, self)
endfunction

function! s:HgRepo.RunCommandEx(plain_mode, command, ...) abort
    let l:prev_hgplain = $HGPLAIN
    if a:plain_mode
        let $HGPLAIN = 'true'
    endif
    let l:all_args = [a:command] + a:000
    let l:hg_command = call(self['GetCommand'], l:all_args, self)
    call lawrencium#trace("Running Mercurial command: " . l:hg_command)
    let l:cmd_out = system(l:hg_command)
    if a:plain_mode
        let $HGPLAIN = l:prev_hgplain
    endif
    return l:cmd_out
endfunction

" Runs a Mercurial command in the repo and reads its output into the current
" buffer.
function! s:HgRepo.ReadCommandOutput(command, ...) abort
    function! s:PutOutputIntoBuffer(command_line)
        let l:was_buffer_empty = (line('$') == 1 && getline(1) == '')
        execute '0read!' . escape(a:command_line, '%#\')
        if l:was_buffer_empty  " (Always true?)
            " '0read' inserts before the cursor, leaving a blank line which
            " needs to be deleted... but if there are folds in this thing, we
            " must open them all first otherwise we could delete the whole
            " contents of the last fold (since Vim may close them all by
            " default).
            normal! zRG"_dd
        endif
    endfunction

    let l:all_args = [a:command] + a:000
    let l:hg_command = call(self['GetCommand'], l:all_args, self)
    call lawrencium#trace("Running Mercurial command: " . l:hg_command)
    call s:PutOutputIntoBuffer(l:hg_command)
endfunction

" Build a Lawrencium path for the given file and action.
" By default, the given path will be made relative to the repository root,
" unless '0' is passed as the 4th argument.
function! s:HgRepo.GetLawrenciumPath(path, action, value, ...) abort
    let l:path = a:path
    if a:0 == 0 || !a:1
        let l:path = self.GetRelativePath(a:path)
    endif
    let l:path = fnameescape(l:path)
    let l:result = 'lawrencium://' . lawrencium#stripslash(self.root_dir) . '//' . l:path
    if a:action !=? ''
        let l:result  = l:result . '//' . a:action
        if a:value !=? ''
            let l:result = l:result . '=' . a:value
        endif
    endif
    return l:result
endfunction

" Repo cache map.
let s:buffer_repos = {}

" Get a cached repo.
function! lawrencium#hg_repo(...) abort
    " Use the given path, or the mercurial directory of the current buffer.
    if a:0 == 0
        if exists('b:mercurial_dir')
            let l:path = b:mercurial_dir
        else
            let l:path = lawrencium#find_repo_root(expand('%:p'))
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

" }}}

" Buffer Object {{{

" The prototype dictionary.
let s:Buffer = {}

" Constructor.
function! s:Buffer.New(number) dict abort
    let l:newBuffer = copy(self)
    let l:newBuffer.nr = a:number
    let l:newBuffer.var_backup = {}
    let l:newBuffer.cmd_names = {}
    let l:newBuffer.on_delete = []
    let l:newBuffer.on_winleave = []
    let l:newBuffer.on_unload = []
    execute 'augroup lawrencium_buffer_' . a:number
    execute '  autocmd!'
    execute '  autocmd BufDelete <buffer=' . a:number . '> call s:buffer_on_delete(' . a:number . ')'
    execute 'augroup end'
    call lawrencium#trace("Built new buffer object for buffer: " . a:number)
    return l:newBuffer
endfunction

function! s:Buffer.GetName(...) dict abort
    let l:name = bufname(self.nr)
    if a:0 > 0
        let l:name = fnamemodify(l:name, a:1)
    endif
    return l:name
endfunction

function! s:Buffer.GetVar(var) dict abort
    return getbufvar(self.nr, a:var)
endfunction

function! s:Buffer.SetVar(var, value) dict abort
    if !has_key(self.var_backup, a:var)
        let self.var_backup[a:var] = getbufvar(self.nr, a:var)
    endif
    return setbufvar(self.nr, a:var, a:value)
endfunction

function! s:Buffer.RestoreVars() dict abort
    for key in keys(self.var_backup)
        setbufvar(self.nr, key, self.var_backup[key])
    endfor
endfunction

function! s:Buffer.DefineCommand(name, ...) dict abort
    if a:0 == 0
        call lawrencium#throwerr("Not enough parameters for s:Buffer.DefineCommands()")
    endif
    if a:0 == 1
        let l:flags = ''
        let l:cmd = a:1
    else
        let l:flags = a:1
        let l:cmd = a:2
    endif
    if has_key(self.cmd_names, a:name)
        call lawrencium#throwerr("Command '".a:name."' is already defined in buffer ".self.nr)
    endif
    if bufnr('%') != self.nr
        call lawrencium#throwerr("You must move to buffer ".self.nr."first before defining local commands")
    endif
    let self.cmd_names[a:name] = 1
    let l:real_flags = ''
    if type(l:flags) == type('')
        let l:real_flags = l:flags
    endif
    execute 'command -buffer '.l:real_flags.' '.a:name.' '.l:cmd
endfunction

function! s:Buffer.DeleteCommand(name) dict abort
    if !has_key(self.cmd_names, a:name)
        call lawrencium#throwerr("Command '".a:name."' has not been defined in buffer ".self.nr)
    endif
    if bufnr('%') != self.nr
        call lawrencium#throwerr("You must move to buffer ".self.nr."first before deleting local commands")
    endif
    execute 'delcommand '.a:name
    call remove(self.cmd_names, a:name)
endfunction

function! s:Buffer.DeleteCommands() dict abort
    if bufnr('%') != self.nr
        call lawrencium#throwerr("You must move to buffer ".self.nr."first before deleting local commands")
    endif
    for name in keys(self.cmd_names)
        execute 'delcommand '.name
    endfor
    let self.cmd_names = {}
endfunction

function! s:Buffer.MoveToFirstWindow() dict abort
    let l:win_nr = bufwinnr(self.nr)
    if l:win_nr < 0
        if a:0 > 0 && a:1 == 0
            return 0
        endif
        call lawrencium#throwerr("No windows currently showing buffer ".self.nr)
    endif
    execute l:win_nr.'wincmd w'
    return 1
endfunction

function! s:Buffer.OnDelete(cmd) dict abort
    call lawrencium#trace("Adding BufDelete callback for buffer " . self.nr . ": " . a:cmd)
    call add(self.on_delete, a:cmd)
endfunction

function! s:Buffer.OnWinLeave(cmd) dict abort
    if len(self.on_winleave) == 0
        call lawrencium#trace("Adding BufWinLeave auto-command on buffer " . self.nr)
        execute 'augroup lawrencium_buffer_' . self.nr . '_winleave'
        execute '  autocmd!'
        execute '  autocmd BufWinLeave <buffer=' . self.nr . '> call s:buffer_on_winleave(' . self.nr .')'
        execute 'augroup end'
    endif
    call lawrencium#trace("Adding BufWinLeave callback for buffer " . self.nr . ": " . a:cmd)
    call add(self.on_winleave, a:cmd)
endfunction

function! s:Buffer.OnUnload(cmd) dict abort
    if len(self.on_unload) == 0
        call lawrencium#trace("Adding BufUnload auto-command on buffer " . self.nr)
        execute 'augroup lawrencium_buffer_' . self.nr . '_unload'
        execute '  autocmd!'
        execute '  autocmd BufUnload <buffer=' . self.nr . '> call s:buffer_on_unload(' . self.nr . ')'
        execute 'augroup end'
    endif
    call lawrencium#trace("Adding BufUnload callback for buffer " . self.nr . ": " . a:cmd)
    call add(self.on_unload, a:cmd)
endfunction

let s:buffer_objects = {}

" Get a buffer instance for the specified buffer number, or the
" current buffer if nothing is specified.
function! lawrencium#buffer_obj(...) abort
    let l:bufnr = a:0 ? a:1 : bufnr('%')
    if !has_key(s:buffer_objects, l:bufnr)
        let s:buffer_objects[l:bufnr] = s:Buffer.New(l:bufnr)
    endif
    return s:buffer_objects[l:bufnr]
endfunction

" Execute all the "on delete" callbacks.
function! s:buffer_on_delete(number) abort
    let l:bufobj = s:buffer_objects[a:number]
    call lawrencium#trace("Calling BufDelete callbacks on buffer " . l:bufobj.nr)
    for cmd in l:bufobj.on_delete
        call lawrencium#trace(" [" . cmd . "]")
        execute cmd
    endfor
    call lawrencium#trace("Deleted buffer object " . l:bufobj.nr)
    call remove(s:buffer_objects, l:bufobj.nr)
    execute 'augroup lawrencium_buffer_' . l:bufobj.nr
    execute '  autocmd!'
    execute 'augroup end'
endfunction

" Execute all the "on winleave" callbacks.
function! s:buffer_on_winleave(number) abort
    let l:bufobj = s:buffer_objects[a:number]
    call lawrencium#trace("Calling BufWinLeave callbacks on buffer " . l:bufobj.nr)
    for cmd in l:bufobj.on_winleave
        call lawrencium#trace(" [" . cmd . "]")
        execute cmd
    endfor
    execute 'augroup lawrencium_buffer_' . l:bufobj.nr . '_winleave'
    execute '  autocmd!'
    execute 'augroup end'
endfunction

" Execute all the "on unload" callbacks.
function! s:buffer_on_unload(number) abort
    let l:bufobj = s:buffer_objects[a:number]
    call lawrencium#trace("Calling BufUnload callbacks on buffer " . l:bufobj.nr)
    for cmd in l:bufobj.on_unload
        call lawrencium#trace(" [" . cmd . "]")
        execute cmd
    endfor
    execute 'augroup lawrencium_buffer_' . l:bufobj.nr . '_unload'
    execute '  autocmd!'
    execute 'augroup end'
endfunction

" }}}

" Buffer Commands Management {{{

" Store the commands for Lawrencium-enabled buffers so that we can add them in
" batch when we need to.
let s:main_commands = []

function! lawrencium#add_command(command) abort
    let s:main_commands += [a:command]
endfunction

function! lawrencium#define_commands()
    for l:command in s:main_commands
        execute 'command! -buffer ' . l:command
    endfor
endfunction

augroup lawrencium_main
    autocmd!
    autocmd User Lawrencium call lawrencium#define_commands()
augroup end

" Sets up the current buffer with Lawrencium commands if it contains a file from a Mercurial repo.
" If the file is not in a Mercurial repo, just exit silently.
function! lawrencium#setup_buffer_commands() abort
    call lawrencium#trace("Scanning buffer '" . bufname('%') . "' for Lawrencium setup...")
    let l:do_setup = 1
    if exists('b:mercurial_dir')
        if b:mercurial_dir =~# '\v^\s*$'
            unlet b:mercurial_dir
        else
            let l:do_setup = 0
        endif
    endif
    try
        let l:repo = lawrencium#hg_repo()
    catch /^lawrencium\:/
        return
    endtry
    let b:mercurial_dir = l:repo.root_dir
    if exists('b:mercurial_dir') && l:do_setup
        call lawrencium#trace("Setting Mercurial commands for buffer '" . bufname('%'))
        call lawrencium#trace("  with repo : " . expand(b:mercurial_dir))
        silent doautocmd User Lawrencium
    endif
endfunction

" }}}

" Commands Auto-Complete {{{

" Auto-complete function for commands that take repo-relative file paths.
function! lawrencium#list_repo_files(ArgLead, CmdLine, CursorPos) abort
    let l:matches = lawrencium#hg_repo().Glob(a:ArgLead . '*', 1)
    call map(l:matches, 'lawrencium#normalizepath(v:val)')
    return l:matches
endfunction

" Auto-complete function for commands that take repo-relative directory paths.
function! lawrencium#list_repo_dirs(ArgLead, CmdLine, CursorPos) abort
    let l:matches = lawrencium#hg_repo().Glob(a:ArgLead . '*/')
    call map(l:matches, 'lawrencium#normalizepath(v:val)')
    return l:matches
endfunction

" }}}

" Lawrencium Files {{{

" Generic read
let s:lawrencium_file_readers = {}
let s:lawrencium_file_customoptions = {}

function! lawrencium#add_reader(action, callback, ...) abort
    if has_key(s:lawrencium_file_readers, a:action)
        call lawrencium#throwerr("Lawrencium file '".a:action."' has alredy been registered.")
    endif
    let s:lawrencium_file_readers[a:action] = function(a:callback)
    if a:0 && a:1
        let s:lawrencium_file_customoptions[a:action] = 1
    endif
endfunction

function! lawrencium#read_lawrencium_file(path) abort
    call lawrencium#trace("Reading Lawrencium file: " . a:path)
    let l:path_parts = lawrencium#parse_lawrencium_path(a:path)
    if l:path_parts['root'] == ''
        call lawrencium#throwerr("Can't get repository root from: " . a:path)
    endif
    if !has_key(s:lawrencium_file_readers, l:path_parts['action'])
        call lawrencium#throwerr("No registered reader for action: " . l:path_parts['action'])
    endif

    " Call the registered reader.
    let l:repo = lawrencium#hg_repo(l:path_parts['root'])
    let l:full_path = l:repo.root_dir . l:path_parts['path']
    let LawrenciumFileReader = s:lawrencium_file_readers[l:path_parts['action']]
    call LawrenciumFileReader(l:repo, l:path_parts, l:full_path)

    " Setup the new buffer.
    if !has_key(s:lawrencium_file_customoptions, l:path_parts['action'])
        setlocal readonly
        setlocal nomodified
        setlocal bufhidden=delete
        setlocal buftype=nofile
    endif
    goto

    " Remember the real Lawrencium path, because Vim can fuck up the slashes
    " on Windows.
    let b:lawrencium_path = a:path

    " Remember the repo it belongs to and make
    " the Lawrencium commands available.
    let b:mercurial_dir = l:repo.root_dir
    call lawrencium#define_commands()

    return ''
endfunction

function! lawrencium#write_lawrencium_file(path) abort
    call lawrencium#trace("Writing Lawrencium file: " . a:path)
endfunction

" }}}

" Statusline {{{

" Prints a summary of the current repo (if any) that's appropriate for
" displaying on the status line.
function! lawrencium#statusline(...)
    if !exists('b:mercurial_dir')
        return ''
    endif
    let l:repo = lawrencium#hg_repo()
    let l:prefix = (a:0 > 0 ? a:1 : '')
    let l:suffix = (a:0 > 1 ? a:2 : '')
    let l:branch = 'default'
    let l:branch_file = l:repo.GetFullPath('.hg/branch')
    if filereadable(l:branch_file)
        let l:branch = readfile(l:branch_file)[0]
    endif
    let l:bookmarks = ''
    let l:bookmarks_file = l:repo.GetFullPath('.hg/bookmarks.current')
    if filereadable(l:bookmarks_file)
        let l:bookmarks = join(readfile(l:bookmarks_file), ', ')
    endif
    let l:line = l:prefix . l:branch
    if strlen(l:bookmarks) > 0
        let l:line = l:line . ' - ' . l:bookmarks
    endif
    let l:line = l:line . l:suffix
    return l:line
endfunction

" }}}

" Miscellaneous User Functions {{{

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
    call lawrencium#setup_buffer_commands()
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

" Setup {{{

function! lawrencium#init() abort
    let s:builtin_exts = [
                \'lawrencium#addremove',
                \'lawrencium#annotate',
                \'lawrencium#cat',
                \'lawrencium#commit',
                \'lawrencium#diff',
                \'lawrencium#hg',
                \'lawrencium#log',
                \'lawrencium#mq',
                \'lawrencium#record',
                \'lawrencium#revert',
                \'lawrencium#status',
                \'lawrencium#vimutils'
                \]
    let s:user_exts = copy(g:lawrencium_extensions)
    let s:exts = s:builtin_exts + s:user_exts
    for ext in s:exts
        call lawrencium#trace("Initializing Lawrencium extension " . ext)
        execute ('call ' . ext . '#init()')
    endfor
endfunction

" }}}

