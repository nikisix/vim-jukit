fun! s:SelectSection()
    " Selects the text between 2 cell markers
    
    set nowrapscan

    let line_before_search = line(".")
    silent! exec '/|%%--%%|'
    " check if line has changed, otherwise no section AFTER the current one
    " was found
    if line(".")!=line_before_search
        normal! k$v
    else
        normal! G$v
    endif
    let line_before_search = line(".")
    silent! exec '?|%%--%%|'
    " check if line has changed, otherwise not section BEFORE the current one
    " was found
    if line(".")!=line_before_search
        normal! j0
    else
        normal! gg0
    endif

    let &wrapscan = s:wrapscan
endfun


function! s:GetVisualSelection()
    " Credit for this function: 
    " https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript/6271254#6271254
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction


fun! s:ParseRegister()
    " Gets content of register and send to kitty window
    
python3 << EOF
import vim 
import json

reg = vim.eval('s:jukit_register')
reg_conent = vim.eval(f'@{reg}')
if reg_conent[-1]!="\n":
    reg_conent += "\n"
escaped = reg_conent.translate(str.maketrans({
    "\n": "\\\n",
    "\\": "\\\\",
    '"': '\\"',
    "'": "\\'",
    "#": "\\#",
    "!": "\!",
    "%": "\%",
    }))
 
vim.command("let escaped_text = shellescape({})".format(json.dumps(escaped)))
EOF
    let command = '!kitty @ send-text --match title:' . b:jukit_output_title . ' ' . escaped_text
    return command
endfun


fun! jukit#PythonSplit(...)
    " Opens new kitty window split and opens python

    " check if ipython is used
    let b:jukit_ipython = (stridx(split(s:jukit_python_cmd, '/')[-1], 'ipython') >= 0)
    " define title of new kitty window by which we match when sending
    let b:jukit_output_title=strftime("%Y%m%d%H%M%S")
    " save these buffer-variables also in global variables according to which 
    " these variables will be set for new buffers
    let g:jukit_last_output_title = b:jukit_output_title
    let g:jukit_last_ipython = b:jukit_ipython
    " create new window
    silent exec "!kitty @ launch --keep-focus --title " . b:jukit_output_title
        \ . " --cwd=current"

    " if an argument was given, execute it in new kitty terminal window before
    " starting python shell
    if a:0 > 0
        silent exec '!kitty @ send-text --match title:' . b:jukit_output_title
            \ . " " . a:1 . "\r"
    endif

    if b:jukit_inline_plotting == 1
        " open python, add path to backend  and import matplotlib with the required
        " backend first
        silent exec '!kitty @ send-text --match title:' . b:jukit_output_title
            \ . " " . s:jukit_python_cmd . " -i -c \"\\\"import sys;
            \ sys.path.append('" . s:plugin_path . "/helpers'); import matplotlib;
            \ matplotlib.use('module://matplotlib-backend-kitty')\\\"\"\r"
    else
        " if no inline plotting is desired, simply open python
        silent exec '!kitty @ send-text --match title:' . b:jukit_output_title
            \ . " " . s:jukit_python_cmd . "\r"
    endif
endfun


fun! jukit#WindowSplit()
    " Opens a new kitty terminal window

    let b:jukit_ipython = 0
    let b:jukit_output_title=strftime("%Y%m%d%H%M%S")
    let g:jukit_last_output_title = b:jukit_output_title
    let g:jukit_last_ipython = b:jukit_ipython
    silent exec "!kitty @ launch  --title " . b:jukit_output_title . " --cwd=current"
endfun


fun! jukit#SendLine()
    " Sends a single line to the other kitty terminal window

    if !exists('b:jukit_output_title')
        echo "No split window found (buffer variable 'b:jukit_output_title' not set)"
        return
    endif

    if b:jukit_ipython==1
        " if ipython is used, copy code to system clipboard and '%paste'
        " to register
        normal! 0v$"+y
        silent exe '!kitty @ send-text --match title:' . b:jukit_output_title . ' "\%paste\r"'
    else
        " otherwise yank line to register
        exec 'normal! 0v$"' . s:jukit_register . 'y'
        silent exec s:ParseRegister()
    endif
    " send register content to window
    normal! j
    redraw!
endfun


