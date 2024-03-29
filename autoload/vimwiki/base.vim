" vim:tabstop=2:shiftwidth=2:expandtab:foldmethod=marker:textwidth=79
" Vimwiki autoload plugin file
" Author: Maxim Kim <habamax@gmail.com>
" Home: http://code.google.com/p/vimwiki/

if exists("g:loaded_vimwiki_auto") || &cp
  finish
endif
let g:loaded_vimwiki_auto = 1

" MISC helper functions {{{

function! vimwiki#base#reset_wiki_state(...) "{{{ initialize wiki options and
  " additional ['key', value] pairs. E.g. reset_wiki_state(['idx', 0]) sets:
  "   let g:vimwiki_current_idx = 0 " current value
  "   let b:vimwiki_idx = 0         " buffer-cached value
  " ['key', value] pairs
  let g:vimwiki_current_keys = {}
  for keyval_pair in a:000
    let g:vimwiki_current_keys[keyval_pair[0]] = 1
    let g:vimwiki_current_{keyval_pair[0]} = keyval_pair[1]
  endfor
  " wiki options
  let option_dict = VimwikiGetOptions()
  for kk in keys(option_dict)
    let g:vimwiki_current_{kk} = option_dict[kk]
  endfor
  " update cache
  call vimwiki#base#cache_wiki_state()
endfunction "}}}

function! vimwiki#base#cache_wiki_state() "{{{ cache wiki options and state
  " ['key', value] pairs
  for kk in keys(g:vimwiki_current_keys)
    if !exists('g:vimwiki_current_'.kk) && g:vimwiki_debug
      echo "[Vimwiki Internal Error]: Missing global state variable: 'g:vimwiki_current_".kk."'"
    endif
    let b:vimwiki_{kk} = g:vimwiki_current_{kk}
  endfor
  " wiki options
  for kk in VimwikiGetOptionNames()
    if !exists('g:vimwiki_current_'.kk) && g:vimwiki_debug
      echo "[Vimwiki Error]: Missing global state variable: 'g:vimwiki_current_".kk."'"
    endif
    let b:vimwiki_{kk} = g:vimwiki_current_{kk}
  endfor
endfunction "}}}

function! vimwiki#base#recall_wiki_state() "{{{ try loading wiki options
  "   previously saved to buffer state, return 0 if cache is incomplete
  " ['key', value] pairs
  if !exists('g:vimwiki_current_keys')
    return 0
  endif
  for kk in keys(g:vimwiki_current_keys)
    if !exists('b:vimwiki_'.kk) 
      if g:vimwiki_debug
        echo "[Vimwiki Internal Error]: Missing buffer state variable: 'b:vimwiki_".kk."'"
      endif
      return 0
    endif
    let g:vimwiki_current_{kk} = b:vimwiki_{kk}
  endfor
  " wiki options
  for kk in VimwikiGetOptionNames()
    if !exists('b:vimwiki_'.kk) 
      if g:vimwiki_debug
        echo "[Vimwiki Internal Error]: Missing buffer state variable: 'b:vimwiki_".kk."'"
      endif
      return 0
    endif
    let g:vimwiki_current_{kk} = b:vimwiki_{kk}
  endfor
  return 1
endfunction "}}}

function! vimwiki#base#time(starttime) "{{{
  " measure the elapsed time and cut away miliseconds and smaller
  return matchstr(reltimestr(reltime(a:starttime)),'\d\+\(\.\d\d\)\=')
endfunction "}}}

function! vimwiki#base#chomp_slash(str) "{{{
  return substitute(a:str, '[/\\]\+$', '', '')
endfunction "}}}

