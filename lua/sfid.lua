-- See Copyright Notice in osbf.lua

local require, print, pairs, ipairs, type, error, assert, tostring, pcall =
      require, print, pairs, ipairs, type, error, assert, tostring, pcall

local table =
      table
      

module(...)

local util      = require(_PACKAGE .. 'util')
local cfg       = require(_PACKAGE .. 'cfg')
local cache     = require(_PACKAGE .. 'cache')

__doc = {}

__doc.sfid = [[function(msg.T, [msgspec]) returns string or calls error
Extracts the sfid from the headers of the specified message.
Optional argument used for error messages.]]

local ref_pat, com_pat -- depend on cfg and cache; don't set until needed

local sfid_header
cfg.after_loading_do(
  function() sfid_header = cfg.header_prefix .. '-' .. cfg.header_suffixes.sfid end)

function sfid(msg, spec)
  -- if the sfid was not given in the command, extract it
  -- from the appropriate header or from the references or in-reply-to field

  local sfid = msg[sfid_header]
  if sfid then return sfid end

  ref_pat = ref_pat or '.*<(' .. cache.loose_sfid_pat .. ')>'
  com_pat = com_pat or '.*%((' .. cache.loose_sfid_pat .. ')%)'
  
  for refs in msg:_headers_tagged 'references' do
    -- match the last sfid in the field (hence the initial .* in ref_pat)
    local sfid = refs:match(ref_pat)
    if sfid then return sfid end
  end

  -- if not found as a reference, try as a comment in In-Reply-To or in References
  for field in msg:_headers_tagged('in-reply-to', 'references') do
    local sfid = field:match(com_pat)
    if sfid then return sfid end
  end
  
  error('Could not extract sfid from message ' .. (spec or tostring(msg)))
end

__doc.has_sfid = [[function(msg.T) returns bool
Tells whether the given message contains a sfid in one
of the relevant headers.
]]

function has_sfid(msg)
  return (pcall(sfid, msg)) -- just the one result
end

local msg = require(_PACKAGE .. 'msg')
for k, v in pairs(_M) do
  if msg[k] == nil then
    msg[k] = v
    if __doc[k] and not msg.__doc[k] then
      msg.__doc[k] = table.concat { __doc[k], '\n(copied from ', _PACKAGE, (...), ')' }
    end
  end
end
