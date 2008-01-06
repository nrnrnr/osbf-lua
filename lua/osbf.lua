--  OSBF-Lua anti-spam filter 
--
--  Permission is hereby granted, free of charge, to any person obtaining
--  a copy of this software and associated documentation files (the
--  "Software"), to deal in the Software without restriction, including
--  without limitation the rights to use, copy, modify, merge, publish,
--  distribute, sublicense, and/or sell copies of the Software, and to
--  permit persons to whom the Software is furnished to do so, subject to
--  the following conditions:
--
--  The above copyright notice and this permission notice shall be
--  included in all copies or substantial portions of the Software.
--
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
--  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
--  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
--  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
--  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
--  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
--  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
--  Copyright (C) 2005-2008 Fidelis Assis, all rights reserved.
--  Copyright (C) 2007-2008 Norman Ramsey, all rights reserved.


-- exports:
-- osbf.init
-- osbf.command

local require, print, pairs, ipairs, type, io, string, table, os, _G =
      require, print, pairs, ipairs, type, io, string, table, os, _G

module(...)

-- can't use _PACKAGE here because that's for siblings, not children
local boot = require (_NAME .. '.boot')
require (_NAME .. '.commands')
init = boot.init

__doc = {
  init = [[function(options, no_dirs_ok) returns nothing
Initialize the system passing a table in which the indices are common
options and the values are strings or booleans.  This table should be
returned from options.parse.  If no_dirs_ok is not true, fail if
directories are missing.  This no_dirs_ok is true, continue regardless
of missing directories---the caller must call commands.init as the
next step.
]],
}