function! vimwiki#base#path_norm(path) "{{{
  " /-slashes
  let path = substitute(a:path, '\', '/', 'g')
  " treat multiple consecutive slashes as one path separator
  let path = substitute(path, '/\+', '/', 'g')
  " ensure that we are not fooled by a symbolic link
  return resolve(path)
endfunction "}}}

" If the optional argument 'confirm' == 1 is provided,
" vimwiki#base#mkdir will ask before creating a directory 
function! vimwiki#base#mkdir(path, ...) "{{{
  let path = expand(a:path)
  if !isdirectory(path) && exists("*mkdir")
    let path = vimwiki#base#chomp_slash(path)
    if s:is_windows() && !empty(g:vimwiki_w32_dir_enc)
      let path = iconv(path, &enc, g:vimwiki_w32_dir_enc)
    endif
    if a:0 && a:1 && tolower(input("Vimwiki: Make new directory: ".path."\n [Y]es/[n]o? ")) !~ "y"
      return 0
    endif
    call mkdir(path, "p")
  endif
  return 1
endfunction
" }}}

function! vimwiki#base#file_pattern(files) "{{{ get search regex from glob() string
  " FIXME needless complications ensue just to support silly "filenames" which
  " some filesystems may not handle well; also nonstandard paths
  " Change / to [/\\] to allow "Windows paths" 
  let os_p2 = '[/\\\\]'   "in the end, only [/\\] will survive in regexp
  let pattern = vimwiki#base#branched_pattern(a:files,"\n")
  let pattern = substitute(pattern, '/', os_p2, "g")   "XXX  ???
  let pattern = escape(pattern, '~&$.*')       "special chars for search
  return pattern
endfunction
"}}}

function! vimwiki#base#branched_pattern(string,separator) "{{{ get search regex
" from a string-list; separators assumed at start and end as well
  let pattern = substitute(a:string, a:separator, '\\|','g')
  let pattern = substitute(pattern, '\%^\\|', '\\%(','')
  let pattern = substitute(pattern,'\\|\%$', '\\)','')
  return pattern
endfunction
"}}}

"FIXME TODO slow and faulty
function! vimwiki#base#subdir(path, filename)"{{{
  let g:VimwikiLog.subdir += 1  "XXX
  let path = a:path
  " ensure that we are not fooled by a symbolic link
  "FIXME if we are not "fooled", we end up in a completely different wiki?
  let filename = resolve(a:filename)
  let idx = 0
  "FIXME this can terminate in the middle of a path component!
  while path[idx] ==? filename[idx]
    let idx = idx + 1
  endwhile

  let p = split(strpart(filename, idx), '[/\\]')
  let res = join(p[:-2], '/')
  if len(res) > 0
    let res = res.'/'
  endif
  return res
endfunction"}}}

function! vimwiki#base#current_subdir()"{{{
  return vimwiki#base#subdir(VimwikiGet('path'), expand('%:p'))
endfunction"}}}

function! vimwiki#base#resolve_scheme(lnk, as_html) " {{{
  " schemeless
  let lnk = a:lnk
  let is_schemeless = lnk !~ g:vimwiki_rxSchemeUrl
  let lnk = (is_schemeless  ? 'wiki'.g:vimwiki_current_idx.':'.lnk : lnk)
  " parse
  let scheme = matchstr(lnk, g:vimwiki_rxSchemeUrlMatchScheme)
  let lnk = matchstr(lnk, g:vimwiki_rxSchemeUrlMatchUrl)
  let path = ''
  let subdir = ''
  let ext = ''
  if !(scheme =~ 'wiki*' || scheme =~ 'diary*' || scheme =~ 'local*' 
        \ || scheme =~ 'file')
    return [scheme, path, subdir, lnk, ext, scheme.':'.lnk]
  endif
  "
  " schemes below here resolve to the local filesystem, although 'file:///' 
  " is omitted when the schemeless syntax is used
  "
  " scheme behaviors
  let numbered_scheme = 0
  let add_path = 0
  let html_path = 0
  let diary_rel_path = 0
  let wiki_subdirectory = 0
  let wiki_extension = 0
  let wiki_directory = 0
  if scheme =~ 'wiki*'
    let numbered_scheme = 1
    let add_path = 1
    let html_path = 1
    let wiki_subdirectory = 1
    let wiki_extension = 1
    let wiki_directory = 1
  elseif scheme =~ 'diary*'
    let add_path = 1
    let html_path = 1
    let diary_rel_path = 1
    let wiki_extension = 1
  elseif scheme =~ 'local*'
    let add_path = 1
    "XXX: local-schemes work like wiki-schemes with regards to subdirs
    let wiki_subdirectory = 1
  endif

  " numbered scheme
  if numbered_scheme && scheme =~ '\D\+\d\+'
    let idx = eval(matchstr(scheme, '\D\+\zs\d\+\ze'))
    if idx < 0 || idx >= len(g:vimwiki_list)
      echom 'Vimwiki Error: Numbered scheme refers to a non-existent wiki!'
      return ['','','','','','']
    endif
  else
    let idx = g:vimwiki_current_idx
  endif

  " path
  if add_path
    if html_path && a:as_html
      if idx == g:vimwiki_current_idx
        let path = g:vimwiki_current_path_html
      else
        let path = VimwikiGet('path_html', idx)
      endif
    else
      if idx == g:vimwiki_current_idx
        let path = g:vimwiki_current_path
      else
        let path = VimwikiGet('path', idx)
      endif
    endif
  endif

  " relative path for diary
  if diary_rel_path
    if idx == g:vimwiki_current_idx
      let path = path. g:vimwiki_current_diary_rel_path
    else
      let path = path. VimwikiGet('diary_rel_path', idx)
    endif
  endif

  " subdir
  if wiki_subdirectory && idx == g:vimwiki_current_idx
    let subdir = g:vimwiki_current_subdir
  endif

  " extension
  if wiki_extension
    if a:as_html
      let ext = '.html'
    else
      if idx == g:vimwiki_current_idx
        let ext = g:vimwiki_current_ext
      else
        let ext = VimwikiGet('ext', idx)
      endif
    endif
    " default link for directories
    if wiki_directory && vimwiki#base#is_link_to_dir(lnk)
      let ext = (g:vimwiki_dir_link != '' ? g:vimwiki_dir_link. ext : '')
    endif
  endif

  " remove repeated /'s
  let path = substitute(path, '/\+', '/', 'g')
  let subdir = substitute(subdir, '/\+', '/', 'g')
  let lnk = substitute(lnk, '/\+', '/', 'g')
  " is there a better way?
  if has('win16') || has('win32') || has('win64')
    let lnk = substitute(lnk, '^/\ze[[:alpha:]]:', '', '')
  endif

  " construct url from parts
  if is_schemeless && a:as_html
    let scheme = ''
    " Stu had the following: 
    "let url = subdir.lnk.ext
    " Tomas had the following: 
    let url = lnk.ext
  else
    " ensure there are three slashes after 'file:'
    let url = 'file:///'.path.subdir.lnk.ext
    let url = substitute(url, '^file:/*', 'file:///', '')
  endif

  " result
  return [scheme, path, subdir, lnk, ext, url]
endfunction "}}}

function! vimwiki#base#open_link(cmd, link, ...) "{{{
  " resolve url
  let [scheme, path, subdir, lnk, ext, url] = 
        \ vimwiki#base#resolve_scheme(a:link, 0)
  if lnk == ''
    echom 'Vimwiki Error: Unable to resolve link!'
    return
  endif
  let update_prev_link = (
        \ scheme == '' || 
        \ scheme =~ 'wiki*' || 
        \ scheme =~ 'diary*' ? 1 : 0)
  let use_weblink_handler = (
        \ scheme == '' || 
        \ scheme =~ 'wiki*' || 
        \ scheme =~ 'diary*' || 
        \ scheme =~ 'local*' || 
        \ scheme =~ 'file' ? 0 : 1)
  " update previous link for wiki pages
  if update_prev_link
    if a:0
      let vimwiki_prev_link = [a:1, []]
    elseif &ft == 'vimwiki'
      let vimwiki_prev_link = [expand('%:p'), getpos('.')]
    endif
  endif
  " open/edit
  if g:vimwiki_debug
    echom 'open_link: scheme='.scheme.', path='.path.', subdir='.subdir.', lnk='.lnk.', ext='.ext
  endif
  if use_weblink_handler
    call VimwikiWeblinkHandler(url)
  else
    " rm duplicate /-chars
    call vimwiki#base#edit_file(a:cmd, 
          \ substitute(path.subdir.lnk.ext, '^/\+', '/', ''))
  endif
  " save previous link
  if update_prev_link && exists('vimwiki_prev_link')
    let b:vimwiki_prev_link = vimwiki_prev_link
  endif
endfunction
" }}}

