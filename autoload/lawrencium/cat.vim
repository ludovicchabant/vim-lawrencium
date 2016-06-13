
function! lawrencium#cat#init() abort
    call lawrencium#add_reader('rev', 'lawrencium#cat#read')
endfunction

function! lawrencium#cat#read(repo, path_parts, full_path) abort
    let l:rev = a:path_parts['value']
    if l:rev == ''
        call a:repo.ReadCommandOutput('cat', a:full_path)
    else
        call a:repo.ReadCommandOutput('cat', '-r', l:rev, a:full_path)
    endif
endfunction

