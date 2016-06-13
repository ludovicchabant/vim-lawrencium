
function! lawrencium#mq#init() abort
    call lawrencium#add_command("Hgqseries call lawrencium#mq#HgQSeries()")

    call lawrencium#add_reader('qseries', "lawrencium#mq#read")
endfunction

function! lawrencium#mq#read(repo, path_parts, full_path) abort
    let l:names = split(a:repo.RunCommand('qseries'), '\n')
    let l:head = split(a:repo.RunCommand('qapplied', '-s'), '\n')
    let l:tail = split(a:repo.RunCommand('qunapplied', '-s'), '\n')

    let l:idx = 0
    let l:curbuffer = bufname('%')
    for line in l:head
        call setbufvar(l:curbuffer, 'lawrencium_patchname_' . (l:idx + 1), l:names[l:idx])
        call append(l:idx, "*" . line)
        let l:idx = l:idx + 1
    endfor
    for line in l:tail
        call setbufvar(l:curbuffer, 'lawrencium_patchname_' . (l:idx + 1), l:names[l:idx])
        call append(l:idx, line)
        let l:idx = l:idx + 1
    endfor
    call setbufvar(l:curbuffer, 'lawrencium_patchname_top', l:names[len(l:head) - 1])
    set filetype=hgqseries
endfunction

function! lawrencium#mq#HgQSeries() abort
    " Open the MQ series in the preview window and jump to it.
    let l:repo = lawrencium#hg_repo()
    let l:path = l:repo.GetLawrenciumPath('', 'qseries', '')
    execute 'pedit ' . fnameescape(l:path)
    wincmd P

    " Make the series buffer a Lawrencium buffer.
    let b:mercurial_dir = l:repo.root_dir
    call lawrencium#define_commands()

    " Add some commands and mappings.
    command! -buffer Hgqseriesgoto                  :call s:HgQSeries_Goto()
    command! -buffer Hgqserieseditmessage           :call s:HgQSeries_EditMessage()
    command! -buffer -nargs=+ Hgqseriesrename       :call s:HgQSeries_Rename(<f-args>)
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <C-g> :Hgqseriesgoto<cr>
        nnoremap <buffer> <silent> <C-e> :Hgqserieseditmessage<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>
    endif
endfunction

function! s:HgQSeries_GetCurrentPatchName() abort
    let l:pos = getpos('.')
    return getbufvar('%', 'lawrencium_patchname_' . l:pos[1])
endfunction

function! s:HgQSeries_Goto() abort
    let l:repo = lawrencium#hg_repo()
    let l:patchname = s:HgQSeries_GetCurrentPatchName()
    if len(l:patchname) == 0
        call lawrencium#error("No patch to go to here.")
        return
    endif
    call l:repo.RunCommand('qgoto', l:patchname)
    edit
endfunction

function! s:HgQSeries_Rename(...) abort
    let l:repo = lawrencium#hg_repo()
    let l:current_name = s:HgQSeries_GetCurrentPatchName()
    if len(l:current_name) == 0
        call lawrencium#error("No patch to rename here.")
        return
    endif
    let l:new_name = '"' . join(a:000, ' ') . '"'
    call l:repo.RunCommand('qrename', l:current_name, l:new_name)
    edit
endfunction

function! s:HgQSeries_EditMessage() abort
    let l:repo = lawrencium#hg_repo()
    let l:patchname = getbufvar('%', 'lawrencium_patchname_top')
    if len(l:patchname) == 0
        call lawrencium#error("No patch to edit here.")
        return
    endif
    let l:current = split(l:repo.RunCommand('qheader', l:patchname), '\n')

    " Open a temp file to write the commit message.
    let l:temp_file = lawrencium#tempname('hg-qrefedit-', '.txt')
    split
    execute 'edit ' . fnameescape(l:temp_file)
    call append(0, 'HG: Enter the new commit message for patch "' . l:patchname . '" here.\n')
    call append(0, '')
    call append(0, l:current)
    call cursor(1, 1)

    " Make it a temp buffer that will actually change the commit message
    " when it is saved and closed.
    let b:mercurial_dir = l:repo.root_dir
    let b:lawrencium_patchname = l:patchname
    setlocal bufhidden=delete
    setlocal filetype=hgcommit
    autocmd BufDelete <buffer> call s:HgQSeries_EditMessage_Execute(expand('<afile>:p'))

    call lawrencium#define_commands()
endfunction

function! s:HgQSeries_EditMessage_Execute(log_file) abort
    if !filereadable(a:log_file)
        call lawrencium#error("abort: Commit message not saved")
        return
    endif

    " Clean all the 'HG:' lines.
    let l:is_valid = lawrencium#clean_commit_file(a:log_file)
    if !l:is_valid
        call lawrencium#error("abort: Empty commit message")
        return
    endif

    " Get the repo and edit the given patch.
    let l:repo = lawrencium#hg_repo()
    let l:hg_args = ['-s', '-l', a:log_file]
    call l:repo.RunCommand('qref', l:hg_args)
endfunction

