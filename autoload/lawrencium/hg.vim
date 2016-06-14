
function lawrencium#hg#init() abort
    call lawrencium#add_command("-bang -complete=customlist,lawrencium#hg#CompleteHg -nargs=* Hg :call lawrencium#hg#Hg(<bang>0, <f-args>)")
endfunction

function! lawrencium#hg#Hg(bang, ...) abort
    let l:repo = lawrencium#hg_repo()
    if g:lawrencium_auto_cd
        " Temporary set the current directory to the root of the repo
        " to make auto-completed paths work magically.
        execute 'cd! ' . fnameescape(l:repo.root_dir)
    endif
    let l:output = call(l:repo.RunCommandEx, [0] + a:000, l:repo)
    if g:lawrencium_auto_cd
        execute 'cd! -'
    endif
    silent doautocmd User HgCmdPost
    if a:bang
        " Open the output of the command in a temp file.
        let l:temp_file = lawrencium#tempname('hg-output-', '.txt')
        split
        execute 'edit ' . fnameescape(l:temp_file)
        call append(0, split(l:output, '\n'))
        call cursor(1, 1)

        " Make it a temp buffer
        setlocal bufhidden=delete
        setlocal buftype=nofile

        " Try to find a nice syntax to set given the current command.
        let l:command_name = s:GetHgCommandName(a:000)
        if l:command_name != '' && exists('g:lawrencium_hg_commands_file_types')
            let l:file_type = get(g:lawrencium_hg_commands_file_types, l:command_name, '')
            if l:file_type != ''
                execute 'setlocal ft=' . l:file_type
            endif
        endif
    else
        " Just print out the output of the command.
        echo l:output
    endif
endfunction

" Include the generated HG usage file.
let s:usage_file = expand("<sfile>:h:h:h") . "/resources/hg_usage.vim"
if filereadable(s:usage_file)
    execute "source " . fnameescape(s:usage_file)
else
    call lawrencium#error("Can't find the Mercurial usage file. Auto-completion will be disabled in Lawrencium.")
endif

" Include the command file type mappings.
let s:file_type_mappings = expand("<sfile>:h:h:h") . '/resources/hg_command_file_types.vim'
if filereadable(s:file_type_mappings)
    execute "source " . fnameescape(s:file_type_mappings)
endif

function! lawrencium#hg#CompleteHg(ArgLead, CmdLine, CursorPos)
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
        return filter(keys(g:lawrencium_hg_commands), "v:val[0:strlen(l:arglead)-1] ==# l:arglead")
    endif
    
    " Try completing a command's options.
    let l:cmd = matchstr(a:CmdLine, '\v(^Hg\s+(\-[a-zA-Z0-9\-_]+\s+)*)@<=[a-zA-Z]+')
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
        return lawrencium#list_repo_files(a:ArgLead, a:CmdLine, a:CursorPos)
endfunction

function! s:GetHgCommandName(args) abort
    for l:a in a:args
        if stridx(l:a, '-') != 0
            return l:a
        endif
    endfor
    return ''
endfunction

