" TODO: handle !has('signs')
" TODO: handle signs clearing when server exits
" https://github.com/vim/vim/pull/3652
let s:supports_signs = has('signs')
let s:has_sign_define = has('patch-8.1.0772') && exists('*sign_define')
let s:enabled = 0
let s:signs = {} " { server_name: { path: {} } }
let s:severity_sign_names_mapping = {
    \ 1: 'LspError',
    \ 2: 'LspWarning',
    \ 3: 'LspInformation',
    \ 4: 'LspHint',
    \ }

let s:sign_ids = {}
  function! s:sign_define(sign_name, options)
    let l:command = 'sign define ' . a:sign_name 
        \ . ' text=' . a:options['text'] . ' '
        \ . ' texthl=' . a:options['texthl'] . ' '
        \ . ' linehl=' . a:options['linehl']

    if has_key(a:options, 'icon') 
      let l:command = l:command . ' icon=' . a:options['icon']
    endif

    execute l:command
  endfunction

  function! s:sign_undefine(sign_name)
    execute 'sign undefine ' . a:sign_name
  endfunction

  function! s:sign_place(sign_id, sign_group, sign_name, path, lines) 
    echom 'SIGN_PLACE'
    " calculating sign id
    let l:sign_id = a:sign_id
    if l:sign_id == 0
      echom 'Calculating sign id...'
      let l:index = 1
      if !has_key(s:sign_ids, a:path)
        let s:sign_ids[a:path] = { }
      endif

      while l:sign_id == 0
        if !has_key(s:sign_ids[a:path], l:index) 
          let l:sign_id = l:index
          let s:sign_ids[a:path][l:index] = a:sign_group
        else 
          let l:index = l:index + 1
        endif
      endwhile
      echom 'calculated id: ' . l:sign_id
    endif
    try 

      let l:command = 'sign place ' . l:sign_id 
        \ . ' line=' . a:lines['lnum'] 
        \ . ' name=' . a:sign_name
        \ . ' file=' . a:path
    catch
      echom v:exception
    endtry

    echom l:command
    execute l:command
    echom 'Sign placed'
    return l:sign_id
  endfunction

  function! s:sign_unplace(sign_group, location)
    try 
      echom 'Unplacing signs in group: ' . a:sign_group
      let l:file = a:location.buffer
      echom 'file: ' . l:file
      if has_key(s:sign_ids, l:file) 
        for item in items(s:sign_ids[l:file]) 
          if a:sign_group == item[1] 
            echom 'Unplacing sign #' . item[0] . ' From file ' . l:file
            execute 'sign unplace ' . item[0] . ' file=' . l:file
            unlet s:sign_ids[l:file][item[0]]
          endif
        endfor
      else 
        echom 'No signs found for the file'
      endif
    catch
      echom v:exception
    endtry
  endfunction

if !hlexists('LspErrorText')
    highlight link LspErrorText Error
endif

if !hlexists('LspWarningText')
    highlight link LspWarningText Todo
endif

if !hlexists('LspInformationText')
    highlight link LspInformationText Normal
endif

if !hlexists('LspHintText')
    highlight link LspHintText Normal
endif

function! lsp#ui#vim#signs#enable() abort
    if !s:supports_signs
        call lsp#log('vim-lsp signs requires patch-8.1.0772')
        return
    endif
    if !s:enabled
        call s:define_signs()
        let s:enabled = 1
        call lsp#log('vim-lsp signs enabled')
    endif
endfunction

" Set default sign text to handle case when user provides empty dict
function! s:add_sign(sign_name, sign_default_text, sign_options) abort
    if !s:supports_signs | return | endif
    let l:options = {
      \ 'text': get(a:sign_options, 'text', a:sign_default_text),
      \ 'texthl': a:sign_name . 'Text',
      \ 'linehl': a:sign_name . 'Line',
      \ }
    let l:sign_icon = get(a:sign_options, 'icon', '')
    if !empty(l:sign_icon)
        let l:options['icon'] = l:sign_icon
    endif
    call s:sign_define(a:sign_name, l:options)
endfunction

function! s:define_signs() abort
    if !s:supports_signs | return | endif
    " let vim handle errors/duplicate instead of us maintaining the state
    call s:add_sign('LspError', 'E>', g:lsp_signs_error)
    call s:add_sign('LspWarning', 'W>', g:lsp_signs_warning)
    call s:add_sign('LspInformation', 'I>', g:lsp_signs_information)
    call s:add_sign('LspHint', 'H>', g:lsp_signs_hint)
endfunction

function! lsp#ui#vim#signs#disable() abort
    if s:enabled
        call s:clear_all_signs()
        call s:undefine_signs()
        let s:enabled = 0
        call lsp#log('vim-lsp signs disabled')
    endif
endfunction

function! s:clear_all_signs() abort
    if !s:supports_signs | return | endif
    for l:server_name in lsp#get_server_names()
        let l:sign_group = s:get_sign_group(l:server_name)
        call sign_unplace(l:sign_group)
    endfor
endfunction

function! s:undefine_signs() abort
    if !s:supports_signs | return | endif
    call s:sign_undefine('LspError')
    call s:sign_undefine('LspWarning')
    call s:sign_undefine('LspInformation')
    call s:sign_undefine('LspHint')
endfunction

function! lsp#ui#vim#signs#set(server_name, data) abort
    echom 'signset'
    if !s:supports_signs | return | endif
    echom 'signs supported'
    if !s:enabled | return | endif
    echom 'signs enabled'

    if lsp#client#is_error(a:data['response'])
        return
    endif

    let l:uri = a:data['response']['params']['uri']
    let l:diagnostics = a:data['response']['params']['diagnostics']

    let l:path = lsp#utils#uri_to_path(l:uri)

    " will always replace existing set
    echom 'SIGNSET: render cycle'
    call s:clear_signs(a:server_name, l:path)
    call s:place_signs(a:server_name, l:path, l:diagnostics)
endfunction

function! s:clear_signs(server_name, path) abort
    if !s:supports_signs || !bufloaded(a:path) | return | endif
    let l:sign_group = s:get_sign_group(a:server_name)
    call s:sign_unplace(l:sign_group, { 'buffer': a:path })
endfunction

function! s:get_sign_group(server_name) abort
    return 'vim_lsp_' . a:server_name
endfunction

function! s:place_signs(server_name, path, diagnostics) abort
    echom 'place_signs call'
    if !s:supports_signs | return | endif
    echom 'signs supported'

    let l:sign_group = s:get_sign_group(a:server_name)
    echom 'sign group: ' . l:sign_group

    if !empty(a:diagnostics) && bufnr(a:path) >= 0
        echom 'Displaying signs...'
        for l:item in a:diagnostics
            let l:line = l:item['range']['start']['line'] + 1

            if has_key(l:item, 'severity') && !empty(l:item['severity'])
                let l:sign_name = get(s:severity_sign_names_mapping, l:item['severity'], 'LspError')
                " pass 0 and let vim generate sign id
                echom 'Placing sign at line ' . l:line
                let l:sign_id = s:sign_place(0, l:sign_group, l:sign_name, a:path, { 'lnum': l:line })

                call lsp#log('add signs', l:sign_id)
            endif
        endfor
    endif
endfunction
" vim sw=4 ts=4 et
