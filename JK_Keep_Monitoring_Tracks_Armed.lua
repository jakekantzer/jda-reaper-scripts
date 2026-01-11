--[[
  @author Jake d'Arc
  @license MIT
  @version 1.0.0
  @about When on, keeps tracks ending with " [A]" armed 
  @changelog
    - init
  @provides
    [main] JK_Keep_Monitoring_Tracks_Armed.lua
]]

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

function main()
  local track_count = reaper.CountTracks(0)
  local tracks_to_arm = {}

  -- Check for " [A]" at the end of the track name
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local retval, track_name = reaper.GetTrackName(track)
    if string.sub(track_name, -4) == " [A]" then
      local arm_status = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
      local rec_mode = reaper.GetMediaTrackInfo_Value(track, "I_RECMODE")
      if rec_mode == 2 and arm_status == 0 then
        tracks_to_arm[#tracks_to_arm + 1] = track
      end
    end
  end

  -- Arm everything at once so it looks nicer
  if #tracks_to_arm > 0 then
    reaper.PreventUIRefresh(1)
    for _, track in ipairs(tracks_to_arm) do
      reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
    end
    reaper.PreventUIRefresh(-1)
  end
  
  reaper.defer(main)
end

SetButtonState(1)
main()
reaper.atexit(SetButtonState)