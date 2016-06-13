
function! lawrencium#status#init() abort
    call lawrencium#add_command("Hgstatus :call lawrencium#status#HgStatus()")

    call lawrencium#add_reader('status', "lawrencium#status#read", 1)
endfunction

function! lawrencium#status#read(repo, path_parts, full_path) abort
    if a:path_parts['path'] == ''
        call a:repo.ReadCommandOutput('status')
    else
        call a:repo.ReadCommandOutput('status', a:full_path)
    endif
    setlocal nomodified
    setlocal filetype=hgstatus
    setlocal bufhidden=delete
    setlocal buftype=nofile
endfunction

function! lawrencium#status#HgStatus() abort
    " Get the repo and the Lawrencium path for `hg status`.
    let l:repo = lawrencium#hg_repo()
    let l:status_path = l:repo.GetLawrenciumPath('', 'status', '')

    " Open the Lawrencium buffer in a new split window of the right size.
    if g:lawrencium_status_win_split_above
      execute "keepalt leftabove split " . fnameescape(l:status_path)
    else
      execute "keepalt rightbelow split " . fnameescape(l:status_path)
    endif
    
    if (line('$') == 1 && getline(1) == '')
        " Buffer is empty, which means there are not changes...
        " Quit and display a message.
        " TODO: figure out why the first `echom` doesn't show when alone.
        bdelete
        echom "Nothing was modified."
        echom ""
        return
    endif

    execute "setlocal winfixheight"
    if !g:lawrencium_status_win_split_even
      execute "setlocal winheight=" . (line('$') + 1)
      execute "resize " . (line('$') + 1)
    endif

    " Add some nice commands.
    command! -buffer          Hgstatusedit          :call s:HgStatus_FileEdit(0)
    command! -buffer          Hgstatusdiff          :call s:HgStatus_Diff(0)
    command! -buffer          Hgstatusvdiff         :call s:HgStatus_Diff(1)
    command! -buffer          Hgstatustabdiff       :call s:HgStatus_Diff(2)
    command! -buffer          Hgstatusdiffsum       :call s:HgStatus_DiffSummary(1)
    command! -buffer          Hgstatusvdiffsum      :call s:HgStatus_DiffSummary(2)
    command! -buffer          Hgstatustabdiffsum    :call s:HgStatus_DiffSummary(3)
    command! -buffer          Hgstatusrefresh       :call s:HgStatus_Refresh()
    command! -buffer -range -bang Hgstatusrevert    :call s:HgStatus_Revert(<line1>, <line2>, <bang>0)
    command! -buffer -range   Hgstatusaddremove     :call s:HgStatus_AddRemove(<line1>, <line2>)
    command! -buffer -range=% -bang Hgstatuscommit  :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 0)
    command! -buffer -range=% -bang Hgstatusvcommit :call s:HgStatus_Commit(<line1>, <line2>, <bang>0, 1)
    command! -buffer -range=% -nargs=+ Hgstatusqnew :call s:HgStatus_QNew(<line1>, <line2>, <f-args>)
    command! -buffer -range=% Hgstatusqrefresh      :call s:HgStatus_QRefresh(<line1>, <line2>)

    " Add some handy mappings.
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <cr>  :Hgstatusedit<cr>
        nnoremap <buffer> <silent> <C-N> :call search('^[MARC\!\?I ]\s.', 'We')<cr>
        nnoremap <buffer> <silent> <C-P> :call search('^[MARC\!\?I ]\s.', 'Wbe')<cr>
        nnoremap <buffer> <silent> <C-D> :Hgstatustabdiff<cr>
        nnoremap <buffer> <silent> <C-V> :Hgstatusvdiff<cr>
        nnoremap <buffer> <silent> <C-U> :Hgstatusdiffsum<cr>
        nnoremap <buffer> <silent> <C-H> :Hgstatusvdiffsum<cr>
        nnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        nnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
        nnoremap <buffer> <silent> <C-R> :Hgstatusrefresh<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>

        vnoremap <buffer> <silent> <C-A> :Hgstatusaddremove<cr>
        vnoremap <buffer> <silent> <C-S> :Hgstatuscommit<cr>
    endif
endfunction

function! s:HgStatus_Refresh(...) abort
    if a:0 > 0
        let l:win_nr = bufwinnr(a:1)
        call lawrencium#trace("Switching back to status window ".l:win_nr)
        if l:win_nr < 0
            call lawrencium#throw("Can't find the status window anymore!")
        endif
        execute l:win_nr . 'wincmd w'
        " Delete everything in the buffer, and re-read the status into it.
        " TODO: In theory I would only have to do `edit` like below when we're
        " already in the window, but for some reason Vim just goes bonkers and
        " weird shit happens. I have no idea why, hence the work-around here
        " to bypass the whole `BufReadCmd` auto-command altogether, and just
        " edit the buffer in place.
        normal! ggVGd
        call lawrencium#read_lawrencium_file(b:lawrencium_path)
        return
    endif

    " Just re-edit the buffer, it will reload the contents by calling
    " the matching Mercurial command.
    edit
