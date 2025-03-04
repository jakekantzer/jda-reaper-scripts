--[[
  @author Jake d'Arc
  @license MIT
  @version 1.0.0
  @about When on, keeps tracks beginning with "A: " armed 
  @changelog
    - init
  @provides
    [main] JDA_Keep_Monitoring_Tracks_Armed.lua
]]

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

function main()
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local retval, track_name = reaper.GetTrackName(track)
    if string.sub(track_name, 0, 3) == "A: " then
      local arm_status = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
      if arm_status == 0 then
        reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
      end
    end
  end
  reaper.defer(main)
end

SetButtonState(1)
main()
reaper.atexit(SetButtonState)