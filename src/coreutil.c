/*
 * core utilities for OSBF-Lua
 *
 * See Copyright Notice in osbflib.h
 *
 */

#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <inttypes.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"

#define QUOTEQUOTE(s) #s
#define QUOTE(s) QUOTEQUOTE(s)

#define DIR_METANAME   QUOTE(OSBF_MODNAME)".dir"

/****************************************************************/

#define MAX_DIR_SIZE 256

static int
lua_osbf_changedir (lua_State * L)
{
  const char *newdir = luaL_checkstring (L, 1);

  if (chdir (newdir) != 0)
    {
      return 0;
    }
  else
    {
      return luaL_error (L, "can't change dir to '%s'\n", newdir);
    }
}

/**********************************************************/
/* Test to see if path is a directory */
static int
l_is_dir(lua_State *L)
{
	struct stat s;
	const char *path=luaL_checkstring(L, 1);
	if (stat(path,&s)==-1)
          lua_pushboolean(L, 0);
        else
          lua_pushboolean(L, S_ISDIR(s.st_mode));
        return 1;
}


/**********************************************************/

static int
lua_osbf_getdir (lua_State * L)
{
  char cur_dir[MAX_DIR_SIZE + 1];

  if (getcwd (cur_dir, MAX_DIR_SIZE) != NULL)
    {
      lua_pushstring (L, cur_dir);
      return 1;
    }
  else
    {
      return luaL_error(L, "%s","can't get current dir");
    }
}

/**********************************************************/
/* Directory Iterator - from the PIL book */

/* forward declaration for the iterator function */
static int dir_iter (lua_State * L);

static int
l_dir (lua_State * L)
{
  const char *path = luaL_checkstring (L, 1);

  /* create a userdatum to store a DIR address */
  DIR **d = (DIR **) lua_newuserdata (L, sizeof (DIR *));

  /* set its metatable */
  luaL_getmetatable (L, DIR_METANAME);
  lua_setmetatable (L, -2);

  /* try to open the given directory */
  *d = opendir (path);
  if (*d == NULL)		/* error opening the directory? */
    luaL_error (L, "cannot open %s: %s", path, strerror (errno));

  /* creates and returns the iterator function
     (its sole upvalue, the directory userdatum,
     is already on the stack top */
  lua_pushcclosure (L, dir_iter, 1);
  return 1;
}

static int
dir_iter (lua_State * L)
{
  DIR *d = *(DIR **) lua_touserdata (L, lua_upvalueindex (1));
  struct dirent *entry;
  if ((entry = readdir (d)) != NULL)
    {
      lua_pushstring (L, entry->d_name);
      return 1;
    }
  else
    return 0;			/* no more values to return */
}

static int
dir_gc (lua_State * L)
{
  DIR *d = *(DIR **) lua_touserdata (L, 1);
  if (d)
    closedir (d);
  return 0;
}
/**********************************************************/

/* 32-bit Cyclic Redundancy Code  implemented by A. Appel 1986  
 
   this works only if POLY is a prime polynomial in the field
   of integers modulo 2, of order 32.  Since the representation of this
   won't fit in a 32-bit word, the high-order bit is implicit.
   IT MUST ALSO BE THE CASE that the coefficients of orders 31 down to 25
   are zero.  Fortunately, we have a candidate, from
	E. J. Watson, "Primitive Polynomials (Mod 2)", Math. Comp 16 (1962).
   It is:  x^32 + x^7 + x^5 + x^3 + x^2 + x^1 + x^0

   Now we reverse the bits to get:
	111101010000000000000000000000001  in binary  (but drop the last 1)
           f   5   0   0   0   0   0   0  in hex
*/

#define POLY 0xf5000000

static uint32_t crc_table[256];

static void init_crc(void) {
  int i, j, sum;
  for (i=0; i<256; i++) {
    sum=0;
    for(j = 8-1; j>=0; j=j-1)
      if (i&(1<<j)) sum ^= ((uint32_t)POLY)>>j;
    crc_table[i]=sum;
  }
}

