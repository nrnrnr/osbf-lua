/* fastmime.c -- fast parsing of RFC 2822 messages */

/*

The purpose of this module is to provide fast parsing of RFC 2822
Internet email messages, including MIME messages.  The module is
intended to be integrated with Lua code and to do just about nearly
the minimum needed to make the inner loops fast.  In January of 2008,
I have two motivations for writing it:

  1. Parsing messages appears to be the second most expensive
     operation in OSBF-Lua classification.

  2. My Lua-based MIME parser is embarrassingly complicated.
     (It's also true that scanning is slow, but I attribute this
     slowness almost entirely to the file server; on my twin striped
     SATA disks, Lua scans 221 messages per second with a cold cache,
     256 messages per second with a warm cache, and 270 messages per
     second when writing to /dev/null.  This is fast enough.)

*/

#include <string.h>
#include <sys/types.h>
#include <assert.h>

#include <lua.h>
#include <lauxlib.h>

#define debugf(args) ((void)0)
#define xdebugf(args) printf args

#define WORKAROUND 1 /* try to parse noncompliant messages */

/* precondition: string does not contain a colon */
/* if there is a pointer s with p <= s < lim such that *s is not a valid
   character in an rfc2822 header name, return that pointer; otherwise 
   return NULL */
static unsigned char * find_bad_rfc2822_char(unsigned char *p, unsigned char *lim) {
  for ( ; p < lim; p++)
    if (*p < 33 || *p > 126)
      return p;
  return NULL;
}

/* List of potential line terminators in *headers* *only*.
   Use of pure CR as a line terminator is conflated with 
   mixed use of CR or LF, because both are rare */
enum eol { LF, CRLF, MIXED };

