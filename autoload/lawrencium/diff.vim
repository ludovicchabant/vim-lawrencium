
function! lawrencium#diff#init() abort
    call lawrencium#add_command("-nargs=* Hgdiff :call lawrencium#diff#HgDiff('%:p', 0, <f-args>)")
    call lawrencium#add_command("-nargs=* Hgvdiff :call lawrencium#diff#HgDiff('%:p', 1, <f-args>)")
    call lawrencium#add_command("-nargs=* Hgtabdiff :call lawrencium#diff#HgDiff('%:p', 2, <f-args>)")

    call lawrencium#add_command("-nargs=* Hgdiffsum       :call lawrencium#diff#HgDiffSummary('%:p', 0, <f-args>)")
    call lawrencium#add_command("-nargs=* Hgdiffsumsplit  :call lawrencium#diff#HgDiffSummary('%:p', 1, <f-args>)")
    call lawrencium#add_command("-nargs=* Hgvdiffsumsplit :call lawrencium#diff#HgDiffSummary('%:p', 2, <f-args>)")
    call lawrencium#add_command("-nargs=* Hgtabdiffsum    :call lawrencium#diff#HgDiffSummary('%:p', 3, <f-args>)")

    call lawrencium#add_reader('diff', 'lawrencium#diff#read')
endfunction

function! lawrencium#diff#read(repo, path_parts, full_path) abort
    let l:diffargs = []
    let l:commaidx = stridx(a:path_parts['value'], ',')
    if l:commaidx > 0
        let l:rev1 = strpart(a:path_parts['value'], 0, l:commaidx)
        let l:rev2 = strpart(a:path_parts['value'], l:commaidx + 1)
        if l:rev1 == '-'
            let l:diffargs = [ '-r', l:rev2 ]
        elseif l:rev2 == '-'
            let l:diffargs = [ '-r', l:rev1 ]
        else
            let l:diffargs = [ '-r', l:rev1, '-r', l:rev2 ]
        endif
    elseif a:path_parts['value'] != ''
        let l:diffargs = [ '-c', a:path_parts['value'] ]
    else
        let l:diffargs = []
    endif
    if a:path_parts['path'] != '' && a:path_parts['path'] != '.'
        call add(l:diffargs, a:full_path)
    endif
    call a:repo.ReadCommandOutput('diff', l:diffargs)
    setlocal filetype=diff
    setlocal nofoldenable
endfunction

function! lawrencium#diff#HgDiff(filename, split, ...) abort
    " Default revisions to diff: the working directory (null string) 
    " and the parent of the working directory (using Mercurial's revsets syntax).
    " Otherwise, use the 1 or 2 revisions specified as extra parameters.
    let l:rev1 = 'p1()'
    let l:rev2 = ''
    if a:0 == 1
        if type(a:1) == type([])
            if len(a:1) >= 2
                let l:rev1 = a:1[0]
                let l:rev2 = a:1[1]
            elseif len(a:1) == 1
                let l:rev1 = a:1[0]
            endif
        else
            let l:rev1 = a:1
        endif
    elseif a:0 == 2
        let l:rev1 = a:1
        let l:rev2 = a:2
    endif

    " Get the current repo, and expand the given filename in case it contains
    " fancy filename modifiers.
    let l:repo = lawrencium#hg_repo()
    let l:path = expand(a:filename)
    let l:diff_id = localtime()
    call lawrencium#trace("Diff'ing '".l:rev1."' and '".l:rev2."' on file: ".l:path)

    " Get the first file and open it.
    let l:cleanupbufnr = -1
    if l:rev1 == ''
        if a:split == 2
            " Don't use `tabedit` here because if `l:path` is the same as
            " the current path, it will also reload the buffer in the current
            " tab/window for some reason, which causes all state to be lost
            " (all folds get collapsed again, cursor is moved to start, etc.)
            tabnew
            let l:cleanupbufnr = bufnr('%')
            execute 'edit ' . fnameescape(l:path)
        else
            if bufexists(l:path)
                execute 'buffer ' . fnameescape(l:path)
            else
                execute 'edit ' . fnameescape(l:path)
            endif
        endif
        " Make it part of the diff group.
        call s:HgDiff_DiffThis(l:diff_id)
    else
        let l:rev_path = l:repo.GetLawrenciumPath(l:path, 'rev', l:rev1)
        if a:split == 2
            " See comments above about avoiding `tabedit`.
            tabnew
            let l:cleanupbufnr = bufnr('%')
        endif
        execute 'edit ' . fnameescape(l:rev_path)
        " Make it part of the diff group.
        call s:HgDiff_DiffThis(l:diff_id)
    endif
    if l:cleanupbufnr >= 0 && bufloaded(l:cleanupbufnr)
        execute 'bdelete ' . l:cleanupbufnr
    endif

    " Get the second file and open it too.
    " Don't use `diffsplit` because it will set `&diff` before we get a chance
    " to save a bunch of local settings that we will want to restore later.
    let l:diffsplit = 'split'
    if a:split >= 1
        let l:diffsplit = 'vsplit'
    endif
    if l:rev2 == ''
        execute l:diffsplit . ' ' . fnameescape(l:path)
    else
        let l:rev_path = l:repo.GetLawrenciumPath(l:path, 'rev', l:rev2)
        execute l:diffsplit . ' ' . fnameescape(l:rev_path)
    endif
    call s:HgDiff_DiffThis(l:diff_id)
