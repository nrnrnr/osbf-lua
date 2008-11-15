-- Command for creating a training-form email
--
-- See Copyright Notice in osbf.lua


local require, print, pairs, ipairs, type, assert, setmetatable =
      require, print, pairs, ipairs, type, assert, setmetatable

local os, string, table, math, tostring =
      os, string, table, math, tostring

local modname = ...
local modname = modname:gsub('[^%.]+$', 'commands')
module(modname)

__doc = __doc or { }

local util   = require(_PACKAGE .. 'util')
local cfg    = require(_PACKAGE .. 'cfg')
local msg    = require(_PACKAGE .. 'msg')
local core   = require(_PACKAGE .. 'core')
local cache  = require(_PACKAGE .. 'cache')
local output = require(_PACKAGE .. 'output')
local mime   = require(_PACKAGE .. 'mime')


local html = util.html

----------------------------------------------------------------
---- Color and template support

local colors = {
  background = '#ffec8b',
  menubg = '#acac7c',
  border = '#3d0000',
  class = {
    spam = "#ff0000",
    ham = "#0000aa",
  },
  default = "#000000",
  invalid = "#ff0000", -- color for an invalid date
  tag = { },
}

local class_of_tag = cfg.class_of_tag

do
  local function set_class_colors()
    for class, tbl in pairs(cfg.classes) do
      colors.tag[tbl.sfid] = colors.class[class] or colors.default
    end
  end
  cfg.after_loading_do(set_class_colors)
end

local function tag_color(s)
  return assert(colors.tag[string.lower(s)],
                'Report: tag letter does not correspond to any class')
end

local function replace_dollar(s, t)
  return (s:gsub('%$colors%.([%a_]+)', colors):gsub('%$([%a_]+)', t))
end


----------------------------------------------------------------
---- Language/Locale Support


local homelink = html.a({href=cfg.homepage}, 'OSBF-Lua')

-- how to render menu items, table headings, etc in English
local English = {
  homelink = homelink,
  subject = "OSBF-Lua training form",
  send_actions = "Send Actions",
  title = [[$homelink Training Form<br>
            Check the pre-selected actions, change if necessary, 
            and click "$send_actions"]],
  title_nready  = [[$homelink Training Form<br>
            Select the proper training action for each message
            and click "$send_actions"]],
  actions = {
    none        = "None",
    resend     = "Recover message",
    remove      = "Remove from cache",
    whitelist_from     = "Add 'From:' to whitelist",
    whitelist_subject = "Add 'Subject:' to whitelist",
    train_as  = "Train as %s",
    undo = "Undo training",
  },
  class_names = { }, -- no mapping for class names
  train_nomsgs  = "No messages for training",
  table = 
    { date  = "Date", from = "From", subject = "Subject", confidence = "Class [confidence]", action = 'Action' },

  stats = {
    stats = "Statistics",
    num_class = "Classifications",
    false_negatives = "False negatives",
    false_positives = "False positives",
    learnings = "Learnings",
    accuracy = "Accuracy",
    total = "Total",
  },
}

