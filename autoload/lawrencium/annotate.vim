
function! lawrencium#annotate#init() abort
    call lawrencium#add_command("-bang -nargs=? -complete=customlist,lawrencium#list_repo_files Hgannotate :call lawrencium#annotate#HgAnnotate(<bang>0, 0, <f-args>)")
    call lawrencium#add_command("-bang -nargs=? -complete=customlist,lawrencium#list_repo_files Hgwannotate :call lawrencium#annotate#HgAnnotate(<bang>0, 1, <f-args>)")

    call lawrencium#add_reader('annotate', 'lawrencium#annotate#read')
endfunction

function! lawrencium#annotate#read(repo, path_parts, full_path) abort
    let l:cmd_args = ['-c', '-n', '-u', '-d', '-q']
    if a:path_parts['value'] == 'v=1'
        call insert(l:cmd_args, '-v', 0)
    endif
    call add(l:cmd_args, a:full_path)
    call a:repo.ReadCommandOutput('annotate', l:cmd_args)
endfunction

function! lawrencium#annotate#HgAnnotate(bang, verbose, ...) abort
    " Open the file to annotate if needed.
    if a:0 > 0
        call lawrencium#vimutils#HgEdit(a:bang, a:1)
    endif

    " Get the Lawrencium path for the annotated file.
    let l:path = expand('%:p')
    let l:bufnr = bufnr('%')
    let l:repo = lawrencium#hg_repo()
    let l:value = a:verbose ? 'v=1' : ''
    let l:annotation_path = l:repo.GetLawrenciumPath(l:path, 'annotate', l:value)
    
    " Check if we're trying to annotate something with local changes.
    let l:has_local_edits = 0
    let l:path_status = l:repo.RunCommand('status', l:path)
    if l:path_status != ''
        call lawrencium#trace("Found local edits for '" . l:path . "'. Will annotate parent revision.")
        let l:has_local_edits = 1
    endif
    
    if l:has_local_edits
        " Just open the output of the command.
        echom "Local edits found, will show the annotations for the parent revision."
        execute 'edit ' . fnameescape(l:annotation_path)
        setlocal nowrap nofoldenable
        setlocal filetype=hgannotate
    else
        " Store some info about the current buffer.
        let l:cur_topline = line('w0') + &scrolloff
        let l:cur_line = line('.')
        let l:cur_wrap = &wrap
        let l:cur_foldenable = &foldenable

        " Open the annotated file in a split buffer on the left, after
        " having disabled wrapping and folds on the current file.
        " Make both windows scroll-bound.
        setlocal scrollbind nowrap nofoldenable
        execute 'keepalt leftabove vsplit ' . fnameescape(l:annotation_path)
        setlocal nonumber
        setlocal scrollbind nowrap nofoldenable foldcolumn=0
        setlocal filetype=hgannotate

        " When the annotated buffer is deleted, restore the settings we
        " changed on the current buffer, and go back to that buffer.
        let l:annotate_buffer = lawrencium#buffer_obj()
        call l:annotate_buffer.OnDelete('execute bufwinnr(' . l:bufnr . ') . "wincmd w"')
        call l:annotate_buffer.OnDelete('setlocal noscrollbind')
        if l:cur_wrap
            call l:annotate_buffer.OnDelete('setlocal wrap')
        endif
        if l:cur_foldenable
            call l:annotate_buffer.OnDelete('setlocal foldenable')
        endif

        " Go to the line we were at in the source buffer when we
        " opened the annotation window.
        execute l:cur_topline
        normal! zt
        execute l:cur_line
        syncbind

        " Set the correct window width for the annotations.
        if a:verbose
            let l:last_token = match(getline('.'), '\v\d{4}:\s')
            let l:token_end = 5
        else
            let l:last_token = match(getline('.'), '\v\d{2}:\s')
            let l:token_end = 3
        endif
        if l:last_token < 0
            echoerr "Can't find the end of the annotation columns."
        else
            let l:column_count = l:last_token + l:token_end + g:lawrencium_annotate_width_offset
            execute "vertical resize " . l:column_count
            setlocal winfixwidth
        endif
    endif

    " Make the annotate buffer a Lawrencium buffer.
    let b:mercurial_dir = l:repo.root_dir
    let b:lawrencium_annotated_path = l:path
    let b:lawrencium_annotated_bufnr = l:bufnr
    call lawrencium#define_commands()

    " Add some other nice commands and mappings.
    command! -buffer Hgannotatediffsum :call s:HgAnnotate_DiffSummary()
    command! -buffer Hgannotatelog     :call s:HgAnnotate_DiffSummary(1)
    if g:lawrencium_define_mappings
        nnoremap <buffer> <silent> <cr> :Hgannotatediffsum<cr>
        nnoremap <buffer> <silent> <leader><cr> :Hgannotatelog<cr>
    endif

    " Clean up when the annotate buffer is deleted.
    let l:bufobj = lawrencium#buffer_obj()
    call l:bufobj.OnDelete('call lawrencium#annotate#HgAnnotate_Delete(' . l:bufobj.nr . ')')
endfunction

function! lawrencium#annotate#HgAnnotate_Delete(bufnr) abort
    if g:lawrencium_auto_close_buffers
        call lawrencium#delete_dependency_buffers('lawrencium_diff_for', a:bufnr)
    endif
endfunction

function! s:HgAnnotate_DiffSummary(...) abort
    " Get the path for the diff of the revision specified under the cursor.
    let l:line = getline('.')
    let l:rev_hash = matchstr(l:line, '\v[a-f0-9]{12}')
    let l:log = (a:0 > 0 ? a:1 : 0)

    " Get the Lawrencium path for the diff, and the buffer object for the
    " annotation.
    let l:repo = lawrencium#hg_repo()
    if l:log
      let l:path = l:repo.GetLawrenciumPath(b:lawrencium_annotated_path, 'logpatch', l:rev_hash)
    else
      let l:path = l:repo.GetLawrenciumPath(b:lawrencium_annotated_path, 'diff', l:rev_hash)
    endif
    let l:annotate_buffer = lawrencium#buffer_obj()

    " Find a window already displaying diffs for this annotation.
    let l:diff_winnr = lawrencium#find_buffer_window('lawrencium_diff_for', l:annotate_buffer.nr)
    if l:diff_winnr == -1
        " Not found... go back to the main source buffer and open a bottom 
        " split with the diff for the specified revision.
        execute bufwinnr(b:lawrencium_annotated_bufnr) . 'wincmd w'
        execute 'rightbelow split ' . fnameescape(l:path)
        let b:lawrencium_diff_for = l:annotate_buffer.nr
        let b:lawrencium_quit_on_delete = 1
    else
        " Found! Use that window to open the diff.
        execute l:diff_winnr . 'wincmd w'
        execute 'edit ' . fnameescape(l:path)
        let b:lawrencium_diff_for = l:annotate_buffer.nr
    endif
endfunction

