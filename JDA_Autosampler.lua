-- Reaper Autosampler
-- Creates MIDI items per note/velocity and an SFZ mapping

local reaper = reaper

-- Utilities
local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split(s, sep)
  sep = sep or ","
  local t = {}
  for part in string.gmatch(s, "[^" .. sep .. "]+") do
    table.insert(t, trim(part))
  end
  return t
end

-- Split into exactly n parts using a literal separator; the last part may contain the separator
local function split_n(s, sep, n)
  local out = {}
  local start = 1
  for i = 1, n - 1 do
    local a, b = s:find(sep, start, true)
    if not a then
      table.insert(out, trim(s:sub(start)))
      while #out < n do table.insert(out, "") end
      return out
    end
    table.insert(out, trim(s:sub(start, a - 1)))
    start = b + 1
  end
  table.insert(out, trim(s:sub(start)))
  return out
end

local function note_name_to_midi(name)
  -- Accepts forms like C3, C#3, Db3; octave uses C3=60
  if not name or name == "" then return nil end
  name = trim(name)
  local m = {name:match("^([A-Ga-g])([#b]?)(%-?%d+)$")}
  if #m ~= 3 then return nil end
  local n, accidental, oct = m[1]:upper(), m[2], tonumber(m[3])
  local semis = {C=0, D=2, E=4, F=5, G=7, A=9, B=11}
  local v = semis[n]
  if not v then return nil end
  if accidental == "#" then v = v + 1 end
  if accidental == "b" then v = v - 1 end
  local midi = (oct + 2) * 12 + v  -- C3(60) => (3+2)*12=60
  if midi < 0 or midi > 127 then return nil end
  return midi
end

local function midi_to_note_name(midi)
  if midi < 0 then midi = 0 end
  if midi > 127 then midi = 127 end
  local pc = midi % 12
  local oct = math.floor(midi / 12) - 2 -- C3=60
  return string.format("%s%d", NOTE_NAMES[pc+1], oct)
end

local function parse_note_range(range)
  local a, b = range:match("^%s*([^%s%-]+)%s*%-%s*([^%s%-]+)%s*$")
  if not a or not b then return nil, "Range must look like C2-C6" end
  local lo = tonumber(a) or note_name_to_midi(a)
  local hi = tonumber(b) or note_name_to_midi(b)
  if not lo or not hi then return nil, "Invalid note names (use C#3 etc.)" end
  if lo > hi then lo, hi = hi, lo end
  return {lo=lo, hi=hi}
end

local function parse_velocities(s)
  local vals = {}
  -- allow commas, spaces, or semicolons between velocities
  if not s then return nil, "Provide at least one velocity" end
  s = s:gsub("[;%s]+", ",")
  for _,p in ipairs(split(s, ",")) do
    if p ~= "" then
      local v = tonumber(p)
      if not v then return nil, "Velocity must be comma-separated numbers" end
      v = math.max(1, math.min(127, math.floor(v+0.5)))
      table.insert(vals, v)
    end
  end
  table.sort(vals)
  if #vals == 0 then return nil, "Provide at least one velocity" end
  return vals
end

local function compute_velocity_ranges(vels)
  -- Given ascending vels, compute lovel/hivel per layer using midpoints
  local ranges = {}
  for i,v in ipairs(vels) do
    local low
    if i == 1 then
      low = 1
    else
      local prev = vels[i-1]
      low = math.floor((prev + v)/2) + 1
    end
    local high
    if i == #vels then
      high = 127
    else
      local nxt = vels[i+1]
      high = math.floor((v + nxt)/2)
    end
    table.insert(ranges, {vel=v, lovel=low, hivel=high})
  end
  return ranges
end

local function ensure_dir(path)
  reaper.RecursiveCreateDirectory(path, 0)
end