function! vimwiki#base#select(wnum)"{{{
  if a:wnum < 1 || a:wnum > len(g:vimwiki_list)
    return
  endif
  if &ft == 'vimwiki'
    " initialize buffer vars with current state (including current_idx, etc)
    call vimwiki#base#cache_wiki_state()
  endif
  let g:vimwiki_current_idx = a:wnum - 1
endfunction
" }}}


function! vimwiki#base#generate_links() "{{{only get links from the current dir
  " change to the directory of the current file
  let orig_pwd = getcwd()
  lcd! %:h
  " all path are relative to the current file's location 
  let globlinks = glob('*'.VimwikiGet('ext'),1)."\n"
  " remove extensions
  let globlinks = substitute(globlinks, '\'.VimwikiGet('ext').'\ze\n', '', 'g')
  " restore the original working directory
  exe 'lcd! '.orig_pwd

  " We don't want link to itself. XXX Why ???
  " let cur_link = expand('%:t:r')
  " call filter(links, 'v:val != cur_link')
  let links = split(globlinks,"\n")
  call append(line('$'), '= Generated Links =')
  call sort(links)

  for link in links
    call append(line('$'), '- [['.link.']]')
  endfor
endfunction " }}}

function! vimwiki#base#goto(key) "{{{
    call vimwiki#base#edit_file(':e',
          \ VimwikiGet('path').
          \ a:key.
          \ VimwikiGet('ext'))
endfunction "}}}

function! vimwiki#base#backlinks() "{{{
    execute 'lvimgrep "\%(^\|[[:blank:][:punct:]]\)'.
          \ expand("%:t:r").
          \ '\([[:blank:][:punct:]]\|$\)" '. 
          \ escape(VimwikiGet('path').'**/*'.VimwikiGet('ext'), ' ')
endfunction "}}}

function! s:is_windows() "{{{
  return has("win32") || has("win64") || has("win95") || has("win16")
endfunction "}}}

function! s:is_path_absolute(path) "{{{
  return a:path =~ '^/.*' || a:path =~ '^[[:alpha:]]:[/\\].*'
endfunction "}}}