static int lua_crc32(lua_State *L) {
  size_t n;
  const unsigned char *s = (const unsigned char *)luaL_checklstring(L, 1, &n);
  uint32_t sum = 0;
  while (n-- > 0) {
    sum = (sum>>8) ^ crc_table[(sum^(*s++))&0xff];
  }
  lua_pushnumber(L, (lua_Number) sum);
  return 1;
}


/**********************************************************/
/*
* lbase64.c
* base64 encoding and decoding for Lua 5.1
* Luiz Henrique de Figueiredo <lhf@tecgraf.puc-rio.br>
* 27 Jun 2007 19:04:40
* Code in the public domain.
*/

static const char b64code[]=
"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void b64encode(luaL_Buffer *b, unsigned char c1, unsigned char c2, unsigned char c3, int n)
{
 uint32_t tuple=c3+256UL*(c2+256UL*c1);
 int i;
 char s[4];
 for (i=0; i<4; i++) {
  s[3-i] = b64code[tuple % 64];
  tuple /= 64;
 }
 for (i=n+1; i<4; i++) s[i]='=';
 luaL_addlstring(b,s,4);
}

static int lua_b64encode(lua_State *L)		/** encode(s) */
{
 size_t l;
 const unsigned char *s=(const unsigned char*)luaL_checklstring(L,1,&l);
 luaL_Buffer b;
 int n;
 luaL_buffinit(L,&b);
 for (n=l/3; n--; s+=3) b64encode(&b,s[0],s[1],s[2],3);
 switch (l%3)
 {
  case 1: b64encode(&b,s[0],0,0,1);		break;
  case 2: b64encode(&b,s[0],s[1],0,2);		break;
 }
 luaL_pushresult(&b);
 return 1;
}

static void b64decode(luaL_Buffer *b, int c1, int c2, int c3, int c4, int n)
{
 uint32_t tuple=c4+64L*(c3+64L*(c2+64L*c1));
 char s[3];
 switch (--n)
 {
  case 3:     s[2]=tuple;          goto c2;
  case 2: c2: s[1]=tuple >> 8;     goto c1;
  case 1: c1: s[0]=tuple >> 16;
 }
 luaL_addlstring(b,s,n);
}

static int lua_b64decode(lua_State *L)		/** b64decode(s) */
{
 size_t l;
 const char *s=luaL_checklstring(L,1,&l);
 luaL_Buffer b;
 int n=0;
 char t[4];
 luaL_buffinit(L,&b);
 for (;;)
 {
  int c=*s++;
  switch (c)
  {
   const char *p;
   default:
    p=strchr(b64code,c);
    if (p==NULL)
      luaL_error(L, "Invalid character '%c' in base64-encoded string", c);
    t[n++]= p-b64code;
    if (n==4)
    {
     b64decode(&b,t[0],t[1],t[2],t[3],4);
     n=0;
    }
    break;
   case '=':
    switch (n)
    {
     case 1: b64decode(&b,t[0],0,0,0,1);		break;
     case 2: b64decode(&b,t[0],t[1],0,0,2);	break;
     case 3: b64decode(&b,t[0],t[1],t[2],0,3);	break;
    }
    goto c0;
   case 0: c0:
    luaL_pushresult(&b);
    return 1;
   case '\n': case '\r': case '\t': case ' ': case '\f': case '\b':
    break;
  }
 }
 return luaL_error(L, "This statement can't be reached");
}

/**********************************************************/

/* RFC3629 - UTF-8, a transformation format of ISO 10646
 * 
 *   Char. number range  |        UTF-8 octet sequence
 *      (hexadecimal)    |              (binary)
 *   --------------------+-------------------------------------
 *   0000 0000-0000 007F | 0xxxxxxx
 *   0000 0080-0000 07FF | 110xxxxx 10xxxxxx
 *   0000 0800-0000 FFFF | 1110xxxx 10xxxxxx 10xxxxxx
 *   0001 0000-0010 FFFF | 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
 */

