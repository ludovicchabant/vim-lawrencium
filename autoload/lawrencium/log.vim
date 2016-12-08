
function! lawrencium#log#init() abort
    call lawrencium#add_command("Hglogthis  :call lawrencium#log#HgLog(0, '%:p')")
    call lawrencium#add_command("Hgvlogthis :call lawrencium#log#HgLog(1, '%:p')")
    call lawrencium#add_command("-nargs=* -complete=customlist,lawrencium#list_repo_files Hglog  :call lawrencium#log#HgLog(0, <f-args>)")
    call lawrencium#add_command("-nargs=* -complete=customlist,lawrencium#list_repo_files Hgvlog  :call lawrencium#log#HgLog(1, <f-args>)")

    call lawrencium#add_reader("log", "lawrencium#log#read")
    call lawrencium#add_reader("logpatch", "lawrencium#log#read_patch")
endfunction

let s:log_style_file = expand("<sfile>:h:h:h") . "/resources/hg_log.style"

function! lawrencium#log#read(repo, path_parts, full_path) abort
    let l:log_opts = join(split(a:path_parts['value'], ','))
    let l:log_cmd = "log " . l:log_opts

    if a:path_parts['path'] == ''
        call a:repo.ReadCommandOutput(l:log_cmd, '--style', s:log_style_file)
    else
        call a:repo.ReadCommandOutput(l:log_cmd, '--style', s:log_style_file, a:full_path)
    endif
    setlocal filetype=hglog
endfunction

function! lawrencium#log#read_patch(repo, path_parts, full_path) abort
    let l:log_cmd = 'log --patch --verbose --rev ' . a:path_parts['value']

    if a:path_parts['path'] == ''
        call a:repo.ReadCommandOutput(l:log_cmd)
    else
        call a:repo.ReadCommandOutput(l:log_cmd, a:full_path)
    endif
    setlocal filetype=diff
endfunction

function! lawrencium#log#HgLog(vertical, ...) abort
    " Get the file or directory to get the log from.
    " (empty string is for the whole repository)
    let l:repo = lawrencium#hg_repo()
    if a:0 > 0 && matchstr(a:1, '\v-*') == ""
        let l:path = l:repo.GetRelativePath(expand(a:1))
    else
        let l:path = ''
    endif

    " Get the Lawrencium path for this `hg log`,
    " open it in a preview window and jump to it.
    if a:0 > 0 && l:path != ""
      let l:log_opts = join(a:000[1:-1], ',')
    else
      let l:log_opts = join(a:000, ',')
    endif

    let l:log_path = l:repo.GetLawrenciumPath(l:path, 'log', l:log_opts)
    if a:vertical
        execute 'vertical pedit ' . fnameescape(l:log_path)
    else
        execute 'pedit ' . fnameescape(l:log_path)
    endif
    wincmd P

    " Add some other nice commands and mappings.
    let l:is_file = (l:path != '' && filereadable(l:repo.GetFullPath(l:path)))
    command! -buffer -nargs=* Hglogdiffsum    :call s:HgLog_DiffSummary(1, <f-args>)
    command! -buffer -nargs=* Hglogvdiffsum   :call s:HgLog_DiffSummary(2, <f-args>)
    command! -buffer -nargs=* Hglogtabdiffsum :call s:HgLog_DiffSummary(3, <f-args>)
    command! -buffer -nargs=+ -complete=file Hglogexport :call s:HgLog_ExportPatch(<f-args>)
    if l:is_file
        command! -buffer Hglogrevedit          :call s:HgLog_FileRevEdit()
        command! -buffer -nargs=* Hglogdiff    :call s:HgLog_Diff(0, <f-args>)
        command! -buffer -nargs=* Hglogvdiff   :call s:HgLog_Diff(1, <f-args>)
        command! -buffer -nargs=* Hglogtabdiff :call s:HgLog_Diff(2, <f-args>)
    endif

    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <C-U> :Hglogdiffsum<cr>
        nnoremap <buffer> <silent> <C-H> :Hglogvdiffsum<cr>
        nnoremap <buffer> <silent> <cr>  :Hglogvdiffsum<cr>
        nnoremap <buffer> <silent> q     :bdelete!<cr>
        if l:is_file
            nnoremap <buffer> <silent> <C-E>  :Hglogrevedit<cr>
            nnoremap <buffer> <silent> <C-D>  :Hglogtabdiff<cr>
            nnoremap <buffer> <silent> <C-V>  :Hglogvdiff<cr>
        endif
    endif

    " Clean up when the log buffer is deleted.
    let l:bufobj = lawrencium#buffer_obj()
    call l:bufobj.OnDelete('call lawrencium#log#HgLog_Delete(' . l:bufobj.nr . ')')
