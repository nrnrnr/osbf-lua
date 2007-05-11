-- Command for creating a training-form email

local require, print, pairs, ipairs, type, assert, setmetatable =
      require, print, pairs, ipairs, type, assert, setmetatable

local os, string, table =
      os, string, table

local modname = ...
local modname = string.gsub(modname, '[^%.]+$', 'commands')
module(modname)

__doc = __doc or { }

local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local msg   = require(_PACKAGE .. 'msg')
local core  = require(_PACKAGE .. 'core')
local cache = require(_PACKAGE .. 'cache')


local html = util.html

----------------------------------------------------------------
---- Color and template support

local colors = {
  background = '#ffec8b',
  menubg = '#acac7c',
  border = '#3d0000',
  spam = "#ff0000",
  ham = "#0000aa",
  default = "#000000",
  invalid = "#ff0000", -- color for an invalid date
}

local function replace_dollar(s, t)
  s = string.gsub(s, '%$colors%.([%a_]+)', colors)
  return (string.gsub(s, '%$([%a_]+)', t))
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
            Select the proper training actino for each message
            and click "$send_actions"]],
  actions = {
    none        = "None",
    recover     = "Recover message",
    remove      = "Remove from cache",
    whitelist_from     = "Add 'From:' to whitelist",
    whitelist_subject = "Add 'Subject:' to whitelist",
    ham  = "Train as Ham",
    spam = "Train as Spam",
    undo = "Undo training",
  },
  train_nomsgs  = "No messages for training",
  table = 
    { date  = "Date", from = "From", subject = "Subject", action = "Action" },

  stats = {
    stats     = "Statistics",
    num_class = "Classifications",
    mistakes  = "Mistakes",
    learnings = "Learnings",
    accuracy  = "Accuracy",
    spam      = "Spam",
    non_spam  = "Ham",
    total     = "Total",
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
    recover     = "Recuperar mensagem",
    remove      = "Remover do cache",
    whitelist_from    = "P&ocirc;r remetente em whitelist",
    whitelist_subject = "P&ocirc;r 'Assunto:' em whitelist",
    ham  = "Treinar como N&atilde;o-Spam",
    spam = "Treinar como Spam",
    undo = "Desfazer treinamento",
  },
  train_nomsgs  = "N&atilde;o h&aacute; mensagens para treinamento",
  table = { date  = "Data", from = "De", subject = "Assunto",
            action = "A&ccedil;&atilde;o" },

  stats = {
    stats     = "Estat&iacute;sticas",
    num_class = "Classifica&ccedil;&otilde;es",
    mistakes  = "Erros",
    learnings = "Treinamentos",
    accuracy  = "Precis&atilde;o",
    spam      = "Spam",
    non_spam  = "N&atilde;o Spam",
    total     = "Total",
  },
}

local languages = { en_us = English, pt_br = Brazilian_Portuguese, posix = English }

----- set language according to locale
local language = languages.posix
for l in string.gmatch(os.getenv 'LANGUAGE' or '', '[^:]+') do
  local lang = languages[string.lower(l)]
  if lang then
    language = lang
    break
  end
end

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

----------------------------------------------------------------
---- combined support for color and localization

local function localize(x)
  if type(x) == 'string' then
    return replace_dollar(s, language)
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

local function message(sfids, email, temail)
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
----=-=-=-train-report-boundary-=-=-=
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
     "<center>$train_nomsgs</center><p>
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
    sfid_rows = html_sfid_rows(sfids),
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

local max_widths = { date = 18, from = 23, subject = 45, action = 14 }

