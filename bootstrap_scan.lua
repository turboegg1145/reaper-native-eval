-- Build-time cache warm-up only.
-- REAPER performs its plugin scan before running command-line scripts. Quitting
-- immediately persists reaper-vstplugins64.ini / reaper-clap-linux-x86_64.ini
-- into the Docker image layer.
reaper.Main_OnCommand(40004, 0) -- File: Quit REAPER
