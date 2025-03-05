--[[
  @author Jake d'Arc
  @license MIT
  @version 1.0.0
  @about When on, keeps mute and solo states of pairs of tracks ending in " [M]" and " [A]" synced to the [M] track
  @changelog
    - init
  @provides
    [main] JDA_Sync_Track_Pair_Mute_And_Solo.lua
]]

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

function main()
  local track_count = reaper.CountTracks(0)
  local track_pairs_by_name = {}

  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local retval, track_name = reaper.GetTrackName(track)

    local is_audio_track = false
    local is_midi_track = false

    local suffix = string.sub(track_name, -4)
    if suffix == " [A]" then 
      is_audio_track = true
    elseif suffix == " [M]" then
       is_midi_track = true 
    end

    if is_audio_track or is_midi_track then
      local base_name = string.sub(track_name, 1, -5)

      if not track_pairs_by_name[base_name] then
        track_pairs_by_name[base_name] = {["A"] = nil, ["M"] = nil}
      end

      if is_audio_track then
        track_pairs_by_name[base_name]["A"] = track
      else
        track_pairs_by_name[base_name]["M"] = track
      end
    end
  end

  reaper.PreventUIRefresh(1)
  for base_name, pair in pairs(track_pairs_by_name) do
    local audio_track = pair["A"]
    local midi_track = pair["M"]

    -- Checking if they're different because always setting it can make for UI weirdness
    if audio_track ~= nil and midi_track ~= nil then
      local midi_track_mute = reaper.GetMediaTrackInfo_Value(midi_track, 'B_MUTE')
      local audio_track_mute = reaper.GetMediaTrackInfo_Value(audio_track, 'B_MUTE')

      if midi_track_mute ~= audio_track_mute then
        reaper.SetMediaTrackInfo_Value(audio_track, 'B_MUTE', midi_track_mute)
      end

      local midi_track_solo = reaper.GetMediaTrackInfo_Value(midi_track, 'I_SOLO')
      local audio_track_solo = reaper.GetMediaTrackInfo_Value(audio_track, 'I_SOLO')

      if midi_track_solo ~= audio_track_solo then
        reaper.SetMediaTrackInfo_Value(audio_track, 'I_SOLO', midi_track_solo)
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  
  reaper.defer(main)
end

SetButtonState(1)
main()
reaper.atexit(SetButtonState)