fun! jukit#SendSelection()
    " Sends visually selected text to the other kitty terminal window
    
    if !exists('b:jukit_output_title')
        echo "No split window found (buffer variable 'b:jukit_output_title' not set)"
        return
    endif

    if b:jukit_ipython==1
        " if ipython is used, copy visual selection to system clipboard and 
        " '%paste' to register
        let @+ = s:GetVisualSelection() 
        silent exe '!kitty @ send-text --match title:' . b:jukit_output_title . ' "\%paste\r"'
    else
        " otherwise yank content of visual selection to register
        exec 'let @' . s:jukit_register . ' = s:GetVisualSelection()'
        silent exec s:ParseRegister()
    endif
    " send register content to window
    redraw!
endfun


fun! jukit#SendSection()
    " Sends the section of current cursor position to window

    " first select the whole current section
    call s:SelectSection()
    if b:jukit_ipython==1
        " if ipython is used, copy whole section to system clipboard and 
        " '%paste' to register
        normal! "+y
        silent exe '!kitty @ send-text --match title:' . b:jukit_output_title . ' "\%paste\r"'
    else
        " otherwise yank content of section to register
        exec 'normal! "' . s:jukit_register . 'y'
        silent exec s:ParseRegister()
    endif
    " send register content to window
    redraw!

    set nowrapscan
    " move to next section
    silent! exec '/|%%--%%|'
    let &wrapscan = s:wrapscan
    nohl
    normal! j
endfun


fun! jukit#SendUntilCurrentSection()
    " Sends all code until (and including) the current section to window

    " save current window view to restore after jumping to file beginning
    let save_view = winsaveview()
    " go to end of current section
    silent! exec '/|%%--%%|'
    if b:jukit_ipython==1
        " if ipython is used, copy from end of current section until 
        " file beginning to system clipboard and yank '%paste' to register
        normal! k$vgg0"+y
        silent exe '!kitty @ send-text --match title:' . b:jukit_output_title . ' "\%paste\r"'
    else
        " otherwise simply yank everything from beginning to current
        " section to register
        exec 'normal! k$vgg0"' . s:jukit_register . 'y'
        silent exec s:ParseRegister()
    endif
    " restore previous window view
    call winrestview(save_view)
    nohl
    redraw!
endfun


fun! jukit#SendAll()
    " Sends all code in file to window
    
    let save_view = winsaveview()
    if b:jukit_ipython==1
        " if ipython is used, copy all code in file  to system clipboard 
        " and yank '%paste' to register
        normal! gg0vG$"+y
        silent exe '!kitty @ send-text --match title:' . b:jukit_output_title . ' "\%paste\r"'
    else
        " otherwise copy yank whole file content to register
        exec 'normal! gg0vG$"' . s:jukit_register . 'y'
        silent exec s:ParseRegister()
    endif
    " send register content to window
    call winrestview(save_view)
    redraw!
endfun


fun! jukit#NewMarker()
    " Creates a new cell marker below

    if s:jukit_use_tcomment == 1
        " use tcomment plugin to automaticall detect comment mark of 
        " current filetype and comment line if specified
        exec "normal! o0\<c-d>\|%%--%%\|"
        call tcomment#operator#Line('g@$')
    else
        " otherwise simply prepend line with user b:jukit_comment_mark variable
        exec "normal! o0\<c-d>" . b:jukit_comment_mark . " \|%%--%%\|"
    endif
    normal! j
endfun


fun! jukit#NotebookConvert()
    " Converts from .ipynb to .py and vice versa

    if (expand("%:e")=="ipynb")
        if !empty(glob(expand("%:r") . '.py'))
            let answer = confirm(expand("%:r")
                \ . '.py already exists. Do you want to replace it?', "&Yes\n&No", 1)
            if answer == 0 || answer == 2
                return
            endif
        endif
        silent exec "!" . s:python_path . " " . s:plugin_path . "/helpers/ipynb_py_convert " 
            \ . expand("%") . " " . expand("%:r") . '.py'
        exec 'e ' . expand("%:r") . '.py'
    elseif (expand("%:e")=="py")
        if !empty(glob(expand("%:r") . '.ipynb'))
            let answer = confirm(expand("%:r")
                \ . '.ipynb already exists. Do you want to replace it?', "&Yes\n&No", 1)
            if answer == 0 || answer == 2
                return
            endif
        endif
        silent exec "!" . s:python_path . " " . s:plugin_path . "/helpers/ipynb_py_convert "
            \ . expand("%") . " " . expand("%:r") . '.ipynb'
        exec 'e ' . expand("%:r") . '.ipynb'
    else
        throw "File must be .py or .ipynb!"
    endif
    redraw!