endfunction

function! s:HgStatus_FileEdit(newtab) abort
    " Get the path of the file the cursor is on.
    let l:filename = s:HgStatus_GetSelectedFile()

    let l:cleanupbufnr = -1
    if a:newtab == 0
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
    else
        " Just open a new tab so we can edit the file there.
        " We don't use `tabedit` because it messes up the current window
        " if it happens to be the same file.
        " We'll just have to clean up the default empty buffer created.
        tabnew
        let l:cleanupbufnr = bufnr('%')
    endif
    execute 'edit ' . fnameescape(l:filename)
    if l:cleanupbufnr >= 0
        execute 'bdelete ' . l:cleanupbufnr
    endif
endfunction

function! s:HgStatus_AddRemove(linestart, lineend) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['!', '?'])
    if len(l:filenames) == 0
        call lawrencium#error("No files to add or remove in selection or current line.")
        return
    endif

    " Run `addremove` on those paths.
    let l:repo = lawrencium#hg_repo()
    call l:repo.RunCommand('addremove', l:filenames)

    " Refresh the status window.
    call s:HgStatus_Refresh()
endfunction

function! s:HgStatus_Revert(linestart, lineend, bang) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(l:filenames) == 0
        call lawrencium#error("No files to revert in selection or current line.")
        return
    endif

    " Run `revert` on those paths.
    " If the bang modifier is specified, revert with no backup.
    let l:repo = lawrencium#hg_repo()
    if a:bang
        call insert(l:filenames, '-C', 0)
    endif
    call l:repo.RunCommand('revert', l:filenames)

    " Refresh the status window.
    call s:HgStatus_Refresh()
endfunction

function! s:HgStatus_Commit(linestart, lineend, bang, vertical) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(l:filenames) == 0
        call lawrencium#error("No files to commit in selection or file.")
        return
    endif

    " Run `Hgcommit` on those paths.
    let l:buf_nr = bufnr('%')
    let l:callback = 'call s:HgStatus_Refresh('.l:buf_nr.')'
    call lawrencium#commit#HgCommit(a:bang, a:vertical, l:callback, l:filenames)
endfunction

function! s:HgStatus_Diff(split) abort
    " Open the file and run `Hgdiff` on it.
    " We also need to translate the split mode for it... if we already
    " opened the file in a new tab, `HgDiff` only needs to do a vertical
    " split (i.e. split=1).
    let l:newtab = 0
    let l:hgdiffsplit = a:split
    if a:split == 2
        let l:newtab = 1
        let l:hgdiffsplit = 1
    endif
    call s:HgStatus_FileEdit(l:newtab)
    call lawrencium#diff#HgDiff('%:p', l:hgdiffsplit)
endfunction

function! s:HgStatus_DiffSummary(split) abort
    " Get the path of the file the cursor is on.
    let l:path = s:HgStatus_GetSelectedFile()
    " Reuse the same diff summary window
    let l:reuse_id = 'lawrencium_diffsum_for_' . bufnr('%')
    let l:split_prev_win = (a:split < 3)
    let l:args = {'reuse_id': l:reuse_id, 'use_prev_win': l:split_prev_win,
                \'avoid_win': winnr(), 'split_mode': a:split}
    call lawrencium#diff#HgDiffSummary(l:path, l:args)
endfunction

function! s:HgStatus_QNew(linestart, lineend, patchname, ...) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(l:filenames) == 0
        call lawrencium#error("No files in selection or file to create patch.")
        return
    endif

    " Run `Hg qnew` on those paths.
    let l:repo = lawrencium#hg_repo()
    call insert(l:filenames, a:patchname, 0)
    if a:0 > 0
        call insert(l:filenames, '-m', 0)
        let l:message = '"' . join(a:000, ' ') . '"'
        call insert(l:filenames, l:message, 1)
    endif
    call l:repo.RunCommand('qnew', l:filenames)

    " Refresh the status window.
    call s:HgStatus_Refresh()
endfunction

function! s:HgStatus_QRefresh(linestart, lineend) abort
    " Get the selected filenames.
    let l:filenames = s:HgStatus_GetSelectedFiles(a:linestart, a:lineend, ['M', 'A', 'R'])
    if len(l:filenames) == 0
        call lawrencium#error("No files in selection or file to refresh the patch.")
        return
    endif

    " Run `Hg qrefresh` on those paths.
    let l:repo = lawrencium#hg_repo()
    call insert(l:filenames, '-s', 0)
    call l:repo.RunCommand('qrefresh', l:filenames)

    " Refresh the status window.
    call s:HgStatus_Refresh()
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
    let l:repo = lawrencium#hg_repo()
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

