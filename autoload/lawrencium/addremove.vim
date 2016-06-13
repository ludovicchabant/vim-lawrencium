
function! lawrencium#addremove#init() abort
    call lawrencium#add_command("-bang -nargs=* -complete=customlist,lawrencium#list_repo_files Hgremove :call lawrencium#addremove#HgRemove(<bang>0, <f-args>)")
endfunction

function! lawrencium#addremove#HgRemove(bang, ...) abort
    " Get the files to remove.
    let l:filenames = a:000
    if a:0 == 0
        let l:filenames = [ expand('%:p') ]
    endif
    if a:bang
        call insert(l:filenames, '--force', 0)
    endif

    " Get the repo and run the command.
    let l:repo = lawrencium#hg_repo()
    call l:repo.RunCommand('rm', l:filenames)

    " Re-edit the file to see the change.
    edit
endfunction

