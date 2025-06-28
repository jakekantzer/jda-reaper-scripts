--[[
  @author Jake d'Arc
  @license MIT
  @version 1.0.1
  @about When on, keeps mute and solo states of pairs of tracks ending in " [M]" and " [A]" synced
  @changelog
    - Cleaned up code structure and performance
    - Simplified change detection logic
    - Reduced redundant track scanning
  @provides
    [main] JDA_Sync_Track_Pair_Mute_And_Solo_Clean.lua
]]

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

-- Cache for track pairs and previous states
local track_pairs_by_name = {}
local previous_states_by_guid = {}
local last_track_count = 0

-- Find and pair tracks with [M] and [A] suffixes
function scan_track_pairs()
  local track_count = reaper.CountTracks(0)
  track_pairs_by_name = {}
  
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local retval, track_name = reaper.GetTrackName(track)
    
    local suffix = string.sub(track_name, -4)
    local is_audio_track = (suffix == " [A]")
    local is_midi_track = (suffix == " [M]")
    
    if is_audio_track or is_midi_track then
      local base_name = string.sub(track_name, 1, -5)
      
      if not track_pairs_by_name[base_name] then
        track_pairs_by_name[base_name] = {audio = nil, midi = nil}
      end
      
      if is_audio_track then
        track_pairs_by_name[base_name].audio = track
      else
        track_pairs_by_name[base_name].midi = track
      end
    end
  end
  
  last_track_count = track_count
end

-- Get current state for a track
function get_track_state(track)
  local retval, guid = reaper.GetSetMediaTrackInfo_String(track, 'GUID', '', false)
  local mute = reaper.GetMediaTrackInfo_Value(track, 'B_MUTE')
  local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO')
  
  return guid, {mute = mute, solo = solo}
end

-- Check if there's any redo history that could be disrupted
function has_redo_history()
  -- Check if there are any redo actions available
  local redo_string = reaper.Undo_CanRedo2(0)
  return redo_string ~= nil and redo_string ~= ""
end

-- Sync a specific property between two tracks
function sync_track_property(track1, track2, property, property_key, description)
  local track1_value = reaper.GetMediaTrackInfo_Value(track1, property_key)
  local track2_value = reaper.GetMediaTrackInfo_Value(track2, property_key)
  
  if track1_value ~= track2_value then
    -- Don't sync if there's redo history to preserve
    if has_redo_history() then
      return false
    end
    
    local guid1, current_state1 = get_track_state(track1)
    local guid2, current_state2 = get_track_state(track2)
    
    local prev_state1 = previous_states_by_guid[guid1]
    local prev_state2 = previous_states_by_guid[guid2]
    
    -- Determine which track changed by comparing with previous states
    local track1_changed = prev_state1 and (prev_state1[property] ~= current_state1[property])
    local track2_changed = prev_state2 and (prev_state2[property] ~= current_state2[property])
    
    local sync_value
    if track1_changed and not track2_changed then
      sync_value = track1_value
    elseif track2_changed and not track1_changed then
      sync_value = track2_value
    else
      -- If we can't determine which changed, default to track1 (midi track)
      sync_value = track1_value
    end
    
    reaper.Undo_BeginBlock()
    reaper.SetMediaTrackInfo_Value(track1, property_key, sync_value)
    reaper.SetMediaTrackInfo_Value(track2, property_key, sync_value)
    reaper.Undo_EndBlock('Sync ' .. description .. ' state of track pair', -1)
    
    return true
  end
  
  return false
end

-- Process all track pairs for syncing
function process_track_pairs()
  local current_states = {}
  
  reaper.PreventUIRefresh(1)
  
  for base_name, track_pair in pairs(track_pairs_by_name) do
    local audio_track = track_pair.audio
    local midi_track = track_pair.midi
    
    -- Only process complete pairs
    if audio_track and midi_track then
      -- Store current states
      local midi_guid, midi_state = get_track_state(midi_track)
      local audio_guid, audio_state = get_track_state(audio_track)
      
      current_states[midi_guid] = midi_state
      current_states[audio_guid] = audio_state
      
      -- Only sync if we have previous states to compare against
      if previous_states_by_guid[midi_guid] and previous_states_by_guid[audio_guid] then
        sync_track_property(midi_track, audio_track, 'mute', 'B_MUTE', 'mute')
        sync_track_property(midi_track, audio_track, 'solo', 'I_SOLO', 'solo')
      end
    end
  end
  
  -- Update previous states
  previous_states_by_guid = current_states
  
  reaper.PreventUIRefresh(-1)
end

function main()
  local current_track_count = reaper.CountTracks(0)
  
  -- Rescan tracks only if count changed
  if current_track_count ~= last_track_count then
    scan_track_pairs()
  end
  
  -- Process syncing for all pairs
  process_track_pairs()
  
  reaper.defer(main)
end

-- Initialize
scan_track_pairs()
SetButtonState(1)
main()
reaper.atexit(SetButtonState)