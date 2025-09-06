--[[
  @author Jake d'Arc
  @license MIT
  @version 1.0.0
  @about Auto-add sends (at -inf dB) from newly created tracks to all tracks with names ending in " [FX]". Skips tracks that have a hardware MIDI output. Persistently remembers processed tracks per-project so it never re-applies to existing tracks.
  @changelog
    - Initial version
  @provides
    [main] JDA_Auto_Add_Sends_To_FX_Tracks.lua
]]

local SCRIPT_NAME = "Auto add -inf sends to [FX] (new tracks only)"
local EXT_SECTION = "JDA_AUTO_SENDS"
local EXT_KEY = "processed_guids"

-- Toggle button helpers
local function SetButtonState(set)
  local _, _, sec, cmd = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

-- Serialize/deserialze a simple newline-separated list of GUIDs
local function loadProcessed()
  local t = {}
  local _, buf = reaper.GetProjExtState(0, EXT_SECTION, EXT_KEY)
  if buf and #buf > 0 then
    for guid in string.gmatch(buf, "[^\n]+") do
      t[guid] = true
    end
  end
  return t
end

local function saveProcessed(set)
  local out = {}
  for guid, ok in pairs(set) do
    if ok then table.insert(out, guid) end
  end
  reaper.SetProjExtState(0, EXT_SECTION, EXT_KEY, table.concat(out, "\n"))
end

local function trackGUID(track)
  -- Returns a stable string GUID like "{...}"
  return reaper.GetTrackGUID(track)
end

local function listFXTracks()
  local list = {}
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name:sub(-5) == " [FX]" then
      table.insert(list, { track = tr, name = name })
    end
  end
  return list
end

local function hasSendToDestByName(srcTrack, destName)
  local sendCount = reaper.GetTrackNumSends(srcTrack, 0) -- 0 = HW/Sends
  for i = 0, sendCount - 1 do
    local ok, sname = reaper.GetTrackSendName(srcTrack, i)
    if ok and sname == destName then
      return true
    end
  end
  return false
end

local function addSendsAtNegInf(srcTrack, fxList)
  local added = false
  for _, fx in ipairs(fxList) do
    if not hasSendToDestByName(srcTrack, fx.name) then
      local sendIdx = reaper.CreateTrackSend(srcTrack, fx.track)
      if sendIdx >= 0 then
        -- Set to -inf dB by using linear 0.0 (D_VOL)
        reaper.SetTrackSendInfo_Value(srcTrack, 0, sendIdx, "D_VOL", 0.0)
        added = true
      end
    end
  end
  return added
end

-- State to reduce CPU: only react when project state changes
local last_state_change = reaper.GetProjectStateChangeCount(0)

-- Load processed GUIDs; on first run, mark all existing tracks as processed (no retroactive sends)
local processed = loadProcessed()
do
  local n = reaper.CountTracks(0)
  local saw_any = false
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local guid = trackGUID(tr)
    if not processed[guid] then
      processed[guid] = true
      saw_any = true
    end
  end
  if saw_any then saveProcessed(processed) end
end

local function main()
  local cur_state = reaper.GetProjectStateChangeCount(0)

  -- Skip if nothing changed
  if cur_state == last_state_change then
    reaper.defer(main)
    return
  end

  -- If there is an active Redo string, avoid acting mid-undo/redo
  local redo_text = reaper.Undo_CanRedo2(0)
  if redo_text and redo_text ~= "" then
    last_state_change = cur_state
    reaper.defer(main)
    return
  end

  local fxList = listFXTracks()
  local n = reaper.CountTracks(0)
  local mut_changed = false

  -- Scan for brand new tracks by GUID
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local guid = trackGUID(tr)
    if not processed[guid] then
      -- Mark as processed regardless of whether FX exists (new tracks only policy)
      processed[guid] = true
      mut_changed = true

      -- Basic skip: ignore tracks with hardware MIDI output
      local has_hw_midi = (reaper.GetMediaTrackInfo_Value(tr, "I_MIDIHWOUT") or -1) >= 0

      if #fxList > 0 and not has_hw_midi then
        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)
        addSendsAtNegInf(tr, fxList)
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Auto-add -inf sends to [FX] tracks", -1)
        reaper.UpdateArrange()
      end
    end
  end

  if mut_changed then
    saveProcessed(processed)
  end

  last_state_change = cur_state
  reaper.defer(main)
end

-- Start script with toggle state
SetButtonState(1)
reaper.atexit(function() SetButtonState(0) end)
main()
