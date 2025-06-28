-- Auto-disarm all other tracks when one is armed
-- Only runs if there is no redo action available
-- Run this script as a background script with defer
-- Holds shift to allow multi-arm

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

local last_armed_tracks = {}
local last_track_count = 0

function main()
    local track_count = reaper.CountTracks(0)
    local current_armed_tracks = {}
    local newly_armed_tracks = {}
   
    -- Check if there's a redo action available - if so, skip auto-disarm logic
    local can_redo = reaper.Undo_CanRedo2(0)
    if can_redo and can_redo ~= "" then
        -- Store current state and defer without doing anything
        for i = 0, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            if track then
                local rec_mode = reaper.GetMediaTrackInfo_Value(track, "I_RECMODE")
                
                -- Only track non-input-monitoring tracks
                if rec_mode ~= 2 then
                    local is_armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
                   
                    if is_armed == 1 then
                        current_armed_tracks[i] = true
                    end
                end
            end
        end
        last_armed_tracks = current_armed_tracks
        last_track_count = track_count
        reaper.defer(main)
        return
    end
   
    -- Check if shift is held down
    local shift_held = reaper.JS_Mouse_GetState(8) & 8 ~= 0 -- Check shift key
   
    -- Check current armed state of all tracks (ignore I_RECMODE 2 tracks completely)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local rec_mode = reaper.GetMediaTrackInfo_Value(track, "I_RECMODE")
            
            -- Completely ignore tracks with record mode 2 (input monitoring)
            if rec_mode ~= 2 then
                local is_armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
               
                if is_armed == 1 then
                    current_armed_tracks[i] = true
                    -- Check if this track was just armed (wasn't armed before)
                    if not last_armed_tracks[i] then
                        table.insert(newly_armed_tracks, i)
                    end
                end
            end
        end
    end
   
    -- Only disarm other tracks if exactly ONE track was newly armed and shift is NOT held
    if #newly_armed_tracks == 1 and not shift_held then
        local newly_armed_track = newly_armed_tracks[1]
        
        -- Verify the track index is still valid after potential track count changes
        local current_track_count = reaper.CountTracks(0)
        if newly_armed_track >= current_track_count then
            -- Track index is out of bounds, skip processing
            last_armed_tracks = current_armed_tracks
            reaper.defer(main)
            return
        end
        
        -- Check if there were any other tracks armed in the PREVIOUS state (last_armed_tracks)
        -- Only count non-input-monitoring tracks
        local previously_armed_count = 0
        for track_index, _ in pairs(last_armed_tracks) do
            if track_index ~= newly_armed_track then
                -- Double-check this track still exists and isn't input monitoring
                local check_track = reaper.GetTrack(0, track_index)
                if check_track then
                    local check_rec_mode = reaper.GetMediaTrackInfo_Value(check_track, "I_RECMODE")
                    if check_rec_mode ~= 2 then
                        previously_armed_count = previously_armed_count + 1
                    end
                end
            end
        end
        
        -- Only proceed if there were actually other tracks armed before
        if previously_armed_count > 0 then
            reaper.PreventUIRefresh(1)
            reaper.Undo_BeginBlock()
            
            -- Disarm all other tracks
            current_track_count = reaper.CountTracks(0)
            for i = 0, current_track_count - 1 do
                if i ~= newly_armed_track then
                    local other_track = reaper.GetTrack(0, i)
                    if other_track then
                        local rec_mode = reaper.GetMediaTrackInfo_Value(other_track, "I_RECMODE")
                        -- Only disarm tracks that don't have record mode 2
                        if rec_mode ~= 2 then
                            reaper.SetMediaTrackInfo_Value(other_track, "I_RECARM", 0)
                        end
                    end
                end
            end
           
            -- Update UI
            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
            reaper.TrackList_AdjustWindows(false)
            reaper.Undo_EndBlock('Auto-disarm: Disarmed other tracks', -1)
        end
    end
   
    -- Store current state for next iteration
    last_armed_tracks = current_armed_tracks
    last_track_count = track_count
   
    -- Defer the script to run continuously
    reaper.defer(main)
end

-- Set toggle state and start the script
SetButtonState(1)
main()
reaper.atexit(SetButtonState)