-- how to render menu items, table headings, etc in Brazilian Portuguese
local Brazilian_Portuguese = {
  homelink = homelink,
  subject = "OSBF-Lua - =?ISO-8859-1?Q?formul=E1rio_de_treinamento?=",
  send_actions = "Enviar A&ccedil;&otilde;es",
  title = [[$homelink - Formul&aacute;rio de treinamento<br>
            Verifique as a&ccedil&otilde;es pr&eacute;-selecionadas, 
            altere se necess&aacute;rio, e clique em "$send_actions"]],
  title_nready = [[$homelink - Formul&aacute;rio de treinamento<br>
                   Selecione a a&ccedil;&atilde;o de treinamento
                   adequada para cada mensagem e clique em "$send_actions"]],
  actions = { 
    none        = "Nenhuma",
    resend     = "Recuperar mensagem",
    remove      = "Remover do cache",
    whitelist_from    = "P&ocirc;r remetente em whitelist",
    whitelist_subject = "P&ocirc;r 'Assunto:' em whitelist",
    train_as  = "Treinar como %s",
    undo = "Desfazer treinamento",
  },
  class_names = { -- graciously map English class names to Portuguese if needed
    ham = "N&atilde;o-Spam",
  },
    
  train_nomsgs  = "N&atilde;o h&aacute; mensagens para treinamento",
  table = { date  = "Data", from = "De", subject = "Assunto",
            confidence = "Classe [pontua&ccedil;&atilde;o]", action = "A&ccedil;&atilde;o" },

  stats = {
    stats     = "Estat&iacute;sticas",
    num_class = "Classifica&ccedil;&otilde;es",
    false_negatives  = "Falsos negativos",
    false_positives  = "Falsos positivos",
    learnings = "Treinamentos",
    accuracy  = "Precis&atilde;o",
    spam      = "Spam",
    ham       = "N&atilde;o Spam",
    total     = "Total",
  },
}

local languages = { en_us = English, pt_br = Brazilian_Portuguese, posix = English }

local language -- set (potentially differently) for each report generated

-- not sensible to call this function until user config is loaded
local function set_language(opt_locale)
  ----- set language according to locale
  local locale =
    opt_locale or
    type(cfg.cache.report_locale) == 'string' and cfg.cache.report_locale or
    os.getenv 'LANGUAGE' or
    'posix'
  for l in string.gmatch(locale, '[^:]+') do
    local lang = languages[string.lower(l)]
    if lang then
      language = lang
      break
    end
  end
  language = language or languages.posix

  -- flatten actions
  for k, v in pairs(language.actions) do
    language[k] = v
  end

  -- replace $ strings (shallow only; $ may not refer to $)
  for k, v in pairs(language) do
    if type(v) == 'string' then
      language[k] = replace_dollar(v, language)
    end
  end
end
----------------------------------------------------------------
---- combined support for color and localization

local function localize(x)
  if type(x) == 'string' then
    return replace_dollar(x, language)
  else
    assert(type(x) == 'table')
    setmetatable(x, { __index = language })
    return x
  end
end

--====================== MESSAGE SUPPORT =========================
----------------------------------------------------------------
----- functions used to build message

local html_stat_table, html_sfid_rows, html_style

----------------------------------------------------------------
----- building the training message

local function message(sfids, email, temail, ready)
  local message = [[
From: $email
To: $email
X-Spamfilter-Lua-Whitelist: $password
Subject: $subject
MIME-Version: 1.0
Content-Type: multipart/mixed;
	boundary="--=-=-=-train-report-boundary-=-=-="

This is a multi-part message in MIME format.

----=-=-=-train-report-boundary-=-=-=
Content-Type: text/html
Content-Transfer-Encoding: quoted-printable

$body
----=-=-=-train-report-boundary-=-=-=--
]]

  local body = [[<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
    <html>
      <head>
        <meta content="text/html; charset=ISO-8859-1"
            http-equiv="content-type">
       <title>Train_form</title>
       <style>$style</style>
      </head>
      <body>
      $payload
      </body>
    </html>
  ]]

  local payload =
  #sfids == 0 and [[
     <center>$train_nomsgs</center><p>
     $stats
  ]] or [[
    <div style="text-align: left;">
      <small>
        <span style="font-weight: bold; font-family: Helvetica, sans-serif;">
           <i>$title</i>
        </span>
      </small>
    </div>
    <br>
    <form enctype="text/plain" method="post" 
          action="mailto:$temail?subject=batch_train $password" name="TRAIN_FROM">
      <div style="text-align: center;"></div>
      <table style="text-align: left; max-width: 80%; height: 48px;" 
             border="0" cellpadding="2" cellspacing="2"><tbody>
      $sfid_rows
      </tbody></table>
      <br>
      <div style="text-align: center;">
      <input accesskey="E" type="submit" value="$send_actions"></div>
    </form>
    <br><hr><br>
    $stats
  ]]

  local data = localize {
    email     = email,
    temail    = temail,
    password  = cfg.pwd,
    style     = html_style,
    stats     = html_stat_table(),
    sfid_rows = html_sfid_rows(sfids, ready),
  }
  local qp = util.encode_quoted_printable
  data.payload =    replace_dollar(payload, data)
  data.body    = qp(replace_dollar(body,    data))
  return            replace_dollar(message, data)