-- template for row of the sfid table (one per message)
local sfid_row = [[
<tr class="msgs">
 <td style="width: 15%; max-width: $mwd%; color: $datecolor;"><small>$date</small></td>
 <td style="width: 26%; max-width: $mwf%; color: $fgcolor;"><small>$from</small></td>
 <td style="width: 45%; max-width: $mws%; color: $fgcolor;">
                                                         <small>$subject</small></td>
 <td style="width: 14%; max-width: $mwa%; vertical-align: middle; color: $fgcolor;">
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

  local cols = { }
  for _, what in ipairs { 'date', 'from', 'subject', 'action' } do
    local data = { mw = max_widths[what], contents = language.table[what] }
    table.insert(cols, replace_dollar(col, data))
  end
  html_first_row = html.tr(table.concat(cols, '\n'))
end

local sfid_menu --- defined below

function html_sfid_rows(sfids) -- declared local above

  -- for case insensitive match - from PIL
  local function nocase (s)
    return string.gsub(s, "%a", function (c)
          return string.format("[%s%s]", string.lower(c),
                                         string.upper(c))
        end)
  end
  local tag_colors =
    { S = colors.spam, H = colors.ham, ['-'] = colors.spam, ['+'] = colors.ham }

  rows = { html_first_row }
  for _, sfid in ipairs(sfids) do
    local m, status = msg.of_sfid(sfid)
    util.validate(m, 'Sudden disappearance of sfid from the cache')
    local function header(tag)
      return msg.header_tagged(m, tag) or string.format('(no %s)', tag)
    end
    local function htmlify(s, n)
      -- strip RFC2822 quotation and do something very strange with comments
      s = string.gsub(s, "=%?[Ii][Ss][Oo]%-8859%-1%?[Qq]%?(.-)%?=", "%1")
      s = string.gsub(s, "(" .. string.rep("%S", n) ..")(%S)", "%1 %2")
      s = html.of_ascii(s)
      return s
    end

    local subject, from, date  = header 'subject', header 'from', header 'date'
    from, subject = htmlify(from, 32), htmlify(subject, 40)

    local tag       = string.match(sfid, "sfid%-(.)") or '?'
    local fgcolor   = ready and tag_colors[tag] or colors.default
    local lts       = msg.rfc2822_to_localtime(date) 
    local date      = lts and os.date("%Y/%m/%d %H:%M", lts) or date
    local datecolor = lts and fgcolor or colors.invalid

    local data = {
      datecolor = datecolor, fgcolor = fgcolor,
      from = from, subject = subject, date = date,
      select = sfid_menu(sfid, tag, ready)
    }

    table.insert(rows, replace_dollar(sfid_row, data))
  end

  return table.concat(rows)
end

do
  local default_selections = { ['-'] = 'spam', S = spam, ['+'] = ham, H = ham }

  local menu_items = { -- menu possibilities per each message
    "none", "recover", "remove", "whitelist_from", "whitelist_subject", 
    "spam", "ham", "undo",
  }

  function sfid_menu(sfid, tag, ready) -- declared local above
    local selected = { }
    selected[default_selections[tag] or 'none'] = true

    local function menu_item(choice)
      return string.format([[<option class="menu" value="%s"%s>%s]],
                           choice, selected[choice] and ' selected' or '',
                           language[choice] or ('(Nothing for ' .. choice .. '?!)'))
    end

    local select = 
      [[<select class="menu" onChange="this.style.backgroundColor='$colors.background'
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
  local hstats, sstats, herr, serr, spam_rate, gerr = stats()
  local stats = language.stats
  stats.bcolor = colors.border --- what a hack!

  local columns = { 'stats', 'num_class', 'mistakes', 'learnings', 'accuracy' }
  local widths = {
    stats = 136, num_class = 109, mistakes = 75, learnings = 111, accuracy = 92
  }

  local function pct(x)
    return string.format('%4.1f%%', 100 * x)
  end

  local hams   = {stats.ham, hstats.classifications, hstats.mistakes,
                  hstats.learnings, pct(1-herr)}
  local spams  = {stats.spam, sstats.classifications, sstats.mistakes,
                  sstats.learnings, pct(1-serr)}
  local totals = {stats.total, hstats.classifications + sstats.classifications,
                   hstats.learnings+sstats.learnings, pct(1-gerr)}

  local headers, cols, hspams, hhams, footers = { }, { }, { }, { }, { }
  for i = 1, #columns do
    local c = columns[i]
    local wtab = {width = widths[c]}
    local text = language.stats[c]
    if c == 'stats' then text = html.i(text) end
    table.insert(headers, html.td (wtab, html.p(html.b(text))))
    table.insert(cols,    html.col(wtab))
    table.insert(hspams,  html.td (wtab, html.p(spams[i])))
    table.insert(hhams,   html.td (wtab, html.p(hams [i])))
    table.insert(footers, html.td (wtab, html.p(hams [i])))
  end
  local header = html.tr({class="stats_header", height="25", valign="middle"},
                         table.concat(headers, '\n'))
  local function row(l)
    return html.tr({class="stats_row", valign="MIDDLE", height="25"}, table.concat(l))
  end
  local function linecat(l) return table.concat(l, '\n') end
  local tbl =
    html.table({always="", border=1, bordercolor=colors.border,
                cellpadding=4, cellspacing=0},
              linecat {table.concat(cols),
                html.tbody(linecat {row(hspams), row(hhams), row(footers)})})
  return html.center(tbl)
end

--=============== END OF MESSAGE SUPPORT =========================

__doc.write_training_message = [[function(outfile, email, temail) 
Writes an RFC822-compliant email message on 'outfile'.
The message contains a training form and is sent to 'email'.  
When the training form is filled out and posted, the results
are sent to 'temail', which may be omitted and defaults to 'email'.]]

function write_training_message(outfile, email, temail)
  temail = temail or email

  local hstats, sstats = stats()
  local ready = hstats.learnings >= 10 and sstats.learnings >= 10

  if not ready then language.title = language.title_nready end

  local sfids = {}

  local max_sfids = cfg.cache_report_limit

  local function add_sfids_matching(pat)
    for sfid in cache.two_days_sfids() do
      if string.find(sfid, pat) then
        table.insert(sfids, sfid)
        if #sfids >= max_sfids then
          return
        end
      end
    end
  end

  add_sfids_matching("sfid%-[-+].+[^-][^sh]$") 
  add_sfids_matching("sfid%-[^BW]-[-+]0[01].[%.,]..%-%d-@.+[^-][^sh]$") 

  outfile:write(message(sfids, email, temail))
end