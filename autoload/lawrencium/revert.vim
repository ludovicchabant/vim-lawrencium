
function! lawrencium#revert#init() abort
    call lawrencium#add_command("-bang -nargs=* -complete=customlist,lawrencium#list_repo_files Hgrevert :call lawrencium#revert#HgRevert(<bang>0, <f-args>)")
endfunction

function! lawrencium#revert#HgRevert(bang, ...) abort
    " Get the files to revert.
    let l:filenames = a:000
    if a:0 == 0
        let l:filenames = [ expand('%:p') ]
    endif
    if a:bang
        call insert(l:filenames, '--no-backup', 0)
    endif

    " Get the repo and run the command.
    let l:repo = lawrencium#hg_repo()
    call l:repo.RunCommand('revert', l:filenames)

    " Re-edit the file to see the change.
    edit
endfunction