#define HTML_BUFFER_SIZE 2048
static int lua_utf8tohtml(lua_State *L)
{
 size_t l;
 const char *s=luaL_checklstring(L,1,&l);
 const char *max_s = s + l;
 luaL_Buffer b;
 char buffer[HTML_BUFFER_SIZE+20] = {'\0'};
 char *p = buffer;
 char *max_p = p + HTML_BUFFER_SIZE;
 uint32_t c;
 unsigned len, i;
 uint32_t min_values[] = {0x00, 0x100, 0x080, 0x0800, 0x010000};
 uint32_t max_value = 0x10FFFF;

 luaL_buffinit(L,&b);
 while ((c=*s)) {
   for (len=0; c & 0x80; len++)
     c = c << 1;
   if (len == 1 || len > 4) { /* max bytes of UTF-8 encoded char */
     sprintf(buffer, "%02X", (unsigned char)*s);
     luaL_error(L, "Invalid first byte '0x%s' in UTF-8 char", buffer);
   } else if (s+len > max_s) {
     sprintf(buffer, "%02X", (unsigned char)*s);
     luaL_error(L, "Incomplete UTF-8 char: '0x%s'", buffer);
   }
   c = (c & 0xFF) >> len; /* valid bits back to original position */
   for (s++, i=len; i>1; i--, s++) {
     if ((*s & 0xC0) == 0x80)
       c = (c<<6) | (*s & 0x3F);
     else {
       sprintf(buffer, "%02X", (unsigned char)*s);
       luaL_error(L, "Invalid byte '0x%s' in UTF-8 char", buffer);
     }
   }
   if (c < min_values[len])
     luaL_error(L, "Overlong UTF-8 form: value %d in %d bytes", c, len);
   else if (c > max_value)
     luaL_error(L, "Code point out of UTF-8 range: %f", c);
   /* reserved for surrogate pairs in UTF-16 */
   if (c >= 0xD800 && c <= 0xDFFF) {
     sprintf(buffer, "%4X", c);
     luaL_error(L, "Surrogate pairs are not allowed in UTF-8: U+%s", buffer);
   }

   if (c < 0x7F && c >= ' ') {
     switch (c) {
       case '<':
         strcpy(p, "&lt;");
         break;
       case '>':
         strcpy(p, "&gt;");
         break;
       case '"':
         strcpy(p, "&quot;");
         break;
       case '&':
         strcpy(p, "&amp;");
         break;
       default:
         *p = c;
         break;
     }
   } else
     sprintf(p, "&#%d;", c);
   while (*++p);
   if (p >= max_p) {
     luaL_addstring(&b, buffer);
     buffer[0] = '\0';
     p = buffer;
   }
 }
 luaL_addstring(&b, buffer);
 luaL_pushresult(&b);
 return 1;
}

/**********************************************************/

static int lua_unsigned2string(lua_State *L) {
  uint32_t n = luaL_checkint(L, 1);
  unsigned char buf[4];
  int i;
  for (i = 0; i < 4; i++) buf[i] = (n >> 8*i) & 0xff;
  lua_pushlstring(L, (const char *) buf, 4);
  return 1;
}

/**********************************************************/


/************************ MD5 code from Marcela Ozorio Suarez, Roberto I ****/
#include <string.h>

#define WORD 32
#define MASK 0xFFFFFFFF
typedef uint32_t WORD32;


/**
*  md5 hash function.
*  @param message: aribtary string.
*  @param len: message length.
*  @param output: buffer to receive the hash value. Its size must be
*  (at least) HASHSIZE.
*/
static void md5 (const char *message, long len, char *output);



/*
** Realiza a rotacao no sentido horario dos bits da variavel 'D' do tipo WORD32.
** Os bits sao deslocados de 'num' posicoes
*/
#define rotate(D, num)  (D<<num) | (D>>(WORD-num))

/*Macros que definem operacoes relizadas pelo algoritmo  md5 */
#define F(x, y, z) (((x) & (y)) | ((~(x)) & (z)))
#define G(x, y, z) (((x) & (z)) | ((y) & (~(z))))
#define H(x, y, z) ((x) ^ (y) ^ (z))
#define I(x, y, z) ((y) ^ ((x) | (~(z))))