"TODO
function! vimwiki#base#get_links(pat) "{{{ return string-list for files
  " in the current wiki matching the pattern "pat"
  " search all wiki files (or directories) in wiki 'path' and its subdirs.
  let subdir = g:vimwiki_current_subdir
  let invsubdir = substitute(subdir,'[^/]\+','..','g')
  " if current wiki is temporary -- was added by an arbitrary wiki file then do
  " not search wiki files in subdirectories. Or it would hang the system if
  " wiki file was created in $HOME or C:/ dirs.
  if VimwikiGet('temp') 
    let search_dirs = ''
  else
    let search_dirs = '**/'
  endif
  let time1 = reltime()  " start the clock  XXX
  "save pwd, do lcd %:h, restore old pwd; getcwd()
  let globlinks = "\n".glob(VimwikiGet('path').search_dirs.a:pat,1)."\n"
  let time2 = vimwiki#base#time(time1)  " XXX

  " change to the directory of the current file
  let orig_pwd = getcwd()
  lcd! %:h
  " all path are relative to the current file's location 
  let globlinks = "\n".glob(invsubdir.search_dirs.a:pat,1)."\n"
  " remove extensions
  let globlinks = substitute(globlinks,'\'.VimwikiGet('ext').'\ze\n', '', 'g')
  " standardize path separators on Windows
  let globlinks = substitute(globlinks,'\\', '/', 'g')

  " shortening those paths ../../dir1/dir2/ that can be shortened
  " first for the current directory, then for parent etc.
  let sp_rx = '\n\zs' . invsubdir . subdir . '\ze'
  for i in range(len(invsubdir)/3)   "XXX multibyte?
    let globlinks = substitute(globlinks, sp_rx, '', 'g')
    let sp_rx = substitute(sp_rx,'\\zs../','../\\zs','')
    let sp_rx = substitute(sp_rx,'[^/]\+/\\ze','\\ze','')
  endfor
  " for directories: add ./ (instead of now empty) and invsubdir (if distinct)
  if a:pat == '*/'
    let globlinks = substitute(globlinks, "\n\n", "\n./\n",'') 
    if invsubdir != ''
      let globlinks .= invsubdir."\n"
    else
      let globlinks .= "./\n"
    endif
  endif
  "let g:VimwikiLog.globlinks = globlinks
  " restore the original working directory
  exe 'lcd! '.orig_pwd

  " Remove trailing slashes.  XXX ?
  "call map(links, 'substitute(v:val, "[/\\\\]*$", "", "g")')
  "let time3 = vimwiki#base#time(time1)  "XXX
  call VimwikiLog_extend('timing',['base:afterglob('.len(split(globlinks, '\n')).')',time2])
  return globlinks
endfunction "}}}

function! s:filename(link) "{{{
  " TODO: make it g:vimwiki_rxSep aware
  let result = a:link
  if a:link =~ '|'
    let result = split(a:link, '|')[0]
  elseif a:link =~ ']['
    let result = split(a:link, '][')[0]
  endif
  return result
endfunction
" }}}

"TODO ?
function! s:is_wiki_word(str) "{{{
  if a:str =~ g:vimwiki_rxWikiWord && a:str !~ '[[:space:]\\/]'
    return 1
  endif
  return 0
endfunction
" }}}

function! vimwiki#base#edit_file(command, filename) "{{{
  let fname = escape(a:filename, '% ')
  let dir = fnamemodify(a:filename, ":p:h")
  if vimwiki#base#mkdir(dir, 1)
    execute a:command.' '.fname
  else
    echom ' '
    echom 'Vimwiki: Unable to edit file in non-existent directory: '.dir
  endif
endfunction
" }}}

function! s:search_word(wikiRx, cmd) "{{{
  let match_line = search(a:wikiRx, 's'.a:cmd)
  if match_line == 0
    echomsg 'vimwiki: Wiki link not found.'
  endif
endfunction
" }}}

" Returns part of the line that matches wikiRX at cursor
function! s:matchstr_at_cursor(wikiRX) "{{{
  let col = col('.') - 1
  let line = getline('.')
  let ebeg = -1
  let cont = match(line, a:wikiRX, 0)
  while (ebeg >= 0 || (0 <= cont) && (cont <= col))
    let contn = matchend(line, a:wikiRX, cont)
    if (cont <= col) && (col < contn)
      let ebeg = match(line, a:wikiRX, cont)
      let elen = contn - ebeg
      break
    else
      let cont = match(line, a:wikiRX, contn)
    endif
  endwh
  if ebeg >= 0
    return strpart(line, ebeg, elen)
  else
    return ""
  endif
endf "}}}

function! s:replacestr_at_cursor(wikiRX, sub) "{{{
  let col = col('.') - 1
  let line = getline('.')
  let ebeg = -1
  let cont = match(line, a:wikiRX, 0)
  while (ebeg >= 0 || (0 <= cont) && (cont <= col))
    let contn = matchend(line, a:wikiRX, cont)
    if (cont <= col) && (col < contn)
      let ebeg = match(line, a:wikiRX, cont)
      let elen = contn - ebeg
      break
    else
      let cont = match(line, a:wikiRX, contn)
    endif
  endwh
  if ebeg >= 0
    " TODO: There might be problems with Unicode chars...
    let newline = strpart(line, 0, ebeg).a:sub.strpart(line, ebeg+elen)
    call setline(line('.'), newline)
  endif
endf "}}}

function! s:strip_word(word) "{{{
  let result = a:word
  if strpart(a:word, 0, 2) == "[["
    " get rid of [[ and ]]
    let w = strpart(a:word, 2, strlen(a:word)-4)

    if w =~ '|'
      " we want "link" from [[link|link desc]]
      let w = split(w, "|")[0]
    elseif w =~ ']['
      " we want "link" from [[link][link desc]]
      let w = split(w, "][")[0]
    endif

    let result = w
  endif
  return result
endfunction
" }}}

function! vimwiki#base#is_link_to_dir(link) "{{{
  " Check if link is to a directory.
  " It should be ended with \ or /.
  if a:link =~ '.\+[/\\]$'
    return 1
  endif
  return 0
endfunction " }}}

function! s:print_wiki_list() "{{{
  let idx = 0
  while idx < len(g:vimwiki_list)
    if idx == g:vimwiki_current_idx
      let sep = ' * '
      echohl PmenuSel
    else
      let sep = '   '
      echohl None
    endif
    echo (idx + 1).sep.VimwikiGet('path', idx)
    let idx += 1
  endwhile
  echohl None
endfunction
" }}}

function! s:update_wiki_link(fname, old, new) " {{{
  echo "Updating links in ".a:fname
  let has_updates = 0
  let dest = []
  for line in readfile(a:fname)
    if !has_updates && match(line, a:old) != -1
      let has_updates = 1
    endif
    call add(dest, substitute(line, a:old, escape(a:new, "&"), "g"))
  endfor
  " add exception handling...
  if has_updates
    call rename(a:fname, a:fname.'#vimwiki_upd#')
    call writefile(dest, a:fname)
    call delete(a:fname.'#vimwiki_upd#')
  endif
endfunction
" }}}

function! s:update_wiki_links_dir(dir, old_fname, new_fname) " {{{
  let old_fname = substitute(a:old_fname, '[/\\]', '[/\\\\]', 'g')
  let new_fname = a:new_fname
  let old_fname_r = old_fname
  let new_fname_r = new_fname

  " try WikiLink
  " try WikiIncl
  " try Weblink
  " try Imagelink
  if !s:is_wiki_word(new_fname) && s:is_wiki_word(old_fname)
    let new_fname_r = '[['.new_fname.']]'
  endif

  if !s:is_wiki_word(old_fname)
    let old_fname_r = '\[\[\zs'.old_fname.
          \ '\ze\%(|.*\)\?\%(\]\[.*\)\?\]\]'
  else
    let old_fname_r = '!\@<!\<'.old_fname.'\>'
  endif

  let files = split(glob(VimwikiGet('path').a:dir.'*'.VimwikiGet('ext')), '\n')
  for fname in files
    call s:update_wiki_link(fname, old_fname_r, new_fname_r)
  endfor
endfunction
" }}}

function! s:tail_name(fname) "{{{
  let result = substitute(a:fname, ":", "__colon__", "g")
  let result = fnamemodify(result, ":t:r")
  let result = substitute(result, "__colon__", ":", "g")
  return result
endfunction "}}}

function! s:update_wiki_links(old_fname, new_fname) " {{{
  let old_fname = s:tail_name(a:old_fname)
  let new_fname = s:tail_name(a:new_fname)

  let subdirs = split(a:old_fname, '[/\\]')[: -2]

  " TODO: Use Dictionary here...
  let dirs_keys = ['']
  let dirs_vals = ['']
  if len(subdirs) > 0
    let dirs_keys = ['']
    let dirs_vals = [join(subdirs, '/').'/']
    let idx = 0
    while idx < len(subdirs) - 1
      call add(dirs_keys, join(subdirs[: idx], '/').'/')
      call add(dirs_vals, join(subdirs[idx+1 :], '/').'/')
      let idx = idx + 1
    endwhile
    call add(dirs_keys,join(subdirs, '/').'/')
    call add(dirs_vals, '')
  endif

  let idx = 0
  while idx < len(dirs_keys)
    let dir = dirs_keys[idx]
    let new_dir = dirs_vals[idx]
    call s:update_wiki_links_dir(dir, 
          \ new_dir.old_fname, new_dir.new_fname)
    let idx = idx + 1
  endwhile
endfunction " }}}

function! s:get_wiki_buffers() "{{{
  let blist = []
  let bcount = 1
  while bcount<=bufnr("$")
    if bufexists(bcount)
      let bname = fnamemodify(bufname(bcount), ":p")
      if bname =~ VimwikiGet('ext')."$"
        let bitem = [bname, getbufvar(bname, "vimwiki_prev_link")]
        call add(blist, bitem)
      endif
    endif
    let bcount = bcount + 1
  endwhile
  return blist
endfunction " }}}

function! s:open_wiki_buffer(item) "{{{
  call vimwiki#base#edit_file(':e', a:item[0])
  if !empty(a:item[1])
    call setbufvar(a:item[0], "vimwiki_prev_link", a:item[1])
  endif
endfunction " }}}

function! vimwiki#base#hl_exists(hl) "{{{
  if !hlexists(a:hl)
    return 0
  endif
  redir => hlstatus
  exe "silent hi" a:hl
  redir END
  return (hlstatus !~ "cleared")
endfunction
"}}}

function! vimwiki#base#nested_syntax(filetype, start, end, textSnipHl) abort "{{{
" From http://vim.wikia.com/wiki/VimTip857
  let ft=toupper(a:filetype)
  let group='textGroup'.ft
  if exists('b:current_syntax')
    let s:current_syntax=b:current_syntax
    " Remove current syntax definition, as some syntax files (e.g. cpp.vim)
    " do nothing if b:current_syntax is defined.
    unlet b:current_syntax
  endif

  " Some syntax files set up iskeyword which might scratch vimwiki a bit.
  " Let us save and restore it later.
  " let b:skip_set_iskeyword = 1
  let is_keyword = &iskeyword

  execute 'syntax include @'.group.' syntax/'.a:filetype.'.vim'
  try
    execute 'syntax include @'.group.' after/syntax/'.a:filetype.'.vim'
  catch
  endtry

  let &iskeyword = is_keyword

  if exists('s:current_syntax')
    let b:current_syntax=s:current_syntax
  else
    unlet b:current_syntax
  endif
  execute 'syntax region textSnip'.ft.
        \ ' matchgroup='.a:textSnipHl.
        \ ' start="'.a:start.'" end="'.a:end.'"'.
        \ ' contains=@'.group.' keepend'

  " A workaround to Issue 115: Nested Perl syntax highlighting differs from
  " regular one.
  " Perl syntax file has perlFunctionName which is usually has no effect due to
  " 'contained' flag. Now we have 'syntax include' that makes all the groups
  " included as 'contained' into specific group. 
  " Here perlFunctionName (with quite an angry regexp "\h\w*[^:]") clashes with
  " the rest syntax rules as now it has effect being really 'contained'.
  " Clear it!
  if ft =~ 'perl'
    syntax clear perlFunctionName 
  endif
endfunction "}}}

" }}}

" WIKI link following functions {{{
function! vimwiki#base#find_next_link() "{{{
  call s:search_word(g:vimwiki_rxWikiLink.'\|'.g:vimwiki_rxWikiIncl.'\|'.g:vimwiki_rxWeblink.'\|'.g:vimwiki_rxImagelink, '')
endfunction
" }}}

function! vimwiki#base#find_prev_link() "{{{
  call s:search_word(g:vimwiki_rxWikiLink.'\|'.g:vimwiki_rxWikiIncl.'\|'.g:vimwiki_rxWeblink.'\|'.g:vimwiki_rxImagelink, 'b')
endfunction
" }}}

function! vimwiki#base#follow_link(split, ...) "{{{
  if a:split == "split"
    let cmd = ":split "
  elseif a:split == "vsplit"
    let cmd = ":vsplit "
  elseif a:split == "tabnew"
    let cmd = ":tabnew "
  else
    let cmd = ":e "
  endif

  " try WikiLink
  let lnk = matchstr(s:matchstr_at_cursor(g:vimwiki_rxWikiLink),
        \ g:vimwiki_rxWikiLinkMatchUrl)
  if lnk != ""
    call vimwiki#base#open_link(cmd, lnk)
    return
  endif
  " try WikiIncl
  let lnk = matchstr(s:matchstr_at_cursor(g:vimwiki_rxWikiIncl),
        \ g:vimwiki_rxWikiInclMatchUrl)
  if lnk != ""
    call vimwiki#base#open_link(cmd, lnk)
    return
  endif
  " try Weblink
  let lnk = matchstr(s:matchstr_at_cursor(g:vimwiki_rxWeblink),
        \ g:vimwiki_rxWeblinkMatchUrl)
  if lnk != ""
    call VimwikiWeblinkHandler(lnk)
    return
  endif
  " try Imagelink
  let lnk = matchstr(s:matchstr_at_cursor(g:vimwiki_rxImagelink),
        \ g:vimwiki_rxImagelinkMatchUrl)
  if lnk != ""
    call VimwikiWeblinkHandler(lnk)
    return
  endif

  if a:0 > 0
    execute "normal! ".a:1
  else		
    " execute "normal! \n"
    call vimwiki#base#normalize_link(0)
  endif

endfunction " }}}

function! vimwiki#base#go_back_link() "{{{
  if exists("b:vimwiki_prev_link")
    " go back to saved WikiWord
    let prev_word = b:vimwiki_prev_link
    execute ":e ".substitute(prev_word[0], '\s', '\\\0', 'g')
    call setpos('.', prev_word[1])
  endif
endfunction " }}}

function! vimwiki#base#goto_index(index) "{{{
  call vimwiki#base#select(a:index)
  call vimwiki#base#edit_file('e',
        \ VimwikiGet('path').VimwikiGet('index').VimwikiGet('ext'))
