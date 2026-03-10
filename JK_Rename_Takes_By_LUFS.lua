--[[
  @author Jake Kantzer
  @license MIT
  @version 1.1.0
  @about Rename selected takes by their LUFS values
  @provides
    [main] JK_Rename_Takes_By_LUFS.lua
]]

function get_item_lufs(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return nil end

  -- NF_AnalyzeTakeLoudness_IntegratedOnly returns retval (boolean/int), lufs (number)
  local retval, lufs = reaper.NF_AnalyzeTakeLoudness_IntegratedOnly(take, 0)

  if retval == true or retval == 1 then
    return lufs
  end

  return nil
end

function main()
  -- Check if SWS extension is installed
  if not reaper.NF_AnalyzeTakeLoudness_IntegratedOnly then
    reaper.ShowMessageBox("This script requires SWS extension to be installed.", "Error", 0)
    return
  end

  -- Get selected items
  local num_items = reaper.CountSelectedMediaItems(0)
  if num_items == 0 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Process each selected item
  for i = 0, num_items - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)

    if take then
      -- Get LUFS value
      local lufs = get_item_lufs(item)

      if lufs then
        -- Get current take name
        local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)

        -- Remove previous [X LUFS] suffix if it exists
        take_name = take_name:gsub("%s?%[.-%sLUFS%]", "")

        -- Format LUFS value to one decimal place
        local lufs_str = string.format("%.1f", lufs)

        -- Set new take name with LUFS suffix
        local new_name = take_name .. " [" .. lufs_str .. " LUFS]"
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('Rename Takes by LUFS', -1)
end

main()
