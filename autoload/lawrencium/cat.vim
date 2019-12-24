
function! lawrencium#cat#init() abort
    call lawrencium#add_reader('rev', 'lawrencium#cat#read')
endfunction

function! lawrencium#cat#read(repo, path_parts, full_path) abort
    let l:rev = a:path_parts['value']
    if l:rev == ''
        call a:repo.ReadCommandOutput('cat', a:full_path)
    else
        call a:repo.ReadCommandOutput('cat', '-r', l:rev, s:absolute_pathname(a:repo, a:full_path, l:rev))
    endif
endfunction

function! s:absolute_pathname(repo, current_absolute_pathname, revision)
    if a:revision ==# 'p1()'
        let name_of_copied_file = matchstr(
                    \ a:repo.RunCommand('status', '--copies', a:current_absolute_pathname),
                    \ "^A [^\n]\\+\n  \\zs[^\n]\\+")
        if !empty(name_of_copied_file)
            return a:repo.root_dir . '/' . name_of_copied_file
        endif
    else
        " TODO: handle a:revision != 'p1()'
    endif
    return a:current_absolute_pathname
endfunction
