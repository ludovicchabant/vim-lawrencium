
function! lawrencium#vimutils#init() abort
    call lawrencium#add_command("-bang -nargs=1 -complete=customlist,lawrencium#list_repo_files Hgedit :call lawrencium#vimutils#HgEdit(<bang>0, <f-args>)")

    call lawrencium#add_command("-bang -nargs=? -complete=customlist,lawrencium#list_repo_dirs Hgcd :cd<bang> `=lawrencium#hg_repo().GetFullPath(<q-args>)`")
    call lawrencium#add_command("-bang -nargs=? -complete=customlist,lawrencium#list_repo_dirs Hglcd :lcd<bang> `=lawrencium#hg_repo().GetFullPath(<q-args>)`")
    
    call lawrencium#add_command("-bang -nargs=+ -complete=customlist,lawrencium#list_repo_files Hgvimgrep :call lawrencium#vimutils#HgVimGrep(<bang>0, <f-args>)")
endfunction

" Hgedit {{{

function! lawrencium#vimutils#HgEdit(bang, filename) abort
    let l:full_path = lawrencium#hg_repo().GetFullPath(a:filename)
    if a:bang
        execute "edit! " . fnameescape(l:full_path)
    else
        execute "edit " . fnameescape(l:full_path)
    endif
endfunction

" }}}

" Hgvimgrep {{{

function! lawrencium#vimutils#HgVimGrep(bang, pattern, ...) abort
    let l:repo = lawrencium#hg_repo()
    let l:file_paths = []
    if a:0 > 0
        for ff in a:000
            let l:full_ff = l:repo.GetFullPath(ff)
            call add(l:file_paths, l:full_ff)
        endfor
    else
        call add(l:file_paths, l:repo.root_dir . "**")
    endif
    if a:bang
        execute "vimgrep! " . a:pattern . " " . join(l:file_paths, " ")
    else
        execute "vimgrep " . a:pattern . " " . join(l:file_paths, " ")
    endif
endfunction

" }}}