end

html_style = [[
select.menu, option.menu {
  font-family: Helvetica, sans-serif;
  font-size: 11px;
}

tr.msgs {
  font-family: Helvetica, sans-serif;
  font-size: 14px;
  height: 24px;
  background-color: #ddeedd;
}

tr.stats_header {
  font-family: Helvetica, sans-serif;
  font-size: 12px;
  color: rgb(0, 0, 0);
  background-color: rgb(172, 172, 124);
}
tr.stats_row {
  font-family: Helvetica, sans-serif;
  font-size: 12px;
  color: rgb(0, 0, 0);
  background-color: rgb(221, 238, 221);
  text-align: right;
}
tr.stats_footer {
  font-family: Helvetica, sans-serif;
  font-size: 12px;
  color: rgb(0, 0, 0);
  background-color: rgb(201, 216, 201);
  text-align: right;
}
]]  

----------------------------------------------------------
---- rows of the cache report (one per message)

local max_widths = { date = 18, from = 23, subject = 45, confidence = 10 }

-- template for row of the sfid table (one per message)
local sfid_row = [[
<tr class="msgs">
 <td style="width: 13%; max-width: $mwd%; color: $datecolor;"><small>$date</small></td>
 <td style="width: 24%; max-width: $mwf%; color: $fgcolor;"><small>$from</small></td>
 <td style="width: 43%; max-width: $mws%; color: $fgcolor;">
                                                         <small>$subject</small></td>
 <td style="width:  7%; max-width: $mwc%; vertical-align: middle; color: $fgcolor;">
                                                        <p><small>$confidence</small></td>
 <td style="width: 13%; max-width: $mwa%; vertical-align: middle; color: $fgcolor;">
                                                        <p><small>$select</small></td>
 </tr>
]]
do
  -- fill in the widths in the template
  local t = { }
  for k, v in pairs(max_widths) do
    t['mw' .. string.sub(k, 1, 1)] = v
  end
  sfid_row = replace_dollar(sfid_row, t)
end

local html_first_row --- the table header
do
  local col = [[
  <th style="text-align: center; max-width: $mw%; font-family: Helvetica, sans-serif;
      background-color: $colors.menubg; height: 24px;"><p><small>
      <span style="font-weight: bold;">$contents</span></small></p> 
  </th>]]

  function html_first_row()
    local cols = { }
    for _, what in ipairs { 'date', 'from', 'subject', 'confidence', 'action' } do
      local data = { mw = max_widths[what], contents = language.table[what] }
      table.insert(cols, replace_dollar(col, data))
    end
    return html.tr(table.concat(cols, '\n'))
  end
end

local sfid_menu --- defined below