endfunction "}}}

function! vimwiki#base#delete_link() "{{{
  "" file system funcs
  "" Delete WikiWord you are in from filesystem
  let val = input('Delete ['.expand('%').'] (y/n)? ', "")
  if val != 'y'
    return
  endif
  let fname = expand('%:p')
  try
    call delete(fname)
  catch /.*/
    echomsg 'vimwiki: Cannot delete "'.expand('%:t:r').'"!'
    return
  endtry

  call vimwiki#base#go_back_link()
  execute "bdelete! ".escape(fname, " ")

  " reread buffer => deleted WikiWord should appear as non-existent
  if expand('%:p') != ""
    execute "e"
  endif
endfunction "}}}

function! vimwiki#base#rename_link() "{{{
  "" Rename WikiWord, update all links to renamed WikiWord
  let subdir = g:vimwiki_current_subdir
  let old_fname = subdir.expand('%:t')

  " there is no file (new one maybe)
  if glob(expand('%:p')) == ''
    echomsg 'vimwiki: Cannot rename "'.expand('%:p').
          \'". It does not exist! (New file? Save it before renaming.)'
    return
  endif

  let val = input('Rename "'.expand('%:t:r').'" (y/n)? ', "")
  if val!='y'
    return
  endif

  let new_link = input('Enter new name: ', "")

  if new_link =~ '[/\\]'
    " It is actually doable but I do not have free time to do it.
    echomsg 'vimwiki: Cannot rename to a filename with path!'
    return
  endif

  " check new_fname - it should be 'good', not empty
  if substitute(new_link, '\s', '', 'g') == ''
    echomsg 'vimwiki: Cannot rename to an empty filename!'
    return
  endif

  let new_link = subdir.new_link
  let new_link = s:strip_word(new_link)
  let new_fname = VimwikiGet('path').s:filename(new_link).VimwikiGet('ext')

  " do not rename if word with such name exists
  let fname = glob(new_fname)
  if fname != ''
    echomsg 'vimwiki: Cannot rename to "'.new_fname.
          \ '". File with that name exist!'
    return
  endif
  " rename WikiWord file
  try
    echomsg "Renaming ".VimwikiGet('path').old_fname." to ".new_fname
    let res = rename(expand('%:p'), expand(new_fname))
    if res != 0
      throw "Cannot rename!"
    end
  catch /.*/
    echomsg 'vimwiki: Cannot rename "'.expand('%:t:r').'" to "'.new_fname.'"'
    return
  endtry

  let &buftype="nofile"

  let cur_buffer = [expand('%:p'),
        \getbufvar(expand('%:p'), "vimwiki_prev_link")]

  let blist = s:get_wiki_buffers()

  " save wiki buffers
  for bitem in blist
    execute ':b '.escape(bitem[0], ' ')
    execute ':update'
  endfor

  execute ':b '.escape(cur_buffer[0], ' ')

  " remove wiki buffers
  for bitem in blist
    execute 'bwipeout '.escape(bitem[0], ' ')
  endfor

  let setting_more = &more
  setlocal nomore

  " update links
  call s:update_wiki_links(old_fname, new_link)

  " restore wiki buffers
  for bitem in blist
    if bitem[0] != cur_buffer[0]
      call s:open_wiki_buffer(bitem)
    endif
  endfor

  call s:open_wiki_buffer([new_fname,
        \ cur_buffer[1]])
  " execute 'bwipeout '.escape(cur_buffer[0], ' ')

  echomsg old_fname." is renamed to ".new_fname

  let &more = setting_more