endfunction

function! lawrencium#log#HgLog_Delete(bufnr)
    if g:lawrencium_auto_close_buffers
        call lawrencium#delete_dependency_buffers('lawrencium_diff_for', a:bufnr)
        call lawrencium#delete_dependency_buffers('lawrencium_rev_for', a:bufnr)
    endif
endfunction

function! s:HgLog_FileRevEdit()
    let l:repo = lawrencium#hg_repo()
    let l:bufobj = lawrencium#buffer_obj()
    let l:rev = s:HgLog_GetSelectedRev()
    let l:log_path = lawrencium#parse_lawrencium_path(l:bufobj.GetName())
    let l:path = l:repo.GetLawrenciumPath(l:log_path['path'], 'rev', l:rev)

    " Go to the window we were in before going in the log window,
    " and open the revision there.
    wincmd p
    call lawrencium#edit_deletable_buffer('lawrencium_rev_for', l:bufobj.nr, l:path)
endfunction

function! s:HgLog_Diff(split, ...) abort
    let l:revs = []
    if a:0 >= 2
        let l:revs = [a:1, a:2]
    elseif a:0 == 1
        let l:revs = ['p1('.a:1.')', a:1]
    else
        let l:sel = s:HgLog_GetSelectedRev()
        let l:revs = ['p1('.l:sel.')', l:sel]
    endif

    let l:repo = lawrencium#hg_repo()
    let l:bufobj = lawrencium#buffer_obj()
    let l:log_path = lawrencium#parse_lawrencium_path(l:bufobj.GetName())
    let l:path = l:repo.GetFullPath(l:log_path['path'])

    " Go to the window we were in before going to the log window,
    " and open the split diff there.
    if a:split < 2
        wincmd p
    endif
    call lawrencium#diff#HgDiff(l:path, a:split, l:revs)
endfunction

function! s:HgLog_DiffSummary(split, ...) abort
    let l:revs = []
    if a:0 >= 2
        let l:revs = [a:1, a:2]
    elseif a:0 == 1
        let l:revs = [a:1]
    else
        let l:revs = [s:HgLog_GetSelectedRev()]
    endif

    let l:repo = lawrencium#hg_repo()
    let l:bufobj = lawrencium#buffer_obj()
    let l:log_path = lawrencium#parse_lawrencium_path(l:bufobj.GetName())
    let l:path = l:repo.GetFullPath(l:log_path['path'])

    " Go to the window we were in before going in the log window,
    " and split for the diff summary from there.
    let l:reuse_id = 'lawrencium_diffsum_for_' . bufnr('%')
    let l:split_prev_win = (a:split < 3)
    let l:args = {'reuse_id': l:reuse_id, 'use_prev_win': l:split_prev_win,
                \'split_mode': a:split}
    call lawrencium#diff#HgDiffSummary(l:path, l:args, l:revs)
endfunction

function! s:HgLog_GetSelectedRev(...) abort
    if a:0 == 1
        let l:line = getline(a:1)
    else
        let l:line = getline('.')
    endif
    " Behold, Vim's look-ahead regex syntax again! WTF.
    let l:rev = matchstr(l:line, '\v^(\d+)(\:)@=')
    if l:rev == ''
        call lawrencium#throwerr("Can't parse revision number from line: " . l:line)
    endif
    return l:rev
endfunction

function! s:HgLog_ExportPatch(...) abort
    let l:patch_name = a:1
    if !empty($HG_EXPORT_PATCH_DIR)
        " Use the patch dir only if user has specified a relative path
        if has('win32')
            let l:is_patch_relative = (matchstr(l:patch_name, '\v^([a-zA-Z]:)?\\') == "")
        else
            let l:is_patch_relative = (matchstr(l:patch_name, '\v^/') == "")
        endif
        if l:is_patch_relative
            let l:patch_name = lawrencium#normalizepath(
                lawrencium#stripslash($HG_EXPORT_PATCH_DIR) . "/" . l:patch_name)
        endif
    endif

    if a:0 == 2
        let l:rev = a:2
    else
        let l:rev = s:HgLog_GetSelectedRev()
    endif

    let l:repo = lawrencium#hg_repo()
    let l:export_args = ['-o', l:patch_name, '-r', l:rev]

    call l:repo.RunCommand('export', l:export_args)

    echom "Created patch: " . l:patch_name
endfunction

