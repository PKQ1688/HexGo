on run argv
    if (count of argv) is 0 then error "Expected a project directory."

    set projectDir to item 1 of argv

    tell application "Ghostty"
        activate

        set baseConfig to new surface configuration
        set initial working directory of baseConfig to projectDir

        set mainWindow to new window with configuration baseConfig
        set agentPane to terminal 1 of selected tab of mainWindow

        set editorPane to split agentPane direction right with configuration baseConfig
        split editorPane direction down with configuration baseConfig
    end tell
end run
