
function! lawrencium#commit#init() abort
    call lawrencium#add_command("-bang -nargs=* -complete=customlist,lawrencium#list_repo_files Hgcommit :call lawrencium#commit#HgCommit(<bang>0, 0, 0, <f-args>)")
    call lawrencium#add_command("-bang -nargs=* -complete=customlist,lawrencium#list_repo_files Hgvcommit :call lawrencium#commit#HgCommit(<bang>0, 1, 0, <f-args>)")
endfunction

function! lawrencium#commit#HgCommit(bang, vertical, callback, ...) abort
    " Get the repo we'll be committing into.
    let l:repo = lawrencium#hg_repo()

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
    let l:commit_path = lawrencium#tempname('hg-editor-', '.txt')
    let l:split = a:vertical ? 'vsplit' : 'split'
    execute l:split . ' ' . l:commit_path
    call append(0, ['', ''])
    call append(2, split(s:HgCommit_GenerateMessage(l:repo, l:filenames), '\n'))
    call cursor(1, 1)

    " Setup the auto-command that will actually commit on write/exit,
    " and make the buffer delete itself on exit.
    let b:mercurial_dir = l:repo.root_dir
    let b:lawrencium_commit_files = l:filenames
    if type(a:callback) == type([])
        let b:lawrencium_commit_pre_callback = a:callback[0]
        let b:lawrencium_commit_post_callback = a:callback[1]
        let b:lawrencium_commit_abort_callback = a:callback[2]
    else
        let b:lawrencium_commit_pre_callback = 0
        let b:lawrencium_commit_post_callback = a:callback
        let b:lawrencium_commit_abort_callback = 0
    endif
    setlocal bufhidden=delete
    setlocal filetype=hgcommit
    if a:bang
        autocmd BufDelete <buffer> call s:HgCommit_Execute(expand('<afile>:p'), 0)
    else
        autocmd BufDelete <buffer> call s:HgCommit_Execute(expand('<afile>:p'), 1)
    endif
    " Make commands available.
    call lawrencium#define_commands()
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

    execute 'lcd ' . fnameescape(a:repo.root_dir)
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
        call lawrencium#error("abort: Commit message not saved")
        if exists('b:lawrencium_commit_abort_callback') &&
                    \type(b:lawrencium_commit_abort_callback) == type("") &&
                    \b:lawrencium_commit_abort_callback != ''
            call lawrencium#trace("Executing abort callback: ".b:lawrencium_commit_abort_callback)
            execute b:lawrencium_commit_abort_callback
        endif
        return
    endif

    " Execute a pre-callback if there is one.
    if exists('b:lawrencium_commit_pre_callback') &&
                \type(b:lawrencium_commit_pre_callback) == type("") &&
                \b:lawrencium_commit_pre_callback != ''
        call lawrencium#trace("Executing pre callback: ".b:lawrencium_commit_pre_callback)
        execute b:lawrencium_commit_pre_callback
    endif

    call lawrencium#trace("Committing with log file: " . a:log_file)

    " Clean all the 'HG: ' lines.
    let l:is_valid = lawrencium#clean_commit_file(a:log_file)
    if !l:is_valid
        call lawrencium#error("abort: Empty commit message")
        return
    endif

    " Get the repo and commit with the given message.
    let l:repo = lawrencium#hg_repo()
    let l:hg_args = ['-l', a:log_file]
    call extend(l:hg_args, b:lawrencium_commit_files)
    let l:output = l:repo.RunCommand('commit', l:hg_args)
    if a:show_output && l:output !~# '\v%^\s*%$'
        call lawrencium#trace("Output from hg commit:", 1)
        for l:output_line in split(l:output, '\n')
            echom l:output_line
        endfor
    endif

    " Execute a post-callback if there is one.
    if exists('b:lawrencium_commit_post_callback') &&
                \type(b:lawrencium_commit_post_callback) == type("") &&
                \b:lawrencium_commit_post_callback != ''
        call lawrencium#trace("Executing post callback: ".b:lawrencium_commit_post_callback)
        execute b:lawrencium_commit_post_callback
    endif
endfunction

