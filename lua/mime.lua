-- See Copyright Notice in osbf.lua

local string, os =
      string, os

local require, print, pairs, ipairs, type, error, assert, tonumber =
      require, print, pairs, ipairs, type, error, assert, tonumber

local tostring, pcall =
      tostring, pcall

module(...)

local util      = require(_PACKAGE .. 'util')
local cache     = require(_PACKAGE .. 'cache')

__doc = {}

__doc.rfc2822_to_localtime_or_nil = [[function(date) returns number or nil
Converts RFC2822 date to local time (Unix time).
]]

local tmonth = {jan=1, feb=2, mar=3, apr=4, may=5, jun=6,
                jul=7, aug=8, sep=9, oct=10, nov=11, dec=12}

function rfc2822_to_localtime_or_nil(date)
  -- remove comments (CFWS)
  date = string.gsub(date, "%b()", "")

  -- Ex: Tue, 21 Nov 2006 14:26:58 -0200
  local day, month, year, hh, mm, ss, zz =
    string.match(date,
     "%a%a%a,%s+(%d+)%s+(%a%a%a)%s+(%d%d+)%s+(%d%d):(%d%d)(%S*)%s+(%S+)")

  if not (day and month and year) then
    day, month, year, hh, mm, ss, zz =
    string.match(date,
     "(%d+)%s+(%a%a%a)%s+(%d%d+)%s+(%d%d):(%d%d)(%S*)%s+(%S+)")
    if not (day and month and year) then
      return nil
    end
  end

  local month_number = tmonth[string.lower(month)]
  if not month_number then
    return nil
  end

  year = tonumber(year)

  if year >= 0 and year < 50 then
    year = year + 2000
  elseif year >= 50 and year <= 99 then
    year = year + 1900
  end

  if not ss or ss == "" then
    ss = 0
  else
    ss = string.match(ss, "^:(%d%d)$")
  end

  if not ss then
    return nil
  end


  local zonetable = { GMT = 0, UT = 0,
                      EDT = -4,
                      EST = -5, CDT = -5,
                      CST = -6, MDT = -6,
                      MST = -7, PDT = -7,
                      PST = -8,
                    } -- todo: military zones
                      

  local tz = nil
  local s, zzh, zzm = string.match(zz, "([-+])(%d%d)(%d%d)")
  if s and zzh and zzm then
    tz = zzh * 3600 + zzm * 60
    if s == "-" then tz = -tz end
  elseif zonetable[zz] then
    tz = zonetable[zz] * 3600
  else
    return nil -- OBS: RFC 2822 says in this case tz = 0, but we prefer not
               -- to convert and return nil to signal that date should be
               -- shown in the original format.
  end

  -- get the Unix time of the date of the message
  -- sec might be out of range after subtracting tz but mktime,
  -- called by os.time, normalizes the values if needed.
  local ts = os.time{year=year, month=month_number,
                      day=day, hour=hh, min=mm, sec=ss-tz}

  if not ts then
    util.errorf('Failed to convert [[%s]] to local time', date)
  end

  -- os.time considers the broken-down time as local time, but
  -- RFC2822 date becomes UTC after the zone is subtracted, so
  -- an adjustment is necessary to the ts calculated above.
  local lts = ts + util.localtime_minus_UTC(ts)
  
  -- we need the difference of localtime and UTC at the date of the
  -- message, which may not be the same as the current timezone.
  return ts + util.localtime_minus_UTC(lts)
end

