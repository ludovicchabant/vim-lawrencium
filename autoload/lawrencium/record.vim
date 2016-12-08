
function! lawrencium#record#init() abort
    call lawrencium#add_command("Hgrecord call lawrencium#record#HgRecord(0)")
    call lawrencium#add_command("Hgvrecord call lawrencium#record#HgRecord(1)")
endfunction

function! lawrencium#record#HgRecord(split) abort
    let l:repo = lawrencium#hg_repo()
    let l:orig_buf = lawrencium#buffer_obj()
    let l:tmp_path = l:orig_buf.GetName(':p') . '~record'
    let l:diff_id = localtime()

    " Start diffing on the current file, enable some commands.
    call l:orig_buf.DefineCommand('Hgrecordabort', ':call lawrencium#record#HgRecord_Abort()')
    call l:orig_buf.DefineCommand('Hgrecordcommit', ':call lawrencium#record#HgRecord_Execute()')
    call lawrencium#diff#HgDiffThis(l:diff_id)
    setlocal foldmethod=diff

    " Split the window and open the parent revision in the right or bottom
    " window. Keep the current buffer in the left or top window... we're going
    " to 'move' those changes into the parent revision.
    let l:cmd = 'keepalt rightbelow split '
    if a:split == 1
        let l:cmd = 'keepalt rightbelow vsplit '
    endif
    let l:rev_path = l:repo.GetLawrenciumPath(expand('%:p'), 'rev', '')
    execute l:cmd . fnameescape(l:rev_path)

    " This new buffer with the parent revision is set as a Lawrencium buffer.
    " Let's save it to an actual file and reopen it like that (somehow we
    " could probably do it with `:saveas` instead but we'd need to reset a
    " bunch of other buffer settings, and Vim weirdly creates another backup
    " buffer when you do that).
    execute 'keepalt write! ' . fnameescape(l:tmp_path)
    execute 'keepalt edit! ' . fnameescape(l:tmp_path)
    setlocal bufhidden=delete
    let b:mercurial_dir = l:repo.root_dir
    let b:lawrencium_record_for = l:orig_buf.GetName(':p')
    let b:lawrencium_record_other_nr = l:orig_buf.nr
    let b:lawrencium_record_commit_split = !a:split
    call setbufvar(l:orig_buf.nr, 'lawrencium_record_for', '%')
    call setbufvar(l:orig_buf.nr, 'lawrencium_record_other_nr', bufnr('%'))

    " Hookup the commit and abort commands.
    let l:rec_buf = lawrencium#buffer_obj()
    call l:rec_buf.OnDelete('call lawrencium#record#HgRecord_Execute()')
    call l:rec_buf.DefineCommand('Hgrecordcommit', ':quit')
    call l:rec_buf.DefineCommand('Hgrecordabort', ':call lawrencium#record#HgRecord_Abort()')
    call lawrencium#define_commands()

    " Make it the other part of the diff.
    call lawrencium#diff#HgDiffThis(l:diff_id)
    setlocal foldmethod=diff
    call l:rec_buf.SetVar('&filetype', l:orig_buf.GetVar('&filetype'))
    call l:rec_buf.SetVar('&fileformat', l:orig_buf.GetVar('&fileformat'))

    if g:lawrencium_record_start_in_working_buffer
        wincmd p
    endif
endfunction

