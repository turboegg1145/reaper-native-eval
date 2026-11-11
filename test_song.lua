-- Full-chain smoke test: native ReaScript only.
-- Copy this file to /workspace/agent_song.lua and run the container.
-- runner_wrapper.lua will save output.rpp and render output.wav.

reaper.SetCurrentBPM(0, 120, false)
reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 48000, true)
reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 1, true)

if reaper.CountTracks(0) == 0 then
    reaper.InsertTrackAtIndex(0, true)
end
local track = reaper.GetTrack(0, 0)
reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Surge XT -> ReaEQ", true)
reaper.SetMediaTrackInfo_Value(track, "D_VOL", 0.35) -- about -9 dB

-- Native Linux VST3 names as exposed by REAPER's cache.
local surge = reaper.TrackFX_AddByName(track, "Surge XT", false, -1)
local eq = reaper.TrackFX_AddByName(track, "ReaEQ", false, -1)
if surge < 0 then error("Surge XT VST3 was not found") end
if eq < 0 then error("ReaEQ was not found") end

-- Eight seconds at 120 BPM: C - Am - F - G, four beats each.
local item = reaper.CreateNewMIDIItemInProj(track, 0, 8, false)
local take = reaper.GetActiveTake(item)
local chords = {
    {48, 52, 55}, -- C3  E3  G3
    {45, 48, 52}, -- A2  C3  E3
    {41, 45, 48}, -- F2  A2  C3
    {43, 47, 50}, -- G2  B2  D3
}
for i, chord in ipairs(chords) do
    -- 960 PPQ at 120 BPM: 4 beats = 3840 ticks. Leave a 0.25-beat gap.
    local startppq = (i - 1) * 4 * 960
    for _, pitch in ipairs(chord) do
        reaper.MIDI_InsertNote(take, false, false, startppq, startppq + 3600,
                               0, pitch, 100, true)
    end
end
reaper.MIDI_Sort(take)
reaper.UpdateArrange()
