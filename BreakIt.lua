-- analyze.lua
-- Hard-block + payload dumper harness

local logfile = io.open("stage1_trace.log", "a")

local function log(...)
  local t = {}
  for i = 1, select("#", ...) do
    t[#t+1] = tostring(select(i, ...))
  end
  logfile:write(os.date("[%H:%M:%S] "), table.concat(t, " "), "\n")
  logfile:flush()
end

-- BLOCK external execution
local real_os_execute = os.execute
os.execute = function(cmd)
  log("[os.execute BLOCKED]", cmd)
  return 0
end

local real_io_popen = io.popen
io.popen = function(cmd, mode)
  log("[io.popen BLOCKED]", cmd, mode)
  return nil
end

-- DUMP dynamically loaded Lua
local real_load = load
load = function(chunk, ...)
  if type(chunk) == "string" then
    log("[load STRING PAYLOAD]", "len=", #chunk)
    local f = io.open("dumped_payload.lua", "wb")
    f:write(chunk)
    f:close()
  end
  return real_load(chunk, ...)
end

-- LOG file creation + dump writes
local real_io_open = io.open
io.open = function(path, mode)
  log("[io.open]", path, mode)
  local fh = real_io_open(path, mode)

  -- If it's userdata (C file handle), we cannot override methods
  if fh and type(fh) == "userdata" then
    log("[io.open] file handle is userdata, cannot wrap .write")
    return fh
  end

  -- If it's a Lua object with methods, wrap .write
  if fh and type(fh) == "table" and fh.write then
    local real_fh_write = fh.write
    fh.write = function(self, data)
      log("[file.write]", path, "len=", #tostring(data))
      return real_fh_write(self, data)
    end
  end

  return fh
end


-- Optional: catch env swapping / dump tricks
if string and string.dump then
  local real_string_dump = string.dump
  string.dump = function(fn)
    log("[string.dump]", fn)
    return real_string_dump(fn)
  end
end

if setfenv then
  local real_setfenv = setfenv
  setfenv = function(f, env)
    log("[setfenv]", f, env)
    return real_setfenv(f, env)
  end
end

-- >>> THIS IS THE ONLY PLACE YOU NAME THE REAL SCRIPT <<<
local TARGET_SCRIPT = "obfuscated.lua"

log("[launcher] starting", TARGET_SCRIPT)

-- Run stage 1 under hooks
local ok, err = pcall(dofile, TARGET_SCRIPT)
if not ok then
  log("[launcher] error:", err)
end

log("[launcher] done")
logfile:close()