endfunction " }}}

function! vimwiki#base#ui_select() "{{{
  call s:print_wiki_list()
  let idx = input("Select Wiki (specify number): ")
  if idx == ""
    return
  endif
  call vimwiki#base#goto_index(idx)
endfunction
"}}}
" }}}

" TEXT OBJECTS functions {{{

function! vimwiki#base#TO_header(inner, visual) "{{{
  if !search('^\(=\+\).\+\1\s*$', 'bcW')
    return
  endif
  
  let sel_start = line("'<")
  let sel_end = line("'>")
  let block_start = line(".")
  let advance = 0

  let level = vimwiki#base#count_first_sym(getline('.'))

  let is_header_selected = sel_start == block_start 
        \ && sel_start != sel_end

  if a:visual && is_header_selected
    if level > 1
      let level -= 1
      call search('^\(=\{'.level.'\}\).\+\1\s*$', 'bcW')
    else
      let advance = 1
    endif
  endif

  normal! V

  if a:visual && is_header_selected
    call cursor(sel_end + advance, 0)
  endif

  if search('^\(=\{1,'.level.'}\).\+\1\s*$', 'W')
    call cursor(line('.') - 1, 0)
  else
    call cursor(line('$'), 0)
  endif

  if a:inner && getline(line('.')) =~ '^\s*$'
    let lnum = prevnonblank(line('.') - 1)
    call cursor(lnum, 0)
  endif
endfunction
"}}}

function! vimwiki#base#TO_table_cell(inner, visual) "{{{
  if col('.') == col('$')-1
    return
  endif

  if a:visual
    normal! `>
    let sel_end = getpos('.')
    normal! `<
    let sel_start = getpos('.')

    let firsttime = sel_start == sel_end

    if firsttime
      if !search('|\|\(-+-\)', 'cb', line('.'))
        return
      endif
      if getline('.')[virtcol('.')] == '+'
        normal! l
      endif
      if a:inner
        normal! 2l
      endif
      let sel_start = getpos('.')
    endif

    normal! `>
    call search('|\|\(-+-\)', '', line('.'))
    if getline('.')[virtcol('.')] == '+'
      normal! l
    endif
    if a:inner
      if firsttime || abs(sel_end[2] - getpos('.')[2]) != 2
        normal! 2h
      endif
    endif
    let sel_end = getpos('.')

    call setpos('.', sel_start)
    exe "normal! \<C-v>"
    call setpos('.', sel_end)

    " XXX: WORKAROUND.
    " if blockwise selection is ended at | character then pressing j to extend
    " selection furhter fails. But if we shake the cursor left and right then
    " it works.
    normal! hl
  else
    if !search('|\|\(-+-\)', 'cb', line('.'))
      return
    endif
    if a:inner
      normal! 2l
    endif
    normal! v
    call search('|\|\(-+-\)', '', line('.'))
    if !a:inner && getline('.')[virtcol('.')-1] == '|'
      normal! h
    elseif a:inner
      normal! 2h
    endif
  endif
endfunction "}}}

function! vimwiki#base#TO_table_col(inner, visual) "{{{
  let t_rows = vimwiki#tbl#get_rows(line('.'))
  if empty(t_rows)
    return
  endif

  " TODO: refactor it!
  if a:visual
    normal! `>
    let sel_end = getpos('.')
    normal! `<
    let sel_start = getpos('.')

    let firsttime = sel_start == sel_end

    if firsttime
      " place cursor to the top row of the table
      call vimwiki#u#cursor(t_rows[0][0], virtcol('.'))
      " do not accept the match at cursor position if cursor is next to column
      " separator of the table separator (^ is a cursor):
      " |-----^-+-------|
      " | bla   | bla   |
      " |-------+-------|
      " or it will select wrong column.
      if strpart(getline('.'), virtcol('.')-1) =~ '^-+'
        let s_flag = 'b'
      else
        let s_flag = 'cb'
      endif
      " search the column separator backwards
      if !search('|\|\(-+-\)', s_flag, line('.'))
        return
      endif
      " -+- column separator is matched --> move cursor to the + sign
      if getline('.')[virtcol('.')] == '+'
        normal! l
      endif
      " inner selection --> reduce selection
      if a:inner
        normal! 2l
      endif
      let sel_start = getpos('.')
    endif

    normal! `>
    if !firsttime && getline('.')[virtcol('.')] == '|'
      normal! l
    elseif a:inner && getline('.')[virtcol('.')+1] =~ '[|+]'
      normal! 2l
    endif
    " search for the next column separator
    call search('|\|\(-+-\)', '', line('.'))
    " Outer selection selects a column without border on the right. So we move
    " our cursor left if the previous search finds | border, not -+-.
    if getline('.')[virtcol('.')] != '+'
      normal! h
    endif
    if a:inner
      " reduce selection a bit more if inner.
      normal! h
    endif
    " expand selection to the bottom line of the table
    call vimwiki#u#cursor(t_rows[-1][0], virtcol('.'))
    let sel_end = getpos('.')

    call setpos('.', sel_start)
    exe "normal! \<C-v>"
    call setpos('.', sel_end)

  else
    " place cursor to the top row of the table
    call vimwiki#u#cursor(t_rows[0][0], virtcol('.'))
    " do not accept the match at cursor position if cursor is next to column
    " separator of the table separator (^ is a cursor):
    " |-----^-+-------|
    " | bla   | bla   |
    " |-------+-------|
    " or it will select wrong column.
    if strpart(getline('.'), virtcol('.')-1) =~ '^-+'
      let s_flag = 'b'
    else
      let s_flag = 'cb'
    endif
    " search the column separator backwards
    if !search('|\|\(-+-\)', s_flag, line('.'))
      return
    endif
    " -+- column separator is matched --> move cursor to the + sign
    if getline('.')[virtcol('.')] == '+'
      normal! l
    endif
    " inner selection --> reduce selection
    if a:inner
      normal! 2l
    endif

    exe "normal! \<C-V>"

    " search for the next column separator
    call search('|\|\(-+-\)', '', line('.'))
    " Outer selection selects a column without border on the right. So we move
    " our cursor left if the previous search finds | border, not -+-.
    if getline('.')[virtcol('.')] != '+'
      normal! h
    endif
    " reduce selection a bit more if inner.
    if a:inner
      normal! h
    endif
    " expand selection to the bottom line of the table
    call vimwiki#u#cursor(t_rows[-1][0], virtcol('.'))
  endif