endfunction

function! lawrencium#diff#HgDiffThis(diff_id)
    call s:HgDiff_DiffThis(a:diff_id)
endfunction

function! s:HgDiff_DiffThis(diff_id) abort
    " Store some commands to run when we exit diff mode.
    " It's needed because `diffoff` reverts those settings to their default
    " values, instead of their previous ones.
    if &diff
        call lawrencium#throwerr("Calling diffthis too late on a buffer!")
        return
    endif
    call lawrencium#trace('Enabling diff mode on ' . bufname('%'))
    let w:lawrencium_diffoff = {}
    let w:lawrencium_diffoff['&diff'] = 0
    let w:lawrencium_diffoff['&wrap'] = &l:wrap
    let w:lawrencium_diffoff['&scrollopt'] = &l:scrollopt
    let w:lawrencium_diffoff['&scrollbind'] = &l:scrollbind
    let w:lawrencium_diffoff['&cursorbind'] = &l:cursorbind
    let w:lawrencium_diffoff['&foldmethod'] = &l:foldmethod
    let w:lawrencium_diffoff['&foldcolumn'] = &l:foldcolumn
    let w:lawrencium_diffoff['&foldenable'] = &l:foldenable
    let w:lawrencium_diff_id = a:diff_id
    diffthis
    autocmd BufWinLeave <buffer> call s:HgDiff_CleanUp()
endfunction

function! s:HgDiff_DiffOff(...) abort
    " Get the window name (given as a paramter, or current window).
    let l:nr = a:0 ? a:1 : winnr()

    " Run the commands we saved in `HgDiff_DiffThis`, or just run `diffoff`.
    let l:backup = getwinvar(l:nr, 'lawrencium_diffoff')
    if type(l:backup) == type({}) && len(l:backup) > 0
        call lawrencium#trace('Disabling diff mode on ' . l:nr)
        for key in keys(l:backup)
            call setwinvar(l:nr, key, l:backup[key])
        endfor
        call setwinvar(l:nr, 'lawrencium_diffoff', {})
    else
        call lawrencium#trace('Disabling diff mode on ' . l:nr . ' (but no true restore)')
        diffoff
    endif
endfunction

function! s:HgDiff_GetDiffWindows(diff_id) abort
    let l:result = []
    for nr in range(1, winnr('$'))
        if getwinvar(nr, '&diff') && getwinvar(nr, 'lawrencium_diff_id') == a:diff_id
            call add(l:result, nr)
        endif
    endfor
    return l:result
endfunction