function! lawrencium#record#HgRecord_Execute() abort
    if exists('b:lawrencium_record_abort')
        " Abort flag is set, let's just cleanup.
        let l:buf_nr = b:lawrencium_record_for == '%' ? bufnr('%') :
                    \b:lawrencium_record_other_nr
        call lawrencium#record#HgRecord_CleanUp(l:buf_nr)
        call lawrencium#error("abort: User requested aborting the record operation.")
        return
    endif

    if !exists('b:lawrencium_record_for')
        call lawrencium#throwerr("This doesn't seem like a record buffer, something's wrong!")
    endif
    if b:lawrencium_record_for == '%'
        " Switch to the 'recording' buffer's window.
        let l:buf_obj = lawrencium#buffer_obj(b:lawrencium_record_other_nr)
        call l:buf_obj.MoveToFirstWindow()
    endif

    " Setup the commit operation.
    let l:split = b:lawrencium_record_commit_split
    let l:working_bufnr = b:lawrencium_record_other_nr
    let l:working_path = fnameescape(b:lawrencium_record_for)
    let l:record_path = fnameescape(expand('%:p'))
    let l:callbacks = [
                \'call lawrencium#record#HgRecord_PostExecutePre('.l:working_bufnr.', "'.
                    \escape(l:working_path, '\').'", "'.
                    \escape(l:record_path, '\').'")',
                \'call lawrencium#record#HgRecord_PostExecutePost('.l:working_bufnr.', "'.
                    \escape(l:working_path, '\').'")',
                \'call lawrencium#record#HgRecord_PostExecuteAbort('.l:working_bufnr.', "'.
                    \escape(l:record_path, '\').'")'
                \]
    call lawrencium#trace("Starting commit flow with callbacks: ".string(l:callbacks))
    call lawrencium#commit#HgCommit(0, l:split, l:callbacks, b:lawrencium_record_for)
endfunction

function! lawrencium#record#HgRecord_PostExecutePre(working_bufnr, working_path, record_path) abort
    " Just before committing, we switch the original file with the record
    " file... we'll restore things in the post-callback below.
    " We also switch on 'autoread' temporarily on the working buffer so that
    " we don't have an annoying popup in gVim.
    if has('dialog_gui')
        call setbufvar(a:working_bufnr, '&autoread', 1)
    endif
    call lawrencium#trace("Backuping original file: ".a:working_path)
    silent call rename(a:working_path, a:working_path.'~working')
    call lawrencium#trace("Committing recorded changes using: ".a:record_path)
    silent call rename(a:record_path, a:working_path)
    sleep 200m
endfunction

function! lawrencium#record#HgRecord_PostExecutePost(working_bufnr, working_path) abort
    " Recover the back-up file from underneath the buffer.
    call lawrencium#trace("Recovering original file: ".a:working_path)
    silent call rename(a:working_path.'~working', a:working_path)

    " Clean up!
    call lawrencium#record#HgRecord_CleanUp(a:working_bufnr)

    " Restore default 'autoread'.
    if has('dialog_gui')
        set autoread<
    endif
endfunction

function! lawrencium#record#HgRecord_PostExecuteAbort(working_bufnr, record_path) abort
    call lawrencium#record#HgRecord_CleanUp(a:working_bufnr)
    call lawrencium#trace("Delete discarded record file: ".a:record_path)
    silent call delete(a:record_path)
endfunction

function! lawrencium#record#HgRecord_Abort() abort
    if b:lawrencium_record_for == '%'
        " We're in the working directory buffer. Switch to the 'recording'
        " buffer and quit.
        let l:buf_obj = lawrencium#buffer_obj(b:lawrencium_record_other_nr)
        call l:buf_obj.MoveToFirstWindow()
    endif
    " We're now in the 'recording' buffer... set the abort flag and quit,
    " which will run the execution (it will early out and clean things up).
    let b:lawrencium_record_abort = 1
    quit!
endfunction

function! lawrencium#record#HgRecord_CleanUp(buf_nr) abort
    " Get in the original buffer and clean the local commands/variables.
    let l:buf_obj = lawrencium#buffer_obj(a:buf_nr)
    call l:buf_obj.MoveToFirstWindow()
    if !exists('b:lawrencium_record_for') || b:lawrencium_record_for != '%'
        call lawrencium#throwerr("Cleaning up something else than the original buffer ".
                \"for a record operation. That's suspiciously incorrect! ".
                \"Aborting.")
    endif
    call l:buf_obj.DeleteCommand('Hgrecordabort')
    call l:buf_obj.DeleteCommand('Hgrecordcommit')
    unlet b:lawrencium_record_for
    unlet b:lawrencium_record_other_nr
endfunction

