# Defined in /usr/share/fish/functions/help.fish @ line 1
function help --description 'Show help for the fish shell'
    set -l options h/help
    argparse -n help $options -- $argv
    or return

    if set -q _flag_help
        __fish_print_help help
        return 0
    end

    set -l fish_help_item $argv[1]
    if test (count $argv) -gt 1
        if string match -q string $argv[1]
            set fish_help_item (string join '-' $argv[1] $argv[2])
        else
            echo "help: Expected at most 1 args, got 2"
            return 1
        end
    end

    # Find a suitable browser for viewing the help pages.
    # The first thing we try is $fish_help_browser.
    set -l fish_browser $fish_help_browser

    # A list of graphical browsers we know about.
    set -l graphical_browsers htmlview x-www-browser firefox galeon mozilla
    set -a graphical_browsers konqueror epiphany opera netscape rekonq google-chrome chromium-browser

    # On mac we may have to write a temporary file that redirects to the desired
    # help page, since `open` will drop fragments from file URIs (issue #4480).
    set -l need_trampoline

    if not set -q fish_browser[1]
        if set -q BROWSER
            # User has manually set a preferred browser, so we respect that
            echo $BROWSER | read -at fish_browser
        else
            # No browser set up, inferring.
            # We check a bunch and use the last we find.

            # Check for a text-based browser.
            for i in htmlview www-browser links elinks lynx w3m
                if type -q -f $i
                    set fish_browser $i
                    break
                end
            end

            # If we are in a graphical environment, check if there is a graphical
            # browser to use instead.
            if test -n "$DISPLAY" -a \( "$XAUTHORITY" = "$HOME/.Xauthority" -o "$XAUTHORITY" = "" \)
                for i in $graphical_browsers
                    if type -q -f $i
                        set fish_browser $i
                        break
                    end
                end
            end

            # If we have an open _command_ we use it - otherwise it's our function,
            # which might not have a backend to use.
            # Note that we prefer xdg-open, because this open might also be a symlink to "openvt"
            # like it is on Debian.
            if command -sq open
                set fish_browser open
                # The open command needs a trampoline because the macOS version can't handle #-fragments.
                set need_trampoline 1
            end

            # If the OS appears to be Windows (graphical), try to use cygstart
            if type -q cygstart
                set fish_browser cygstart
                # If xdg-open is available, just use that
            else if type -q xdg-open
                set fish_browser xdg-open
            end

            # Try to find cmd.exe via $PATH or one of the paths that it's often at.
            #
            # We use this instead of xdg-open because that's useless without a backend
            # like wsl-open which we'll check in a minute.
            if test -f /proc/version
                and string match -riq 'Microsoft|WSL|MSYS|MINGW' </proc/version
                and set -l cmd (command -s cmd.exe /mnt/c/Windows/System32/cmd.exe)
                # Use the first of these.
                set fish_browser $cmd[1]
            end

            if type -q wsl-open
                set fish_browser wsl-open
            end
        end
    end

    if not set -q fish_browser[1]
        printf (_ '%s: Could not find a web browser.\n') help
        printf (_ 'Please try `BROWSER=some_browser help`, `man fish-doc`, or `man fish-tutorial`.\n\n')
        return 1
    end

    # In Cygwin, start the user-specified browser using cygstart,
    # only if a Windows browser is to be used.
    if type -q cygstart
        if test $fish_browser != cygstart
            and not command -sq $fish_browser[1]
            # Escaped quotes are necessary to work with spaces in the path
            # when the command is finally eval'd.
            set fish_browser cygstart $fish_browser
        else
            set need_trampoline 1
        end
    end

    set -l fish_help_page
    switch "$fish_help_item"
        case "."
            set fish_help_page "cmds/source.html"
        case globbing
            set fish_help_page "index.html#expand"
        case (builtin -n) (__fish_print_commands)
            # If the docs aren't installed, __fish_print_commands won't print anything
            # Since we document all our builtins, check those at least.
            # The alternative is to create this list at build time.
            set fish_help_page "cmds/$fish_help_item.html"
        case 'completion-*'
            set fish_help_page "completions.html#$fish_help_item"
        case 'tut-*'
            set fish_help_page "tutorial.html#"(string sub -s 5 -- $fish_help_item | string replace -a -- _ -)
        case tutorial
            set fish_help_page "tutorial.html"
        case releasenotes
            set fish_help_page relnotes.html
        case completions
            set fish_help_page completions.html
        case faq
            set fish_help_page faq.html
        case fish-for-bash-users
            set fish_help_page fish_for_bash_users.html
        case ''
            set fish_help_page "index.html"
        case "*"
            set fish_help_page "index.html#$fish_help_item"
    end

    # In Crostini Chrome OS Linux, the default browser opens URLs in Chrome running outside the
    # linux VM. This browser does not have access to the Linux filesystem. This uses Garcon, see e.g.
    # https://chromium.googlesource.com/chromiumos/platform2/+/master/vm_tools/garcon/#opening-urls
    # https://source.chromium.org/search?q=garcon-url-handler
    string match -q '*garcon-url-handler*' $fish_browser[1]
    and set -l chromeos_linux_garcon

    set -l page_url
    if test -f $__fish_help_dir/index.html; and not set -lq chromeos_linux_garcon
        # Help is installed, use it
        set page_url file://$__fish_help_dir/$fish_help_page

        # For Windows (Cygwin, msys2 and WSL), we need to convert the base
        # help dir to a Windows path before converting it to a file URL
        # but only if a Windows browser is being used
        if type -q cygpath
            and string match -qr '(cygstart|\.exe)(\s+|$)' $fish_browser[1]
            set page_url file://(cygpath -m $__fish_help_dir)/$fish_help_page
        else if type -q wslpath
            and string match -qr '\.exe(\s+|$)' $fish_browser[1]
            set page_url file://(wslpath -w $__fish_help_dir)/$fish_help_page
        end
    else
        # Go to the web. Only include one dot in the version string
        set -l version_string (string split . -f 1,2 -- $version | string join .)
        set page_url https://fishshell.com/docs/$version_string/$fish_help_page
        # We don't need a trampoline for a remote URL.
        set need_trampoline
    end

    if set -q need_trampoline[1]
        # If string replace doesn't replace anything, we don't actually need a
        # trampoline (they're only needed if there's a fragment in the path)
        if set -l clean_url (string match -re '#' $page_url)
            # Write a temporary file that will redirect where we want.
            set -q TMPDIR
            or set -l TMPDIR /tmp
            set -l tmpdir (mktemp -d $TMPDIR/help.XXXXXX)
            or return 1
            set -l tmpname $tmpdir/help.html
            echo '<meta http-equiv="refresh" content="0;URL=\''$clean_url'\'" />' >$tmpname
            set page_url file://$tmpname

            # For Windows (Cygwin, msys2 and WSL), we need to convert the base help dir to a Windows path before converting it to a file URL
            # but only if a Windows browser is being used
            if type -q cygpath
                and string match -qr '(cygstart|\.exe)(\s+|$)' $fish_browser[1]
                set page_url file://(cygpath -m $tmpname)
            else if type -q wslpath
                and string match -qr '\.exe(\s+|$)' $fish_browser[1]
                set page_url file://(wslpath -w $tmpname)
            end
        end
    end

    # cmd.exe needs more coaxing.
    if string match -qr 'cmd\.exe$' -- $fish_browser[1]
        # The space before the /c is to prevent msys2 from expanding it to a path
        $fish_browser " /c" start $page_url
        # If browser is known to be graphical, put into background
    else if contains -- $fish_browser[1] $graphical_browsers
        switch $fish_browser[1]
            case htmlview x-www-browser
                printf (_ 'help: Help is being displayed in your default browser.\n')
            case '*'
                printf (_ 'help: Help is being displayed in %s.\n') $fish_browser[1]
        end
        $fish_browser $page_url &
        disown $last_pid >/dev/null 2>&1
    else
        # Work around lynx bug where <div class="contents"> always has the same formatting as links (unreadable)
        # by using a custom style sheet. See https://github.com/fish-shell/fish-shell/issues/4170
        if string match -qr '^lynx' -- $fish_browser
            set fish_browser $fish_browser -lss={$__fish_data_dir}/lynx.lss
        end
        $fish_browser $page_url
    end
end
