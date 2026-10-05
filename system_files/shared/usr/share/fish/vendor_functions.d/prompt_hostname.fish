function prompt_hostname --description 'The host for the prompt, or the container the shell is running in'
    # fish's own prompt names the host through this function; inside a toolbox or distrobox
    # container it names the container instead
    if test -n "$CONTAINER_ID"
        echo "📦 $CONTAINER_ID"
    else
        string split -f1 -- . $hostname
    end
end