function! s:HgDiff_CleanUp() abort
    " If we're not leaving one of our diff window, do nothing.
    if !&diff || !exists('w:lawrencium_diff_id')
        return
    endif

    " If there will be only one diff window left (plus the one we're leaving),
    " turn off diff in it and restore its local settings.
    let l:nrs = s:HgDiff_GetDiffWindows(w:lawrencium_diff_id)
    if len(l:nrs) <= 2
        call lawrencium#trace('Disabling diff mode in ' . len(l:nrs) . ' windows.')
        for nr in l:nrs
            if getwinvar(nr, '&diff')
                call s:HgDiff_DiffOff(nr)
            endif
        endfor
    else
        call lawrencium#trace('Still ' . len(l:nrs) . ' diff windows open.')
    endif
endfunction

function! lawrencium#diff#HgDiffSummary(filename, present_args, ...) abort
    " Default revisions to diff: the working directory (null string) 
    " and the parent of the working directory (using Mercurial's revsets syntax).
    " Otherwise, use the 1 or 2 revisions specified as extra parameters.
    let l:revs = ''
    if a:0 == 1
        if type(a:1) == type([])
            if len(a:1) >= 2
                let l:revs = a:1[0] . ',' . a:1[1]
            elseif len(a:1) == 1
                let l:revs = a:1[0]
            endif
        else
            let l:revs = a:1
        endif
    elseif a:0 >= 2
        let l:revs = a:1 . ',' . a:2
    endif

    " Get the current repo, and expand the given filename in case it contains
    " fancy filename modifiers.
    let l:repo = lawrencium#hg_repo()
    let l:path = expand(a:filename)
    call lawrencium#trace("Diff'ing revisions: '".l:revs."' on file: ".l:path)
    let l:special = l:repo.GetLawrenciumPath(l:path, 'diff', l:revs)

    " Build the correct edit command, and switch to the correct window, based
    " on the presentation arguments we got.
    if type(a:present_args) == type(0)
        " Just got a split mode.
        let l:valid_args = {'split_mode': a:present_args}
    else
        " Got complex args.
        let l:valid_args = a:present_args
    endif

    " First, see if we should reuse an existing window based on some buffer
    " variable.
    let l:target_winnr = -1
    let l:split = get(l:valid_args, 'split_mode', 0)
    let l:reuse_id = get(l:valid_args, 'reuse_id', '')
    let l:avoid_id = get(l:valid_args, 'avoid_win', -1)
    if l:reuse_id != ''
        let l:target_winnr = lawrencium#find_buffer_window(l:reuse_id, 1)
        if l:target_winnr > 0 && l:split != 3
            " Unless we'll be opening in a new tab, don't split anymore, since
            " we found the exact window we wanted.
            let l:split = 0
        endif
        call lawrencium#trace("Looking for window with '".l:reuse_id."', found: ".l:target_winnr)
    endif
    " If we didn't find anything, see if we should use the current or previous
    " window.
    if l:target_winnr <= 0
        let l:use_prev_win = get(l:valid_args, 'use_prev_win', 0)
        if l:use_prev_win
            let l:target_winnr = winnr('#')
            call lawrencium#trace("Will use previous window: ".l:target_winnr)
        endif
    endif
    " And let's see if we have a window we should actually avoid.
    if l:avoid_id >= 0 && 
                \(l:target_winnr == l:avoid_id ||
                \(l:target_winnr <= 0 && winnr() == l:avoid_id))
        for wnr in range(1, winnr('$'))
            if wnr != l:avoid_id
                call lawrencium#trace("Avoiding using window ".l:avoid_id.
                            \", now using: ".wnr)
                let l:target_winnr = wnr
                break
            endif
        endfor
    endif
    " Now let's see what kind of split we want to use, if any.
    let l:cmd = 'edit '
    if l:split == 1
        let l:cmd = 'rightbelow split '
    elseif l:split == 2
        let l:cmd = 'rightbelow vsplit '
    elseif l:split == 3
        let l:cmd = 'tabedit '
    endif
    
    " All good now, proceed.
    if l:target_winnr > 0
        execute l:target_winnr . "wincmd w"
    endif
    execute 'keepalt ' . l:cmd . fnameescape(l:special)

    " Set the reuse ID if we had one.
    if l:reuse_id != ''
        call lawrencium#trace("Setting reuse ID '".l:reuse_id."' on buffer: ".bufnr('%'))
        call setbufvar('%', l:reuse_id, 1)
    endif
endfunction

