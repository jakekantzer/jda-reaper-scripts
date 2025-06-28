-- Deselect all but first track when multiple tracks are added
-- Only acts if one of the tracks is record armed upon being added
-- Runs continuously with defer to monitor track changes
-- Save as .lua file and load into REAPER Actions

local last_track_count = 0
local script_title = "Monitor and deselect all but first track (record armed only)"

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

function main()
    local current_track_count = reaper.CountTracks(0)
   
    -- Check if tracks were added (count increased)
    if current_track_count > last_track_count then
        -- Check if any of the selected tracks are record armed
        local selected_count = 0
        local selected_tracks = {}
        local has_record_armed = false
       
        for i = 0, current_track_count - 1 do
            local track = reaper.GetTrack(0, i)
            if reaper.IsTrackSelected(track) then
                selected_count = selected_count + 1
                table.insert(selected_tracks, track)
                
                -- Check if this track is record armed
                local rec_arm = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
                if rec_arm > 0 then
                    has_record_armed = true
                end
            end
        end
       
        -- Only act if multiple tracks are selected AND at least one is record armed
        if selected_count > 1 and has_record_armed then
            reaper.Undo_BeginBlock()
           
            -- Deselect all tracks
            for i = 0, current_track_count - 1 do
                local track = reaper.GetTrack(0, i)
                reaper.SetTrackSelected(track, false)
            end
           
            -- Select only the first selected track
            if selected_tracks[1] then
                reaper.SetTrackSelected(selected_tracks[1], true)
            end
           
            reaper.TrackList_AdjustWindows(false)
            reaper.UpdateArrange()
            reaper.Undo_EndBlock("Auto-deselect all but first track (record armed)", -1)
        end
    end
   
    -- Update the track count for next iteration
    last_track_count = current_track_count
   
    -- Defer the script to run again
    reaper.defer(main)
end

-- Initialize
last_track_count = reaper.CountTracks(0)

-- Start the monitoring loop
-- Set toggle state and start the script
SetButtonState(1)
main()
reaper.atexit(SetButtonState)