endfunction "}}}
" }}}

" HEADER functions {{{
function! vimwiki#base#count_first_sym(line) "{{{
  let first_sym = matchstr(a:line, '\S')
  return len(matchstr(a:line, first_sym.'\+'))
endfunction "}}}

function! vimwiki#base#AddHeaderLevel() "{{{
  let lnum = line('.')
  let line = getline(lnum)
  let rxHdr = g:vimwiki_rxH
  if line =~ '^\s*$'
    return
  endif

  if line =~ g:vimwiki_rxHeader
    let level = vimwiki#base#count_first_sym(line)
    if level < 6
      if g:vimwiki_symH
        let line = substitute(line, '\('.rxHdr.'\+\).\+\1', rxHdr.'&'.rxHdr, '')
      else
        let line = substitute(line, '\('.rxHdr.'\+\).\+', rxHdr.'&', '')
      endif
      call setline(lnum, line)
    endif
  else
    let line = substitute(line, '^\s*', '&'.rxHdr.' ', '') 
    if g:vimwiki_symH
      let line = substitute(line, '\s*$', ' '.rxHdr.'&', '')
    endif
    call setline(lnum, line)
  endif
endfunction
"}}}

function! vimwiki#base#RemoveHeaderLevel() "{{{
  let lnum = line('.')
  let line = getline(lnum)
  let rxHdr = g:vimwiki_rxH
  if line =~ '^\s*$'
    return
  endif

  if line =~ g:vimwiki_rxHeader
    let level = vimwiki#base#count_first_sym(line)
    let old = repeat(rxHdr, level)
    let new = repeat(rxHdr, level - 1)

    let chomp = line =~ rxHdr.'\s'

    if g:vimwiki_symH
      let line = substitute(line, old, new, 'g')
    else
      let line = substitute(line, old, new, '')
    endif

    if level == 1 && chomp
      let line = substitute(line, '^\s', '', 'g')
      let line = substitute(line, '\s$', '', 'g')
    endif

    let line = substitute(line, '\s*$', '', '')

    call setline(lnum, line)
  endif
endfunction
" }}}


" LINK functions {{{
function! vimwiki#base#apply_template(template, rxUrl, rxDesc, rxStyle) "{{{
  let magic_chars = '.*[]\^$'
  let lnk = escape(a:template, magic_chars)
  let escape_chars = '\'
  let url = escape(a:rxUrl, escape_chars)
  let descr = escape(a:rxDesc, escape_chars)
  let style = escape(a:rxStyle, escape_chars)
  if a:rxUrl != ""
    let lnk = substitute(lnk, '__LinkUrl__', url, '') 
  endif
  if a:rxDesc != ""
    let lnk = substitute(lnk, '__LinkDescription__', descr, '')
  endif
  if a:rxStyle != ""
    let lnk = substitute(lnk, '__LinkStyle__', style, '')
  endif
  return lnk
endfunction
" }}}

function! s:clean_url(url) " {{{
  let url = split(a:url, '/\|=\|-\|&\|?\|\.')
  let url = filter(url, 'v:val != ""')
  let url = filter(url, 'v:val != "www"')
  let url = filter(url, 'v:val != "com"')
  let url = filter(url, 'v:val != "org"')
  let url = filter(url, 'v:val != "net"')
  let url = filter(url, 'v:val != "edu"')
  let url = filter(url, 'v:val != "http\:"')
  let url = filter(url, 'v:val != "https\:"')
  let url = filter(url, 'v:val != "file\:"')
  let url = filter(url, 'v:val != "xml\:"')
  return join(url, " ")
endfunction " }}}

function! s:normalize_link(str, rxUrl, rxDesc, template) " {{{
  let str = a:str
  let url = matchstr(str, a:rxUrl)
  let descr = matchstr(str, a:rxDesc)
  let template = a:template
  if descr == ""
    let descr = s:clean_url(url)
  endif
  let lnk = substitute(template, '__LinkDescription__', '\="'.descr.'"', '')
  let lnk = substitute(lnk, '__LinkUrl__', '\="'.url.'"', '')
  return lnk
endfunction " }}}

function! s:normalize_imagelink(str, rxUrl, rxDesc, rxStyle, template) "{{{
  let lnk = s:normalize_link(a:str, a:rxUrl, a:rxDesc, a:template)
  let style = matchstr(str, a:rxStyle)
  let lnk = substitute(lnk, '__LinkStyle__', '\="'.style.'"', '')
  return lnk
