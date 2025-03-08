--[[
  @author Jake d'Arc
  @license MIT
  @version 1.0.0
  @about Real-time pre-FX rendering and FX chain copying for MIDI/audio track pairs, intended for hardware synths
  @changelog
    - init
  @provides
    [main] JDA_HW_Synth_Render/JDA_HW_Synth_Render_1P.lua
    [main] JDA_HW_Synth_Render/JDA_HW_Synth_Render_2P.lua
]]

function bounce(second_pass)
  -- Render to new track
  if second_pass then
    reaper.Main_OnCommand(42416, 0)
  else
    reaper.Main_OnCommand(41719, 0)
  end
end

function get_track_pair(first_track)
  local first_track = reaper.GetSelectedTrack(0, 0)

  -- If they selected the MIDI track, we need to find the corresponding audio one or vice-versa
  local retval, first_track_name = reaper.GetTrackName(first_track)

  if string.sub(first_track_name, -4) == " [M]" then
    midi_track = first_track
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
      local current_track = reaper.GetTrack(0, i)
      local retval, second_track_name = reaper.GetTrackName(current_track)

      if string.sub(second_track_name, -4) == " [A]" then
        if string.sub(second_track_name, 1, #second_track_name - 4) == string.sub(first_track_name, 1, #first_track_name - 4) then
          audio_track = current_track
          break
        end
      end
    end
  elseif string.sub(first_track_name, -4) == " [A]" then
    audio_track = first_track
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
      local current_track = reaper.GetTrack(0, i)
      local retval, second_track_name = reaper.GetTrackName(current_track)

      if string.sub(second_track_name, -4) == " [M]" then
        if string.sub(second_track_name, 1, #second_track_name - 4) == string.sub(first_track_name, 1, #first_track_name - 4) then
          midi_track = current_track
          break
        end
      end
    end
  end

  return audio_track, midi_track
end

function check_track_pair()
  local first_track = reaper.GetSelectedTrack(0, 0)
  local retval, first_track_name = reaper.GetTrackName(first_track)
  local second_track = reaper.GetSelectedTrack(0, 1)
  local retval, second_track_name = reaper.GetTrackName(second_track)

  if string.sub(first_track_name, -4) == " [M]" then
    midi_track = first_track
    if second_track_name == string.sub(first_track_name, 1, #first_track_name - 4) .. " [A]" then
      audio_track = second_track
    end
  elseif string.sub(first_track_name, -4) == " [A]" then
    audio_track = first_track
    
    if second_track_name == string.sub(first_track_name, 1, #first_track_name - 4) .. " [M]" then
      midi_track = second_track
    end
  end

  return audio_track, midi_track
end

function main(second_pass, make_new_track)
  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- Check if one or two tracks are selected
  local selected_track_count = reaper.CountSelectedTracks(0)
  if selected_track_count ~= 1 and selected_track_count ~= 2 then
    reaper.ShowMessageBox("Please select a single track ending with [M] or [A] or a matching track pair.", "Error", 0)
  return end

  -- Attempt to get the audio and MIDI track pair
  local audio_track = nil
  local midi_track = nil
  
  -- Either find the matching track or check that the tracks match based on selected track count
  if selected_track_count == 1 then
    audio_track, midi_track = get_track_pair()

    if audio_track == nil or midi_track == nil then
      reaper.ShowMessageBox("Could not find a matching track pair.", "Error", 0)
    return end
  elseif selected_track_count == 2 then
    audio_track, midi_track = check_track_pair()

    if audio_track == nil or midi_track == nil then
      reaper.ShowMessageBox("The pair of tracks that you selected do not match.", "Error", 0)
    return end
  end

  -- Select only the MIDI track so we can get its items
  reaper.SetOnlyTrackSelected(midi_track)

  -- Deselect all items first
  reaper.Main_OnCommand(40289, 0)

  -- Select all items on selected tracks in current time selection
  reaper.Main_OnCommand(40718, 0)

  -- Store the currently selected items
  local selected_items = {}
  local num_selected_items = reaper.CountSelectedMediaItems(0)
  for i = 0, num_selected_items - 1 do
      selected_items[i+1] = reaper.GetSelectedMediaItem(0, i)
  end

  -- Check that there's a loop
  local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if start_time == end_time then
    reaper.ShowMessageBox("There is no loop set, aborting.", "Error", 0)
  return end

  -- Move on to the audio track to do work there
  reaper.SetOnlyTrackSelected(audio_track)

  -- Get the automation mode, store it, and set it to trim/read so effects bypass correctly
  local orig_automation_mode = reaper.GetTrackAutomationMode(audio_track)
  reaper.SetTrackAutomationMode(audio_track, 0)

  -- Store the original render speed
  store_render_speed_id = reaper.NamedCommandLookup("_XENAKIOS_STORERENDERSPEED")
  if store_render_speed_id == nil then
    reaper.ShowMessageBox("Please install SWS!", "Error", 0) -- If SWS isn't installed, it'll blow up here
  return end
  reaper.Main_OnCommand(store_render_speed_id, 0)

  -- Set the render speed to realtime
  set_render_speed_rt_id = reaper.NamedCommandLookup("_XENAKIOS_SETRENDERSPEEDRT")
  if set_render_speed_rt_id == nil then return end
  reaper.Main_OnCommand(set_render_speed_rt_id, 0)

  -- Store the original bypass states and bypass all
  local fx_bypass_states = {}
  local num_fx = reaper.TrackFX_GetCount(audio_track)
  for i = 0, num_fx - 1 do
      fx_bypass_states[i] = reaper.TrackFX_GetEnabled(audio_track, i)
      reaper.TrackFX_SetEnabled(audio_track, i, false)
  end

  -- Render to new track
  bounce(second_pass)

  -- Restore the previous render speed
  recall_render_speed_id = reaper.NamedCommandLookup("_XENAKIOS_RECALLRENDERSPEED")
  if recall_render_speed_id == nil then return end
  reaper.Main_OnCommand(recall_render_speed_id, 0)

  -- Assign the new track to a variable for later
  local new_track = reaper.GetSelectedTrack(0, 0)

  -- Restore the original bypass states 
  for i, state in pairs(fx_bypass_states) do
    reaper.TrackFX_SetEnabled(audio_track, i, state)
  end

  if make_new_track then
    -- Get the number of FX in the source track
    local num_fx = reaper.TrackFX_GetCount(audio_track)

    -- Copy all FX
    for i = 0, num_fx - 1 do
      local fx_chunk = reaper.TrackFX_GetFXGUID(audio_track, i)
      reaper.TrackFX_CopyToTrack(audio_track, i, new_track, reaper.TrackFX_GetCount(new_track), false)
    end
  end

  -- Restore the original automation mode
  reaper.SetTrackAutomationMode(audio_track, orig_automation_mode)

  -- Mute the items from the original MIDI track
  for i = 1, #selected_items do
      reaper.SetMediaItemInfo_Value(selected_items[i], "B_MUTE", 1)
  end

  -- Unmute the original audio track because the render mutes it
  reaper.SetMediaTrackInfo_Value(audio_track, "B_MUTE", 0)

  if make_new_track then
    -- Move the audio track above the new track because the new track is made above it for some reason
    reaper.SetOnlyTrackSelected(audio_track)
    local new_track_id = math.floor(reaper.GetMediaTrackInfo_Value(new_track, "IP_TRACKNUMBER"))
    reaper.ReorderSelectedTracks(new_track_id - 1, 0)

    -- Color and name
    reaper.SetTrackColor(new_track, reaper.GetTrackColor(audio_track))
    local retval, audio_track_name = reaper.GetTrackName(audio_track)
    local new_track_name = string.sub(audio_track_name, 1, -5) .. " [S]"
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", new_track_name, true)
    reaper.SetOnlyTrackSelected(new_track)
  else
    -- Move the new item to the audio track and kill the new track
    local new_item = reaper.GetTrackMediaItem(new_track, 0)
    reaper.MoveMediaItemToTrack(new_item, audio_track)
    reaper.DeleteTrack(new_track)
  end

  -- Wrap up
  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)

  reaper.Undo_EndBlock('Hardware synth render',-1)
end

return main