local function join_path(a,b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  local sep = package.config:sub(1,1) -- '\' on Windows
  return a .. sep .. b
end

-- Convert compact/friendly loop mode input to canonical SFZ token
-- (normalize_loop_mode removed; explicit SFZ tokens are used instead)

local function prompt()
  local ok, vals = reaper.GetUserInputs(
    "Autosampler Setup",
    15,
    table.concat({
      "Range (e.g. C2-C6)",
      "Note interval",
      "Note length (sec)",
      "Tail (sec)",
      "Channel (1-16)",
      "Output folder",
      "Name prefix",
      "Write SFZ? (y/n)",
      "Velocities (e.g. 64 127)",
      "Loop mode (N/O/C/S)",
      "Loop start % (0-100)",
      "Loop end % (0-100)",
      "RR count (>=1)",
      "Loop xfade (ms, 0=off)",
      "Extend to full (y/n)",
    },","),
    -- Important: do not include commas in defaults; GetUserInputs splits on commas.
    table.concat({
      "C2-C6","1","1.0","0.3","1","","Patch","y",
      "64 127",
      "N",
      "60",
      "80",
      "1",
      "0",
      "y"
    },",")
  )
  if not ok then return nil, "Cancelled" end
  -- Split to 15 fields; velocity field may contain spaces/semicolons (we normalize later)
  local fields = split_n(vals, ",", 15)
  local R, step, nlen, tail, chan, outdir, prefix, write_sfz, vels,
        loop_mode_in, loop_start_pct_in, loop_end_pct_in, rr_in, loop_xfade_ms_in, extend_full_in = table.unpack(fields)
  local range, er = parse_note_range(R)
  if not range then return nil, er end
  step = tonumber(step or "1") or 1
  step = math.max(1, math.floor(step + 0.5))
  local vel_list, ev = parse_velocities(vels)
  if not vel_list then return nil, ev end
  nlen = tonumber(nlen)
  tail = tonumber(tail)
  chan = tonumber(chan)
  if not (nlen and nlen > 0) then return nil, "Note length must be > 0" end
  if not (tail and tail >= 0) then return nil, "Tail must be >= 0" end
  if not (chan and chan >= 1 and chan <= 16) then return nil, "Channel 1-16" end
  outdir = trim(outdir or "")
  prefix = trim(prefix or "Patch")
  local ws = (write_sfz or "y"):lower()
  local want_sfz = (ws == "y" or ws == "yes" or ws == "1" or ws == "true")

  -- Loop/round-robin
  local allowed_modes = { no_loop=true, one_shot=true, loop_continuous=true, loop_sustain=true }
  local lm_in = trim(loop_mode_in or "")
  local first = lm_in:sub(1,1):lower()
  local loop_mode
  if first == 'n' then
    loop_mode = 'no_loop'
  elseif first == 'o' then
    loop_mode = 'one_shot'
  elseif first == 'c' then
    loop_mode = 'loop_continuous'
  elseif first == 's' then
    loop_mode = 'loop_sustain'
  else
    local lm = lm_in:lower()
    loop_mode = allowed_modes[lm] and lm or 'no_loop'
  end
  local ls_pct = tonumber(loop_start_pct_in) or 20
  local le_pct = tonumber(loop_end_pct_in) or 80
  -- Clamp and sanitize
  ls_pct = math.max(0, math.min(100, ls_pct))
  le_pct = math.max(0, math.min(100, le_pct))
  if le_pct <= ls_pct then
    if le_pct >= 99 then ls_pct, le_pct = 0, 100 else ls_pct, le_pct = math.max(0, le_pct-1), le_pct end
  end
  local rr = math.max(1, math.floor((tonumber(rr_in) or 1) + 0.0))
  local loop_xfade_ms = math.max(0, math.floor((tonumber(loop_xfade_ms_in) or 0) + 0.0))
  local extend_full = false
  do
    local ef = (extend_full_in or "n"):lower()
    extend_full = (ef == "y" or ef == "yes" or ef == "1" or ef == "true")
  end

  -- Project sample rate (0 means follow audio device; fallback to 44100 here)
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if not sr or sr <= 0 then sr = 44100 end
  return {
    range=range,
    step=step,
    velocities=vel_list,
    vel_ranges=compute_velocity_ranges(vel_list),
    note_len=nlen,
    tail=tail,
    chan=chan-1,
    outdir=outdir,
    prefix=prefix,
    write_sfz=want_sfz,
    sample_rate=sr,
    loop_mode=loop_mode,
    loop_start_pct=ls_pct,
    loop_end_pct=le_pct,
    rr_count=rr,
    loop_xfade_ms=loop_xfade_ms,
    extend_full=extend_full
  }
end

local function get_selected_track()
  local cnt = reaper.CountSelectedTracks(0)
  if cnt ~= 1 then return nil, "Select exactly one instrument track" end
  return reaper.GetSelectedTrack(0,0)
end

local function insert_midi_item(track, pos, note_len, tail, chan, pitch, vel)
  local item = reaper.CreateNewMIDIItemInProj(track, pos, pos + note_len + tail, false)
  if not item then return nil end
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local ppq_start = reaper.MIDI_GetPPQPosFromProjTime(take, pos)
  -- Note-off should occur at note_len (tail is captured by item length only)
  local ppq_noteoff = reaper.MIDI_GetPPQPosFromProjTime(take, pos + note_len)
  reaper.MIDI_InsertNote(take, false, false, ppq_start, ppq_noteoff, chan, pitch, vel, false)
  reaper.MIDI_Sort(take)
  return item, take
end

local function build_items(cfg, track)
  -- Lay items sequentially to avoid overlap
  local items = {}
  local gap = 0.0
  local seg = cfg.note_len + cfg.tail + gap
  local t = reaper.GetCursorPosition()
  for note = cfg.range.lo, cfg.range.hi, cfg.step do
    for _,vr in ipairs(cfg.vel_ranges) do
      local rrn = cfg.rr_count or 1
      for rr = 1, rrn do
        local item, take = insert_midi_item(track, t, cfg.note_len, cfg.tail, cfg.chan, note, vr.vel)
        if item and take then
          local nn = midi_to_note_name(note)
          local base = string.format("%s_%s_v%d", cfg.prefix, nn, vr.vel)
          if rrn > 1 then base = string.format("%s_rr%d", base, rr) end
          reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", base, true)
          table.insert(items, {
            item=item, take=take, note=note, vel=vr.vel,
            lovel=vr.lovel, hivel=vr.hivel, name=base, rr=rr
          })
        end
        t = t + seg
      end
    end
  end
  return items
end

local function write_sfz(cfg, items)
  if cfg.outdir == "" then
    -- Default to project directory
    local proj_path = reaper.GetProjectPath(0, "")
    cfg.outdir = proj_path
  end
  ensure_dir(cfg.outdir)
  local sfz_path = join_path(cfg.outdir, cfg.prefix .. ".sfz")
  local fh, err = io.open(sfz_path, "w")
  if not fh then return nil, err end
  fh:write("<group>\n")
  fh:write(string.format("// Autosampler export - %s\n", os.date()))
  -- Group-level defaults
  if cfg.loop_mode == "loop_continuous" or cfg.loop_mode == "loop_sustain" then
    fh:write(string.format("loop_mode=%s\n", cfg.loop_mode))
    -- Derive loop points from note_len at project SR, in frames
    local total_frames = math.max(1, math.floor(cfg.note_len * cfg.sample_rate + 0.5))
    local ls = math.floor((cfg.loop_start_pct/100.0) * total_frames + 0.5)
    local le = math.floor((cfg.loop_end_pct/100.0) * total_frames + 0.5)
    if le <= ls then le = math.min(total_frames-1, ls + 1) end
    fh:write(string.format("loop_start=%d\n", ls))
    fh:write(string.format("loop_end=%d\n", le))
    if (cfg.loop_xfade_ms or 0) > 0 then
      local xfade = math.max(1, math.floor((cfg.loop_xfade_ms/1000.0) * cfg.sample_rate + 0.5))
      fh:write(string.format("loop_crossfade=%d\n", xfade))
    end
  elseif cfg.loop_mode == "one_shot" then
    fh:write("loop_mode=one_shot\n")
  end
  if cfg.rr_count and cfg.rr_count > 1 then
    fh:write(string.format("seq_length=%d\n", cfg.rr_count))
  end
  -- Compute key ranges from sampled centers using midpoints
  local note_set = {}
  for _,it in ipairs(items) do note_set[it.note] = true end
  local centers = {}
  for n,_ in pairs(note_set) do table.insert(centers, n) end
  table.sort(centers)
  local boundaries = {}
  for i = 1, #centers - 1 do
    boundaries[i] = math.floor((centers[i] + centers[i+1]) / 2)
  end
  local key_range_by_center = {}
  for i,center in ipairs(centers) do
    local lokey = (i == 1) and (cfg.extend_full and 0 or cfg.range.lo) or (boundaries[i-1] + 1)
    local hikey = (i == #centers) and (cfg.extend_full and 127 or cfg.range.hi) or boundaries[i]
    key_range_by_center[center] = {lokey=lokey, hikey=hikey}
  end

  -- Regions per item; each RR variant is a distinct sample with matching seq_position
  for _,it in ipairs(items) do
    local sample = it.name .. ".wav" -- assume render uses take name
    local kr = key_range_by_center[it.note] or {lokey=it.note, hikey=it.note}
    if cfg.rr_count and cfg.rr_count > 1 then
      fh:write(string.format(
        "<region> sample=%s key=%d lokey=%d hikey=%d pitch_keycenter=%d lovel=%d hivel=%d seq_position=%d\n",
        sample, it.note, kr.lokey, kr.hikey, it.note, it.lovel, it.hivel, it.rr or 1
      ))
    else
      fh:write(string.format(
        "<region> sample=%s key=%d lokey=%d hikey=%d pitch_keycenter=%d lovel=%d hivel=%d\n",
        sample, it.note, kr.lokey, kr.hikey, it.note, it.lovel, it.hivel
      ))
    end
  end
  fh:close()
  return sfz_path
end

local function main()
  reaper.Undo_BeginBlock()
  local cfg, err = prompt()
  if not cfg then
    reaper.ShowMessageBox(err or "Invalid input", "Autosampler", 0)
    return
  end
  local track, terr = get_selected_track()
  if not track then
    reaper.ShowMessageBox(terr or "Select one track", "Autosampler", 0)
    return
  end

  local items = build_items(cfg, track)
  if #items == 0 then
    reaper.ShowMessageBox("Failed to create MIDI items", "Autosampler", 0)
    return
  end

  local sfz_path = nil
  if cfg.write_sfz then
    local serr
    sfz_path, serr = write_sfz(cfg, items)
    if not sfz_path then
      reaper.ShowMessageBox("Could not write SFZ: " .. (serr or ""), "Autosampler", 0)
      return
    end
  end

  -- Select all created items for convenience
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  for _,it in ipairs(items) do
    reaper.SetMediaItemSelected(it.item, true)
  end
  reaper.UpdateArrange()

  -- Usage hint
  local msg
  if cfg.write_sfz then
    msg = ([[Created %d MIDI items and SFZ:
%s

Render the samples:
- Keep the items selected and open File > Render (Ctrl+Alt+R)
- Source: Selected media items
- Directory: %s
- File name: $item (keeps names consistent if you build a map later)
- Render

Make sure to do an Online Render if you're recording hardware.]]):format(#items, sfz_path, (cfg.outdir ~= "" and cfg.outdir or reaper.GetProjectPath(0, "")))
  else
    msg = ([[Created %d MIDI items (SFZ skipped)

Render the samples:
- Keep the items selected and open File > Render (Ctrl+Alt+R)
- Source: Selected media items
- Directory: %s
- File name: $item (keeps names consistent if you build a map later)
- Render

Make sure to do an Online Render if you're recording hardware.]]):format(#items, (cfg.outdir ~= "" and cfg.outdir or reaper.GetProjectPath(0, "")))
  end
  reaper.ShowMessageBox(msg, "Autosampler", 0)
  reaper.Undo_EndBlock("Autosampler: build MIDI + SFZ", -1)
end

reaper.PreventUIRefresh(1)
local ok, err = xpcall(main, debug.traceback)
reaper.PreventUIRefresh(-1)
if not ok then
  reaper.ShowMessageBox("Error: " .. tostring(err), "Autosampler", 0)
end