/*vetor de numeros utilizados pelo algoritmo md5 para embaralhar bits */
static const WORD32 T[64]={
                     0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
                     0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
                     0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
                     0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
                     0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
                     0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
                     0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
                     0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
                     0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
                     0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
                     0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
                     0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
                     0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
                     0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
                     0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
                     0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
};


static void word32tobytes (const WORD32 *input, char *output) {
  int j = 0;
  while (j<4*4) {
    WORD32 v = *input++;
    output[j++] = (char)(v & 0xff); v >>= 8;
    output[j++] = (char)(v & 0xff); v >>= 8;
    output[j++] = (char)(v & 0xff); v >>= 8;
    output[j++] = (char)(v & 0xff);
  }
}


static void inic_digest(WORD32 *d) {
  d[0] = 0x67452301;
  d[1] = 0xEFCDAB89;
  d[2] = 0x98BADCFE;
  d[3] = 0x10325476;
}


/*funcao que implemeta os quatro passos principais do algoritmo MD5 */
static void digest(const WORD32 *m, WORD32 *d) {
  int j;
  /*MD5 PASSO1 */
  for (j=0; j<4*4; j+=4) {
    d[0] = d[0]+ F(d[1], d[2], d[3])+ m[j] + T[j];       d[0]=rotate(d[0], 7);
    d[0]+=d[1];
    d[3] = d[3]+ F(d[0], d[1], d[2])+ m[(j)+1] + T[j+1]; d[3]=rotate(d[3], 12);
    d[3]+=d[0];
    d[2] = d[2]+ F(d[3], d[0], d[1])+ m[(j)+2] + T[j+2]; d[2]=rotate(d[2], 17);
    d[2]+=d[3];
    d[1] = d[1]+ F(d[2], d[3], d[0])+ m[(j)+3] + T[j+3]; d[1]=rotate(d[1], 22);
    d[1]+=d[2];
  }
  /*MD5 PASSO2 */
  for (j=0; j<4*4; j+=4) {
    d[0] = d[0]+ G(d[1], d[2], d[3])+ m[(5*j+1)&0x0f] + T[(j-1)+17];
    d[0] = rotate(d[0],5);
    d[0]+=d[1];
    d[3] = d[3]+ G(d[0], d[1], d[2])+ m[((5*(j+1)+1)&0x0f)] + T[(j+0)+17];
    d[3] = rotate(d[3], 9);
    d[3]+=d[0];
    d[2] = d[2]+ G(d[3], d[0], d[1])+ m[((5*(j+2)+1)&0x0f)] + T[(j+1)+17];
    d[2] = rotate(d[2], 14);
    d[2]+=d[3];
    d[1] = d[1]+ G(d[2], d[3], d[0])+ m[((5*(j+3)+1)&0x0f)] + T[(j+2)+17];
    d[1] = rotate(d[1], 20);
    d[1]+=d[2];
  }
  /*MD5 PASSO3 */
  for (j=0; j<4*4; j+=4) {
    d[0] = d[0]+ H(d[1], d[2], d[3])+ m[(3*j+5)&0x0f] + T[(j-1)+33];
    d[0] = rotate(d[0], 4);
    d[0]+=d[1];
    d[3] = d[3]+ H(d[0], d[1], d[2])+ m[(3*(j+1)+5)&0x0f] + T[(j+0)+33];
    d[3] = rotate(d[3], 11);
    d[3]+=d[0];
    d[2] = d[2]+ H(d[3], d[0], d[1])+ m[(3*(j+2)+5)&0x0f] + T[(j+1)+33];
    d[2] = rotate(d[2], 16);
    d[2]+=d[3];
    d[1] = d[1]+ H(d[2], d[3], d[0])+ m[(3*(j+3)+5)&0x0f] + T[(j+2)+33];
    d[1] = rotate(d[1], 23);
    d[1]+=d[2];
  }
  /*MD5 PASSO4 */
  for (j=0; j<4*4; j+=4) {
    d[0] = d[0]+ I(d[1], d[2], d[3])+ m[(7*j)&0x0f] + T[(j-1)+49];
    d[0] = rotate(d[0], 6);
    d[0]+=d[1];
    d[3] = d[3]+ I(d[0], d[1], d[2])+ m[(7*(j+1))&0x0f] + T[(j+0)+49];
    d[3] = rotate(d[3], 10);
    d[3]+=d[0];
    d[2] = d[2]+ I(d[3], d[0], d[1])+ m[(7*(j+2))&0x0f] + T[(j+1)+49];
    d[2] = rotate(d[2], 15);
    d[2]+=d[3];
    d[1] = d[1]+ I(d[2], d[3], d[0])+ m[(7*(j+3))&0x0f] + T[(j+2)+49];
    d[1] = rotate(d[1], 21);
    d[1]+=d[2];
  }
}