endfun


fun! jukit#SaveNBToFile(run, open, to)
    " Converts the existing .ipynb to the given filetype (a:to) - e.g. html or
    " pdf - and open with specified file viewer

    silent exec "!" . s:python_path . " " . s:plugin_path . "/helpers/ipynb_py_convert "
        \ . expand("%") . " " . expand("%:r") . '.ipynb'
    if a:run == 1
        let command = "!jupyter nbconvert --to " . a:to
            \ . " --allow-errors --execute --log-level='ERROR' "
            \ . "--HTMLExporter.theme=dark " . expand("%:r") . '.ipynb '
    else
        let command = "!jupyter nbconvert --to " . a:to . " --log-level='ERROR' "
            \ . "--HTMLExporter.theme=dark " . expand("%:r") . '.ipynb '
    endif
    if a:open == 1
        exec 'let command = command . "&& " . s:jukit_' . a:to . '_viewer . " '
            \ . expand("%:r") . '.' . a:to . ' &"'
    else
        let command = command . "&"
    endif
    silent! exec command
    redraw!
endfun


fun! jukit#PythonHelp()
    " send to terminal
    if b:jukit_ipython==1
        " if ipython is used, copy all code in file  to system clipboard 
        " and yank '%paste' to register
        let @+ = 'help(' . s:GetVisualSelection() . ')'
        silent exe '!kitty @ send-text --match title:' . b:jukit_output_title . ' "\%paste\r"'
    else
        " otherwise yank line to register
        exec 'let @' . s:jukit_register . ' = "help(' . s:GetVisualSelection() . ')"'
        silent exec s:ParseRegister()
    endif
    " send register content to window
    silent exec "!kitty @ focus-window --match title:" . b:jukit_output_title
    redraw!
    nohl
endfun


fun! s:GetPluginPath(plugin_script_path)
    " Gets the absolute path to the plugin (i.e. to the folder vim-jukit/) 
    
    let plugin_path = a:plugin_script_path
    let plugin_path = split(plugin_path, "/")[:-3]
    return "/" . join(plugin_path, "/")
endfun


fun! s:InitBufVar()
    " Initialize buffer variables

    if !exists('b:jukit_buffer_vars_set') && exists("g:jukit_last_output_title") && exists("g:jukit_last_ipython")
        let b:jukit_buffer_vars_set = 1
        let b:jukit_output_title = g:jukit_last_output_title
        let b:jukit_ipython = g:jukit_last_ipython
    endif

    let b:jukit_inline_plotting = s:jukit_inline_plotting_default
    if s:jukit_use_tcomment != 1
        let b:jukit_comment_mark = s:jukit_comment_mark_default
    endif
endfun


""""""""""""""""""
" helper variables
let s:wrapscan = &wrapscan 
let s:plugin_path = s:GetPluginPath(expand("<sfile>"))

" get path of python executable that vim is using
python3 << EOF
import vim
import sys
vim.command("let s:python_path = '{}'".format(sys.executable))
EOF


"""""""""""""""""""""""""
" User defined variables:
let s:jukit_use_tcomment = get(g:, 'jukit_use_tcomment', 0)
let s:jukit_inline_plotting_default = get(g:, 'jukit_inline_plotting_default', 1)
let s:jukit_comment_mark_default = get(g:, 'jukit_comment_mark_default', '#')
let s:jukit_python_cmd = get(g:, 'jukit_python_cmd', 'ipython3')
let s:jukit_register = get(g:, 'jukit_register', 'x')
let s:jukit_html_viewer = get(g:, 'jukit_html_viewer', 'firefox')
let s:jukit_pdf_viewer = get(g:, 'jukit_pdf_viewer', 'zathura')


"""""""""""""""""""""""""""""
" initialize buffer variables
call s:InitBufVar()
autocmd BufEnter * call s:InitBufVar()
