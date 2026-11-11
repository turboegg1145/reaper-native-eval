-- Native headless runner for the REAPER evaluation sandbox.
-- This file intentionally uses only the stock REAPER Lua API.

local WORKSPACE = "/workspace"
local AGENT_SCRIPT = WORKSPACE .. "/agent_song.lua"
local OUTPUT_RPP = WORKSPACE .. "/output.rpp"
local OUTPUT_WAV = WORKSPACE .. "/output.wav"
local ERROR_LOG = WORKSPACE .. "/error.log"
local RENDER_ACTION = 42230 -- Render project, most recent settings, auto-close dialog
local QUIT_ACTION = 40004   -- File: Quit REAPER

local function write_error(stage, message)
    local text = string.format("[%s] %s\n", stage, tostring(message))
    local f = io.open(ERROR_LOG, "w")
    if f then
        f:write(text)
        f:close()
    end
    io.stderr:write(text)
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
end

-- Quit without any chance of a "save changes?" modal. The project may be dirty
-- even on failure paths (a model can add tracks before hitting a bad API).
local function quit_cleanly()
    reaper.GetSetProjectInfo(0, "DIRTY", 0, true)
    reaper.Main_OnCommand(QUIT_ACTION, 0)
end

-- Never let a previous evaluation leak into this one.
os.remove(OUTPUT_WAV)
os.remove(OUTPUT_RPP)
os.remove(ERROR_LOG)

local agent = io.open(AGENT_SCRIPT, "rb")
if not agent then
    write_error("runner", "missing agent script: " .. AGENT_SCRIPT)
    quit_cleanly()
    return
end
agent:close()

-- The model's script must be ordinary, synchronous ReaScript. Any Lua error,
-- including a call to a nonexistent reaper.* API, is captured here.
local ok, err = pcall(dofile, AGENT_SCRIPT)
if not ok then
    write_error("agent_song.lua", err)
    quit_cleanly()
    return
end

-- Force deterministic project/render settings, overriding whatever the agent
-- left in the project.
local function set_num(key, value)
    reaper.GetSetProjectInfo(0, key, value, true)
end

local function set_str(key, value)
    reaper.GetSetProjectInfo_String(0, key, value, true)
end

set_num("PROJECT_SRATE", 48000)
set_num("PROJECT_SRATE_USE", 1)
set_num("RENDER_SETTINGS", 0)       -- master mix
set_num("RENDER_BOUNDSFLAG", 1)     -- entire project
set_num("RENDER_CHANNELS", 2)       -- stereo
set_num("RENDER_SRATE", 48000)      -- 48 kHz
set_num("RENDER_TAILFLAG", 0)       -- no extra tail beyond the project
set_num("RENDER_TAILMS", 0)
set_num("RENDER_ADDTOPROJ", 0)
set_num("RENDER_NORMALIZE", 0)
set_num("RENDER_DITHER", 0)

set_str("RENDER_FILE", WORKSPACE)
set_str("RENDER_PATTERN", "output")
set_str("RENDER_FORMAT", "evaw")    -- native WAV sink; project default depth
set_str("RENDER_FORMAT2", "")       -- no secondary render

local _, target = reaper.GetSetProjectInfo_String(0, "RENDER_TARGETS", "", false)
if target ~= OUTPUT_WAV then
    write_error("render_config", "unexpected RENDER_TARGETS: " .. tostring(target))
    quit_cleanly()
    return
end

-- Option 8 makes this the project filename. The RPP contains the render setup.
reaper.Main_SaveProjectEx(0, OUTPUT_RPP, 8)
local rpp_size = file_size(OUTPUT_RPP)
if not rpp_size or rpp_size == 0 then
    write_error("save_project", "failed to write " .. OUTPUT_RPP)
    quit_cleanly()
    return
end

-- 42230 performs the offline render and auto-closes the render dialog. It
-- returns only after the render has finished in REAPER 7.85.
reaper.Main_OnCommand(RENDER_ACTION, 0)

local wav_size = file_size(OUTPUT_WAV)
if not wav_size or wav_size <= 44 then
    write_error("render", "render did not produce a non-empty " .. OUTPUT_WAV)
    quit_cleanly()
    return
end

-- The project was saved before rendering. Clear any dirty flag left by the
-- render so 40004 cannot pop a save dialog, then terminate.
quit_cleanly()