static void bytestoword32 (WORD32 *x, const char *pt) {
  int i;
  for (i=0; i<16; i++) {
    int j=i*4;
    x[i] = (((WORD32)(unsigned char)pt[j+3] << 8 |
           (WORD32)(unsigned char)pt[j+2]) << 8 |
           (WORD32)(unsigned char)pt[j+1]) << 8 |
           (WORD32)(unsigned char)pt[j];
  }

}


static void put_length(WORD32 *x, long len) {
  /* in bits! */
  x[14] = (WORD32)((len<<3) & MASK);
  x[15] = (WORD32)(len>>(32-3) & 0x7);
}


/*
** returned status:
*  0 - normal message (full 64 bytes)
*  1 - enough room for 0x80, but not for message length (two 4-byte words)
*  2 - enough room for 0x80 plus message length (at least 9 bytes free)
*/
static int converte (WORD32 *x, const char *pt, int num, int old_status) {
  int new_status = 0;
  char buff[64];
  if (num<64) {
    memcpy(buff, pt, num);  /* to avoid changing original string */
    memset(buff+num, 0, 64-num);
    if (old_status == 0)
      buff[num] = '\200';
    new_status = 1;
    pt = buff;
  }
  bytestoword32(x, pt);
  if (num <= (64 - 9))
    new_status = 2;
  return new_status;
}



static void md5 (const char *message, long len, char *output) {
  WORD32 d[4];
  int status = 0;
  long i = 0;
  inic_digest(d);
  while (status != 2) {
    WORD32 d_old[4];
    WORD32 wbuff[16];
    int numbytes = (len-i >= 64) ? 64 : len-i;
    /*salva os valores do vetor digest*/
    d_old[0]=d[0]; d_old[1]=d[1]; d_old[2]=d[2]; d_old[3]=d[3];
    status = converte(wbuff, message+i, numbytes, status);
    if (status == 2) put_length(wbuff, len);
    digest(wbuff, d);
    d[0]+=d_old[0]; d[1]+=d_old[1]; d[2]+=d_old[2]; d[3]+=d_old[3];
    i += numbytes;
  }
  word32tobytes(d, output);
}

/**
*  Hash function. Returns a hash for a given string.
*  @param message: arbitrary binary string.
*  @return  A 128-bit hash string.
*/
static int lmd5 (lua_State *L) {
  char buff[16];
  size_t l;
  const char *message = luaL_checklstring(L, 1, &l);
  md5(message, l, buff);
  lua_pushlstring(L, buff, 16L);
  return 1;
}

const struct luaL_reg osbf_lua_utils[] = {
  {"getdir", lua_osbf_getdir},
  {"chdir", lua_osbf_changedir},
  {"dir", l_dir},
  {"isdir", l_is_dir},
  {"crc32", lua_crc32},
  {"b64encode", lua_b64encode},
  {"b64decode", lua_b64decode},
  {"unsigned2string", lua_unsigned2string},
  {"utf8tohtml", lua_utf8tohtml},
  {"md5sum", lmd5},
  {NULL, NULL}
};

void init_core_util(lua_State *L) {
  init_crc();

  /* Open dir function */
  luaL_newmetatable (L, DIR_METANAME);
  lua_pushcfunction (L, dir_gc);
  lua_setfield (L, -2, "__gc");
  lua_pop(L, 1);

}