static int parsemime(lua_State *L) {
  /* function(string) returns { headers = list, tags = list, body = string or nil,
                                headerstring = string, workaround = string or nil, 
                                mbox_from = string_or_nil
                                eol = enum, noncompliant = string or nil } 
    N.B. neither mbox_from nor headers[i], if present, contains a terminating eol.
    Presence of an mbox 'From ' line is not sufficient to deem a message noncompliant.
   */
  

  size_t len;
  unsigned char *s = (unsigned char *) luaL_checklstring(L, 1, &len);
  unsigned char *limit = s + len; /* past end of string (sentintel location) */
#define set_sentinel(C) (*limit = (unsigned char) (C))
  unsigned char limitchar = *limit; /* original character in sentinel position */
  unsigned char *start_header;      /* start of the header currently being parsed */
  unsigned char *start_hline;       /* start of the current line of the same header */
  unsigned char *p;                 /* pointer used to scan through headers */
  unsigned n = 1;                   /* next header/tag to write */
  int hindex, tindex;   /* locations (on Lua stack) of headers and tags tables */
  int resindex;         /* location on Lua stack of result table */
  int has_crlf;         /* true iff first occurrence of \n is preceded by \r */
  int has_no_lf;        /* true iff string contains no \n */
  const char *eolname = "this can't happen";  /* string name of eol chosen */
  const char *workaround = NULL;
                            /* if not NULL, identifies compliance workaround used */
  unsigned char *badchar;   /* temporary pointer to bad character in header name */
  int body_present;         /* nonzero if headers end with double EOL */

  /* create tables and put indices in hindex, tindex, resindex */
  lua_newtable(L);
  hindex = lua_gettop(L);
  lua_newtable(L);
  tindex = lua_gettop(L);
  lua_newtable(L);
  resindex = lua_gettop(L);


  /* The basic idea is a state machine with these states:

       start_header of new header -[:]->         header value -[eol]-> end of header line
       end of header line  -[eol]->       start_header of body
       end of header line  -[space]->     header value
       end of header line  -[nonspace]->  start_header of new header
       end of header line  -[eof]->       header-only message
       start_header of body       -[eof]->       parsing complete

    Other transitions indicate a noncompliant message, which is encapsulated.

    The fly in the ointment is that we don't know the end-of-line (eol) convention.
    It may be
       CRLF    \r\n
       LF      \n
       mixed   either \r or \n
    A CR-only eol convention is treated as 'mixed'.

    The state machine is therefore implemented in triplicate, using macros from hell.


    Some observations on noncompliant messages:

       1. Many messages (almost exclusively spam) are noncompliant
          because they are LF or CRLF messages with a CR in the middle of
          a line.  We therefore treat such a CR as an ordinary character.

       2. One particular mailer sends messages that would be compliant
          except a header of the form X-hostname lacks a colon.

       3. Most other noncompliant messages seem to have resulted from bad MTAs
          breaking long lines incorrectly

    We attempt to work around such defects.

  */


  /* set has_crlf and has_nolf by looking for first \n and possible preceding \r */

  set_sentinel('\n');
  p = memchr(s, '\n', len+1);  /* cannot be NULL */
  has_crlf = (p > s && p[-1] == '\r');
  has_no_lf = (p == limit);


  /* start at beginning of string and if necessary handle 'From ...' line from
     sendmail and Unix mbox format */
  p = s;
  debugf(("len == %d && p[4] == '%c' && p[0] == '%c' && !strncmp(...) == %d\n",
          len, p[4], p[0], !strncmp((char *)p, "From ", 5)));
  if (len > 5 && p[4] == ' ' && p[0] == 'F' && !strncmp((char *)p, "From ", 5)) {
    debugf(("Found mbox-style 'From '\n"));
    while (*p != '\r' && *p != '\n') p++;
    lua_pushlstring(L, (char *)s, p-s);
    lua_setfield(L, resindex, "mbox_from");

    /* step past line terminator and go to appropriate start of header */
    if (has_crlf) {
      assert(p[0] == '\r' && p[1] == '\n');
      p += 2;
      debugf(("Starting CRLF after 'From '\n"));
      goto CRLF_start_header;
    } else if (p[0] == '\r') {
      p += 1;
      debugf(("Starting MIXED after 'From '\n"));
      goto MIXED_start_header;
    } else {
      p += 1;
      debugf(("Starting LF after 'From '\n"));
      goto LF_start_header;
    }

  } else {

    /* choose initial state based on earlier determination of eol */
    if (has_crlf) 
      goto CRLF_start_header;
    else if (has_no_lf)
      goto MIXED_start_header;
    else
      goto LF_start_header;

  }
      
  assert(0); /* state-machine definitions below; this code should not fall through */

  /* Definition of state machine, in three flavors:
        EOL == LF
        EOL == CRLF
        EOL == MIXED
     Note that all tests on EOL are evaluated at compile time! 

     Other parameters:
        EOLWIDTH: number of characters in EOL sequence (1 or 2)
        P_NOT_EOL: for LF or CRLF, *p != '\n'; for MIXED, *p != '\n' && *p != '\r'
                   (want it concise because it's in an inner loop)
        POST_EOL_CONDITION: satisfied if p points just past the line terminator
        P_AT_EOL: p points to the line terminator.
     It is *not* the case that P_AT_EOL != P_NOT_EOL always, because
     P_NOT_EOL tests only one character (for speed), where P_AT_EOL tests 2.
  */
    

#define SM(EOL, EOLWIDTH, P_NOT_EOL, POST_EOL_CONDITION, P_AT_EOL)                  \
                                                                                    \
  EOL ## _start_header:                                                             \
    /* p is positioned at the start of a new header */                              \
    debugf(("%s new header at %p: \"%.8s\"...\n", #EOL, p, p));                     \
    assert(p <= limit);                                                             \
    set_sentinel(':');                                                              \
    start_header = start_hline = p;                                                 \
    while (*p != ':') p++;  /* inner loop */                                        \
    if (p == limit) {                                                               \
      lua_pushstring(L, "Missing double end-of-line to terminate headers?");        \
      eolname = #EOL;                                                               \
      goto noncompliant;                                                            \
    } else if ((badchar = find_bad_rfc2822_char(start_header, p)) != NULL) {        \
      /* we found a colon, but a bad character intervened */                        \
      p = badchar;                                                                  \
      if (WORKAROUND && (P_AT_EOL) && start_header[0] == 'X') {                     \
        /* the bad character is a newline, and we treat it as an empty header       \
           whose tag is missing a colon (thanks stanford and mit) */                \
        workaround = "X header tag without colon";                                  \
        p += EOLWIDTH;  /* the noncompliant header disappears */                    \
        goto EOL##_start_header;                                                    \
      }                                                                             \
      /* We can't continue.  Everything up to start_header is                       \
         compliant, but everything from start_header downstream is                  \
         noncompliant.  The only question is what error message to push. */         \
      if (memchr(start_header, '\n', p-start_header))                               \
        lua_pushstring(L, "Missing double end-of-line to terminate headers?");      \
      else {                                                                        \
        lua_pushfstring(L, "Illegal character in RFC 2822 name at offset %d: ",     \
                        start_header - s);                                          \
        lua_pushlstring(L, (char *)start_header, p-start_header);                   \
        lua_concat(L, 2);                                                           \
      }                                                                             \
      eolname = #EOL;                                                               \
      goto noncompliant;                                                            \
    } else {                                                                        \
      /* we found a colon, and the text up to the colon is a valid name */          \
      /* set tag[n] to what has been parsed so far */                               \
      lua_pushlstring(L, (char *) start_header, p-start_header);                    \
      lua_rawseti(L, tindex, n);                                                    \
                                                                                    \
      /* scan to the next line terminator, as determined by P_NOT_EOL */            \
      set_sentinel('\n'); /* OK for CRLF, LF, and mixed */                          \
      while (P_NOT_EOL) p++;                                                        \
      if (p == limit) {                                                             \
        /* keep the final header even though it's not properly terminated */        \
        lua_pushlstring(L, (char *) start_header, p-start_header);                  \
        lua_rawseti(L, hindex, n);                                                  \
        n++;                                                                        \
        eolname = #EOL;                                                             \
        lua_pushstring(L, "Missing final EOL");                                     \
        goto noncompliant;                                                          \
      } else {                                                                      \
        p++;  /* in all 3 cases, makes p point just past the line terminator */     \
        goto EOL##_post_lf; /* find out if the header is continued */               \
      }                                                                             \
    }                                                                               \
                                                                                    \
  EOL ## _post_lf:                                                                  \
    /* p points to the first character following the eol marker                     \
       at the end of a header line */                                               \
    if (!(WORKAROUND && n > 1) && EOL != MIXED &&                                   \
        memchr(start_hline, '\r', p-start_hline-EOLWIDTH)) {                        \
debugf(("Bad hline at %p: \"%.80s\"\n", start_hline, (char *)start_hline));         \
debugf(("Found unwanted \\r at %p (p=%p): \"%.10s\"\n",                             \
memchr(start_hline, '\r', p-start_hline-EOLWIDTH), p,                               \
(char*)memchr(start_hline, '\r', p-start_hline-EOLWIDTH)));                         \
      /* we were expecting LF or CRLF, but there's a CR in the                      \
         middle of the line.  With WORKAROUND and at least 1 good                   \
         header, we ignore the CR and treat like any other character;               \
         otherwise we take this branch, which starts over at the beginning          \
         of the header but changes to the MIXED state. */                           \
      p = start_header;                                                             \
      debugf(("Starting header %p again with eol %s -> MIXED\n", p, #EOL));         \
      goto MIXED_start_header;                                                      \
    } else if ((EOL == CRLF && p[-2] != '\r') || (EOL == LF && p[-2] == '\r')) {    \
      /* if the penultimate character is not as expected, start over as MIXED */    \
      p = start_header;                                                             \
      debugf(("Starting header %p again with eol %s -> MIXED\n", p, #EOL));         \
      goto MIXED_start_header;                                                      \
    }                                                                               \
    /* if we ignored a stray CR above, make a note of it */                         \
    if (WORKAROUND && n > 1 && memchr(start_hline, '\r', p-start_hline-EOLWIDTH))   \
      workaround = "Treated CR as ordinary character";                              \
                                                                                    \
    /* Now we are just past the end of a header line; we need to determine          \
       which of the following four situations obtains:                              \
          - We are at EOL and have just scanned the final header.                   \
          - We've scanned the whole message, which must be a headers-only           \
            message.                                                                \
          - We are at space, in which case we have a continuation of                \
            the current header.                                                     \
          - We are at nonspace, in which case we have finished scanning the         \
            preceding header and must start scanning a new header.                  \
    */                                                                              \
                                                                                    \
    start_hline = p;   /* note start of a new header line */                        \
    /* Now we know there are no eol characters on the preceding line */             \
    assert(p > s && (POST_EOL_CONDITION));                                          \
    assert(p <= limit);                                                             \
    assert(*limit == '\n');                                                         \
    if (P_AT_EOL) { /* test must be safe even if p == limit */                      \
      /* we have found the last of the headers */                                   \
      debugf(("found eol/eol at %p; body is %.20s...\n", p, p+EOLWIDTH));           \
      /* save the last header; scan past the terminating EOL; capture the body */   \
      lua_pushlstring(L, (char *) start_header, p-EOLWIDTH-start_header);           \
      lua_rawseti(L, hindex, n);                                                    \
      p += EOLWIDTH;                                                                \
      body_present = (p <= limit);                                                  \
      if (p > limit) p = limit;                                                     \
      eolname = #EOL;                                                               \
      goto body;                                                                    \
    } else if (p == limit) {                                                        \
      /* end of message: save last header; no body */                               \
      debugf(("message is headers only\n"));                                        \
      lua_pushlstring(L, (char *) start_header, p-EOLWIDTH-start_header);           \
      lua_rawseti(L, hindex, n);                                                    \
      n++;                                                                          \
      body_present = 0;                                                             \
      eolname = #EOL;                                                               \
      goto body;                                                                    \
    } else if (*p == ' ' || *p == '\t') {                                           \
      /* continue this header */                                                    \
      debugf(("%s header starting at %p (%.8s...) is continued at %p (%.8s)\n",     \
             #EOL, start_header, start_header, p, p));                              \
      while (P_NOT_EOL) p++;                                                        \
      if (p == limit) {                                                             \
        /* The header isn't terminated.  Keep it anyway, but note noncompliance */  \
        lua_pushlstring(L, (char *) start_header, p-start_header);                  \
        lua_rawseti(L, hindex, n);                                                  \
        lua_pushstring(L, "EOF reading headers");                                   \
        eolname = #EOL;                                                             \
        goto noncompliant;                                                          \
      } else {                                                                      \
        p++;  /* in all 3 cases, makes p point just past the line terminator */     \
        goto EOL##_post_lf; /* find out if the header is continued */               \
      }                                                                             \
    } else {                                                                        \
      /* start of a new header: save the previous one and continue */               \
      lua_pushlstring(L, (char *) start_header, p-EOLWIDTH-start_header);           \
      lua_rawseti(L, hindex, n);                                                    \
      n++;                                                                          \
      goto EOL##_start_header;                                                      \
    }                                                                               \

  assert(0);  /* unreachable code */

  /* define one state machine for each kind of EOL */

  /*  SM(EOL, EOLWIDTH, P_NOT_EOL, POST_EOL_CONDITION, P_AT_EOL) */

  SM(CRLF,  2, *p != '\n', p[-2] == '\r' && p[-1] == '\n',
                           p[0]  == '\r' && p[1]  == '\n');
  SM(LF,    1, *p != '\n', p[-1] == '\n', *p == '\n');
  SM(MIXED, 1, *p != '\n' && *p != '\r', p[-1] == '\r' || p[-1] == '\n', 
                                         p[0]  == '\r' || p[0]  == '\n');

  assert(0); /* unreachable code */

 body:
  /* we arrive here if all headers are parsed successfully with proper compliance */
  /* p points to the dividing line between header part (for reinforcement)
     and body part.  Body is set only if present */
 finish:
  /* result table is on the stack and p points to the division between
     headerstring and body */
  /* set fields of result, restore sentinel, and return result */
  lua_pushlstring(L, (char *)s, p - s);
  lua_setfield(L, resindex, "headerstring");
  if (body_present) { /* body could be present but empty; this is OK */
    lua_pushlstring(L, (char *) p, limit-p);
    lua_setfield(L, resindex, "body");
  }
  lua_pushvalue(L, hindex);
  lua_setfield(L, resindex, "headers");
  lua_pushvalue(L, tindex);
  lua_setfield(L, resindex, "tags");
  lua_pushstring(L, eolname);
  lua_setfield(L, resindex, "eol");
  if (workaround != NULL) {
    lua_pushstring(L, workaround);
    lua_setfield(L, resindex, "workaround");
  }
  *limit = limitchar; /* restore sentinel */
  lua_settop(L, resindex);
  return 1;
 noncompliant:
  /* we arrive here if we tripped over a noncompliant message.
     start_header points to the dividing line between compliant headers
     and something noncompliant.  A string indicating the reason for noncompliance
     is on the Lua stack. */
  lua_setfield(L, resindex, "noncompliant");
  p = start_header; /* do this to share code with finish: */
  goto finish;
}

static const luaL_Reg lib[] = {
  {"parse", parsemime},
  {NULL, NULL}
};

extern int luaopen_fastmime (lua_State *L);
extern int luaopen_fastmime (lua_State *L) {
  luaL_register(L, luaL_checkstring(L, -1), lib);
  return 1;
}

