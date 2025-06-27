-- Auto-disarm all other tracks when one is armed
-- Run this script as a background script with defer
-- Holds shift to allow multi-arm

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

local last_armed_tracks = {}

function main()
    local track_count = reaper.CountTracks(0)
    local current_armed_tracks = {}
    local newly_armed_track = nil
    
    -- Check if shift is held down
    local shift_held = reaper.JS_Mouse_GetState(8) & 8 ~= 0 -- Check shift key
    
    -- Check current armed state of all tracks
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local is_armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
        local rec_mode = reaper.GetMediaTrackInfo_Value(track, "I_RECMODE")
        
        if is_armed == 1 and rec_mode ~= 2 then
            current_armed_tracks[i] = true
            -- Check if this track was just armed (wasn't armed before)
            if not last_armed_tracks[i] then
                newly_armed_track = i
            end
        end
    end
    
    -- If a track was just armed and shift is NOT held, disarm all others
    if newly_armed_track ~= nil and not shift_held then
        for i = 0, track_count - 1 do
            if i ~= newly_armed_track then
                local track = reaper.GetTrack(0, i)
                local rec_mode = reaper.GetMediaTrackInfo_Value(track, "I_RECMODE")
                -- Only disarm tracks that don't have record mode 2
                if rec_mode ~= 2 then
                    reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
                end
            end
        end
        
        -- Update button states for track record arm buttons
        reaper.Main_OnCommand(40020, 0) -- Track: Toggle record arming for current track (updates UI)
        
        -- Force UI refresh to update button states
        reaper.UpdateArrange()
        reaper.TrackList_AdjustWindows(false)
    end
    
    -- Store current state for next iteration
    last_armed_tracks = current_armed_tracks
    
    -- Defer the script to run continuously
    reaper.defer(main)
end

-- Set toggle state and start the script
SetButtonState(1)
main()
reaper.atexit(SetButtonState)