function html_sfid_rows(sfids, ready) -- declared local above

  -- for case insensitive match - from PIL
  local function nocase (s)
    return (string.gsub(s, "%a", function (c)
          return string.format("[%s%s]", string.lower(c),
                                         string.upper(c))
        end))
  end
  rows = { html_first_row() }
  for _, sfid in ipairs(sfids) do
    local m = msg.of_string(cache.recover(sfid))
    local sfid_table = cache.table_of_sfid(sfid)
    util.validate(m, 'Sudden disappearance of sfid from the cache')
    local function header(tag) return m[tag] or string.format('(no %s)', tag) end
    local function htmlify(s, n)
      -- strip RFC2822 quotation from s and make sure it contains no word
      -- longer than n characters (by inserting spaces if necessary), then
      -- convert iso-8859-1 or utf-8 encoded chars to html with
      -- html.of_iso_8859_1_or_utf8. The length limit prevents the HTML
      -- browser from showing overwide columns.
      s = s:gsub("=%?(.-)%?([BbQq])%?(.-)%?=", util.html.of_iso_8859_1_or_utf8)
    do
      local h, i = {}, 0
      -- do not break html sequences '&...;'
      s = s:gsub("&[^;]+;", function (c) h[#h+1] = c return '\1' end)
      s = s:gsub("(" .. string.rep("%S", n) ..")(%S)", "%1 %2")
      s = s:gsub('\1', function(c) i = i+1 return h[i] end )
end

      return s
    end

    local subject, from, date  = header 'subject', header 'from', header 'date'
    from, subject = htmlify(from, 32), htmlify(subject, 40)

    local tag       = assert(sfid_table.tag)
    local fgcolor   = ready and assert(tag_color(tag)) or colors.default
    local lts       = mime.rfc2822_to_localtime_or_nil(date) 
    local date      = lts and os.date("%Y/%m/%d %H:%M", lts) or date
    local datecolor = lts and fgcolor or colors.invalid

    local data = {
      datecolor = datecolor, fgcolor = fgcolor,
      from = from, subject = subject, date = date,
      confidence = table.concat { sfid_table.class, ' [',
                   tostring(sfid_table.confidence), ']' },
      select = sfid_menu(sfid, tag, ready)
    }

    table.insert(rows, replace_dollar(sfid_row, data))
  end

  return table.concat(rows)
end

do
  local menu_items = { -- menu possibilities per each message
    "none", "resend", "remove", "whitelist_from", "whitelist_subject", "undo"
  }
  local function insert_classes_in_menu()
    for _, class in ipairs(cfg.classlist()) do
      table.insert(menu_items, #menu_items, class)
    end
  end
  cfg.after_loading_do(insert_classes_in_menu)

  function sfid_menu(sfid, tag, ready) -- declared local above
    local selected = { }
    selected[ready and class_of_tag[tag] or 'none'] = true

    local function menu_item(choice)
      local label = language[choice] or
                    cfg.classes[choice] and string.format(language.train_as, choice) or
                    '(Nothing for ' .. choice .. '?!)'
      return string.format([[<option class="menu" value="%s"%s>%s]],
                           choice, selected[choice] and ' selected' or '', label)
    end

    local select = 
      [[<select class="menu" onChange="this.style.backgroundColor='$colors.background'"
        name="$sfid">]]

    local menu = { replace_dollar(select, {sfid=sfid}) }
    for _, m in ipairs(menu_items) do
      table.insert(menu, menu_item(m))
    end
    table.insert(menu, "</option></select>")

    return table.concat(menu, '\n')
  end
end

-- return an HTML table with statistics
function html_stat_table() -- declared local above
  local verbose = false
  local cstats, errs, rates, gerr = stats(verbose)
  language.stats.bcolor = colors.border --- what a hack!


  local function pct(x)
    return string.format('%5.2f%%', 100 * x)
  end

  local classlines = { }
  local totals = { language.stats.total, 0, 0, 0, 0, pct(1-gerr) }
  do
    local function classline(class) -- information reported for a class
      return { language.class_names[class] or class,
               cstats[class].classifications,
               cstats[class].false_negatives,
               cstats[class].false_positives,
               cstats[class].learnings,
               pct(1-errs[class]),
             }
    end
    for class, s in pairs(cstats) do
      classlines[class] = classline(class)
      totals[2] = totals[2] + s.classifications
      totals[3] = totals[3] + s.false_negatives
      totals[4] = totals[4] + s.false_positives
      totals[5] = totals[5] + s.learnings
    end
  end

  local headers, cols, footers = { }, { }, { }, { }, { }
  local columns = { 'stats', 'num_class', 'false_negatives', 'false_positives', 'learnings', 'accuracy' }
  local widths = {
    stats = 136, num_class = 109, false_negatives = 75, false_positives = 75, learnings = 111, accuracy = 92
  }
  local hclasses = { }
  for class in pairs(cstats) do hclasses[class] = { } end -- html for the class
  for i = 1, #columns do
    local c = columns[i]
    local wtab = {width = widths[c]}
    local text = language.stats[c]
    if c == 'stats' then text = html.i(text) end
    table.insert(headers, html.td (wtab, html.p(html.center(html.b(text)))))
    table.insert(cols,    html.col(wtab))
    for class in pairs(cstats) do
      table.insert(hclasses[class], html.td (wtab, html.p(classlines[class][i])))
    end
    table.insert(footers, html.td (wtab, html.p(totals [i])))
  end
  local function row(l, class)
    return html.tr({class=class, valign="middle", height="25"}, table.concat(l))
  end
  local function linecat(l) return table.concat(l, '\n') end
  local rows = {row(headers, "stats_header")}
  for _, class in ipairs(cfg.classlist()) do
    table.insert(rows, row(hclasses[class], "stats_row"))
  end
  table.insert(rows, row(footers, "stats_footer"))
  local tbl =
    html.table({always="", border=1, bordercolor=colors.border,
                cellpadding=4, cellspacing=0},
               linecat {table.concat(cols), html.tbody(linecat(rows))})
  return html.center(tbl)
end

--=============== END OF MESSAGE SUPPORT =========================

__doc.generate_training_message = [[function(email, temail, [locale]) 
Returns an RFC822-compliant email message.
The message contains a training form and is sent to 'email'.  
When the training form is filled out and posted, the results
are sent to 'temail', which may be omitted and defaults to 'email'.
The optional 'locale' determines the language used in the form.
]]

function generate_training_message(email, temail, opt_locale)
  set_language(opt_locale)
  temail = temail or email

  local ready
  local cstats = stats()
  local min_learnings = 10e100 -- a big number
  do
    local num_classes_with_10_learnings = 0
    for _, s in pairs(cstats) do
      if s.learnings >= 10 then
        min_learnings = math.min(min_learnings, s.learnings)
        num_classes_with_10_learnings = num_classes_with_10_learnings + 1
      end
    end
    ready = num_classes_with_10_learnings >= 2
  end

  if not ready then language.title = language.title_nready end

  -- Experimental - to be moved to a funtion in a better place.
  -- Calculates half the width of reinforcement zone based on
  -- number of learnings. Initial width is larger than the max
  -- possible value (307) and decreases exponentially down.
  -- However if the threshold specified by the user is larger, 
  -- we use that instead (local variable ct below).
  local train_below = 350 / math.sqrt(2*min_learnings+0.1)

  local max_sfids = cfg.cache.report_limit

  -- Adds all learnable sfids in cache and within reinforcement
  -- zone, up to max_sfids.
  local sfids = {}
  local outside_minimum = {}
  for sfid in cache.two_days_sfids() do
    local t = cache.table_of_sfid(sfid)
    if not t.learned and not cache.tag_is_unlearnable(t.tag) then
      if t.confidence < cfg.classes[t.class].train_below then -- should be train_below 
        table.insert(sfids, sfid)
        if #sfids >= max_sfids then
          break
        end
      elseif t.confidence < math.max(train_below, cfg.classes[t.class].train_below) then
        table.insert(outside_minimum, sfid)
      end
    end
  end
  -- If still less than max_sfids, completes with sfids outside
  -- of user reinforcement zone.
  for _, s in ipairs(outside_minimum) do
    if #sfids < max_sfids then
      table.insert(sfids, s)
    else
      break
    end
  end

  cache.sort_sfids(sfids) -- should be redundant (but then should be cheap)
  return(message(sfids, email, temail, ready))
end

__doc.write_training_message = [[function(email, temail, [locale]) 
Writes an RFC822-compliant email message to standard output using
output.write.
The message contains a training form and is sent to 'email'.  
When the training form is filled out and posted, the results
are sent to 'temail', which may be omitted and defaults to 'email'.
The optional 'locale' determines the language used in the form.
]]

function write_training_message(...)
  output.write(generate_training_message(...))
  --- WHY IS THIS NOT output.write_message()???
end