endfunction " }}}

function! s:normalize_link_syntax_n() " {{{
  let lnum = line('.')

  " try WikiLink
  let lnk = s:matchstr_at_cursor(g:vimwiki_rxWikiLink)
  if !empty(lnk)
    let sub = s:normalize_link(lnk,
          \ g:vimwiki_rxWikiLinkMatchUrl, g:vimwiki_rxWikiLinkMatchDescr,
          \ g:vimwiki_WikiLinkTemplate2)
    call s:replacestr_at_cursor(g:vimwiki_rxWikiLink, sub)
    if g:vimwiki_debug > 1
      echomsg "WikiLink: ".lnk." Sub: ".sub
    endif
    return
  endif
  
  " try WikiIncl
  let lnk = s:matchstr_at_cursor(g:vimwiki_rxWikiIncl)
  if !empty(lnk)
    " NO-OP !!
    if g:vimwiki_debug > 1
      echomsg "WikiIncl: ".lnk." Sub: ".lnk
    endif
    return
  endif

  " try Image link
  let lnk = s:matchstr_at_cursor(g:vimwiki_rxImagelink)
  if !empty(lnk)
    let sub = s:normalize_imagelink(lnk,
          \ g:vimwiki_rxImagelinkMatchUrl, g:vimwiki_rxImagelinkMatchDescr,
          \ g:vimwiki_rxImagelinkMatchStyle, g:vimwiki_image_template)
    call s:replacestr_at_cursor(g:vimwiki_rxImagelink, sub)
    if g:vimwiki_debug > 1
      echomsg "ImageLink: ".lnk." Sub: ".sub
    endif
    return
  endif
  
  " try Word (any characters except separators)
  " rxWord is less permissive than rxWikiLinkUrl which is used in
  " normalize_link_syntax_v
  let lnk = s:matchstr_at_cursor(g:vimwiki_rxWord)
  if !empty(lnk)
    let sub = s:normalize_link(lnk,
          \ g:vimwiki_rxWord, '',
          \ g:vimwiki_WikiLinkTemplate1)
    call s:replacestr_at_cursor(lnk, sub)
    if g:vimwiki_debug > 1
      echomsg "Word: ".lnk." Sub: ".sub
    endif
    return
  endif

endfunction " }}}

function! s:normalize_link_syntax_v() " {{{
  let lnum = line('.')
  let sel_save = &selection
  let &selection = "old"
  let rv = @"
  let rt = getregtype('"')
  let done = 0

  let wiki_link_at_cursor = s:matchstr_at_cursor(g:vimwiki_rxWikiLink)
  let wiki_incl_at_cursor = s:matchstr_at_cursor(g:vimwiki_rxWikiIncl)
  let image_link_at_cursor = s:matchstr_at_cursor(g:vimwiki_rxImagelink)
  let word_at_cursor = s:matchstr_at_cursor(g:vimwiki_rxWikiLinkUrl)

  try
    norm! gvy
    let visual_selection = @"
    let v_prefix = matchstr(visual_selection, '^\s*')
    let v_suffix = matchstr(visual_selection, '.*\S\zs\s*$')
    let visual_selection = substitute(visual_selection, '^\s*\(\S\(.*\S\)*\)\s*$', '\1', '')

    " try WikiLink - substituting link_at_cursor, not buffer @"
    if !done && visual_selection =~ g:vimwiki_rxWikiLink
      call setreg('"', v_prefix. s:normalize_link(wiki_link_at_cursor,
            \ g:vimwiki_rxWikiLinkMatchUrl, g:vimwiki_rxWikiLinkMatchDescr,
            \ g:vimwiki_WikiLinkTemplate2). v_suffix, 'v')
      if g:vimwiki_debug > 1
        echomsg 'WikiLink: '.visual_selection.' Sub: '.@"
      endif
    endif
    let done = empty(wiki_link_at_cursor) ? done : 1

    " try WikiIncl - substituting link_at_cursor, not buffer @"
    if !done && visual_selection =~ g:vimwiki_rxWikiLink
      " call setreg('"', v_prefix. s:normalize_link(wiki_link_at_cursor,
      "       \ g:vimwiki_rxWikiLinkMatchUrl, g:vimwiki_rxWikiLinkMatchDescr,
      "       \ g:vimwiki_WikiLinkTemplate2). v_suffix, 'v')
      if g:vimwiki_debug > 1
        echomsg 'WikiIncl: '.visual_selection.' Sub: '.visual_selection
      endif
    endif
    let done = empty(wiki_incl_at_cursor) ? done : 1

    " try Imagelink - substituting link_at_cursor, not buffer @"
    if !done && visual_selection =~ g:vimwiki_rxImagelink
      call setreg('"', v_prefix. s:normalize_imagelink(image_link_at_cursor,
            \ g:vimwiki_rxImagelinkMatchUrl, g:vimwiki_rxImagelinkMatchDescr, 
            \ g:vimwiki_rxImagelinkMatchStyle, g:vimwiki_image_template). v_suffix, 'v')
      if g:vimwiki_debug > 1
        echomsg 'Image: '.visual_selection.' Sub: '.@"
      endif
    endif
    let done = empty(image_link_at_cursor) ? done : 1

    " try WikiLinkUrl (any characters except separators)
    if !done && visual_selection =~ g:vimwiki_rxWikiLinkUrl
      call setreg('"', v_prefix. s:normalize_link(@", 
            \ g:vimwiki_rxWikiLinkUrl, '', 
            \ g:vimwiki_WikiLinkTemplate1). v_suffix, 'v')
      if g:vimwiki_debug > 1
        echomsg 'WikiLinkUrl: '.visual_selection.' Sub: '.@"
      endif
    endif
    let done = empty(word_at_cursor) ? done : 1

    " paste result
    norm! `>pgvd

  finally
    call setreg('"', rv, rt)
    let &selection = sel_save
  endtry

endfunction " }}}

function! vimwiki#base#normalize_link(is_visual_mode) "{{{
  if !a:is_visual_mode
    call s:normalize_link_syntax_n()
  elseif visualmode() ==# 'v' && line("'<") == line("'>")
    " action undefined for 'line-wise' or 'multi-line' visual mode selections
    call s:normalize_link_syntax_v()
  endif
endfunction "}}}

" }}}
