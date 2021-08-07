##
## File exploration
##

declare-option -docstring 'Whether to show hidden files' bool explore_files_show_hidden no

declare-option -hidden str explore_files
declare-option -hidden int explore_files_count

set-face global ExploreFiles 'magenta,default'
set-face global ExploreDirectories 'cyan,default'

add-highlighter shared/directory regions
add-highlighter shared/directory/content default-region group
add-highlighter shared/directory/content/files regex '^.+$' 0:ExploreFiles
add-highlighter shared/directory/content/directories regex '^.+/$' 0:ExploreDirectories

define-command -hidden explore-files-display -params 1..2 %{ evaluate-commands %sh{
  command=$1
  path=$(realpath "${2:-.}")
  name=$(basename "$path")
  out=$(mktemp -d)
  fifo=$out/fifo
  last_buffer_name=$(basename "$kak_bufname")
  mkfifo $fifo
  cd "$path"
  (eval "$command" > $fifo) < /dev/null > /dev/null 2>&1 &
  echo "
    edit -fifo %($fifo) %($path)
    set-option buffer filetype directory
    hook -once window NormalIdle '' %{
      evaluate-commands -save-regs / %{
        set-register / %(\b\Q$last_buffer_name\E\b)
        try %(execute-keys n)
      }
      # Information
      echo -markup {Information} %(Showing $name/ entries)
    }
    hook -always -once buffer BufCloseFifo '' %(nop %sh(rm -Rf $out))
    # Information
    echo -markup {Information} %(Showing $name/ entries)
  "
}}

define-command -hidden explore-files-smart -params 0..1 %{ evaluate-commands %sh{
  file=${1:-.}
  edit=$(test -d "$file" && echo explore-files || echo edit)
  echo "$edit %($file)"
}}

define-command -hidden explore-files -params 0..1 -docstring 'Explore directory entries' %{
  explore-files-display "ls -L --group-directories-first --indicator-style=slash %sh(test $kak_opt_explore_files_show_hidden = true && echo --almost-all)" %arg(1)
}

define-command -hidden explore-files-recursive -params 0..1 -docstring 'Explore directory entries recursively' %{
  explore-files-display "find %sh(test $kak_opt_explore_files_show_hidden = false && echo -not -path ""'*/.*'"")" %arg(1)
}

define-command -hidden explore-files-forward -docstring 'Edit selected files' %{
  set-option current explore_files %val(bufname)
  execute-keys '<a-s>;<a-x>_'
  set-option current explore_files_count %sh(count() { echo $#; }; count $kak_selections_desc)
  evaluate-commands -draft -itersel -save-regs 'F' %{
    set-register F "%val(bufname)/%reg(.)"
    evaluate-commands -client %val(client) %(explore-files-smart %reg(F))
  }
  delete-buffer %opt(explore_files)
  evaluate-commands %sh{
    count=$kak_opt_explore_files_count
    test $count -gt 1 &&
      echo "echo -markup {Information} %[$count files opened]"
  }
}

define-command -hidden explore-files-back -docstring 'Explore parent directory' %{
  set-option current explore_files %val(bufname)
  explore-files "%opt(explore_files)/.."
  delete-buffer %opt(explore_files)
  echo -markup {Information} "Showing %sh(basename ""$kak_bufname"")/ entries"
}

define-command -hidden explore-files-change-directory -docstring 'Change directory and quit' %{
  change-directory %val(bufname)
  delete-buffer
}

define-command -hidden explore-files-toggle-hidden -docstring 'Toggle hidden files' %{
  set-option current explore_files_show_hidden %sh{
    if test $kak_opt_explore_files_show_hidden = true; then
      echo no
    else
      echo yes
    fi
  }
  explore-files %val(bufname)
}

hook global WinSetOption filetype=directory %{
  add-highlighter window/ ref directory
  map window normal <ret> ': explore-files-forward<ret>'
  map window normal <backspace> ': explore-files-back<ret>'
  map window normal . ': explore-files-toggle-hidden<ret>'
  map window normal R ': explore-files-recursive %val(bufname)<ret>'
  map window normal q ': explore-files-change-directory<ret>'
  map window normal <esc> ': delete-buffer<ret>'
  hook -always -once window WinSetOption filetype=.* %{
    remove-highlighter window/directory
  }
}

define-command -hidden explore-files-enable %{
  hook window -group explore-files RuntimeError '\d+:\d+: ''(?:edit|e)'': wrong argument count' %{
    explore-files %sh(dirname "$kak_buffile")
  }
  hook window -group explore-files RuntimeError '\d+:\d+: ''(?:edit|e)'' (.+): is a directory' %{
    # Hide error message
    echo
    explore-files %val(hook_param_capture_1)
  }
  hook window -group explore-files RuntimeError 'unable to find file ''(.+)''' %{
    # Hide error message
    echo
    explore-files-smart %val(hook_param_capture_1)
  }
}

hook -group explore-files global WinCreate .* %{
  explore-files-enable
}

hook -group explore-files global KakBegin .* %{ hook -once global WinCreate .* %{ hook -once global NormalIdle '' %{
  try %{ evaluate-commands -draft -save-regs '/' %{
    buffer *debug*
    set-register / 'error while opening file ''(.+?)'':\n\h+(.+?): is a directory'
    execute-keys '%1s<ret>'
    evaluate-commands -draft -itersel %{
      evaluate-commands -client %val(client) explore-files %reg(.)
    }
  }}
}}}


##
## Buffer exploration
##

declare-option -hidden str explore_buffers_current

set-face global ExploreBuffers 'yellow,default'

add-highlighter shared/buffers regions
add-highlighter shared/buffers/content default-region group
add-highlighter shared/buffers/content/buffers regex '^.+$' 0:ExploreBuffers

define-command -hidden explore-buffers -docstring 'Explore buffers' %{ evaluate-commands -save-regs '"/' %{
  set-option current explore_buffers_current %val(bufname)
  edit! -scratch *buffers*
  set-option buffer filetype buffers
  evaluate-commands set-register dquote %val(buflist)
  execute-keys '<a-R>)<a-space>i<ret><esc><space>'
  set-register / "\Q%opt(explore_buffers_current)\E"
  execute-keys n
}}

define-command -hidden explore-buffers-parent -docstring 'Explore the parent directory of the selected buffer' %{
  explore-buffers-validate
  explore-files %sh(dirname "$kak_buffile")
}

define-command -hidden explore-buffers-validate -docstring 'Edit selected buffer' %{
  execute-keys '<space><a-x>_'
  buffer %reg(.)
  delete-buffer *buffers*
}

define-command -hidden explore-buffers-delete -docstring 'Delete selected buffer' %{
  execute-keys '<space><a-x>_'
  delete-buffer %reg(.)
  explore-buffers
}

hook global WinSetOption filetype=buffers %{
  add-highlighter window/ ref buffers
  map window normal <ret> ': explore-buffers-validate<ret>'
  map window normal <backspace> ': explore-buffers-parent<ret>'
  map window normal q ': delete-buffer<ret>'
  map window normal <esc> ': delete-buffer<ret>'
  map window normal d ': explore-buffers-delete<ret>'
  hook -always -once window WinSetOption filetype=.* %{
    remove-highlighter window/buffers
  }
}

define-command -hidden explore-buffers-enable %{
  hook window -group explore-buffers RuntimeError '\d+:\d+: ''(buffer|b)'': wrong argument count' %{
    # Hide error message
    echo
    explore-buffers
  }
}

hook -group explore-buffers global WinCreate .* %{
  explore-buffers-enable
}
