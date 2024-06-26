#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ(2.61)
AC_INIT([OSBF-Lua], [3.0.0])
AM_INIT_AUTOMAKE

MOD_NAME=osbf3
AC_ARG_ENABLE(osbf-name,
  AC_HELP_STRING([[--enable-osbf-name=[[[[NAME]]]]]],
    [set the module name - default=osbf3]),
  [MOD_NAME=$enableval],
  [MOD_NAME=$MOD_NAME])

MOD_VERSION=3.0.0

dnl lib version info for libtool
dnl for the linker to understand which versions the library are compatible with
dnl each other we must keep a separate library version cout of the format c:r:a.
dnl - if only implementation changed but all interfaces are kept, do r++
dnl - if only functionality was added do c++,r=0,a++
dnl - if any functionality was removed do c++,r=0,a=0.
dnl
dnl see http://sourceware.org/autobook/autobook/autobook_91.html
dnl 
LIB_VERSION=3:0:0

AC_SUBST(MOD_NAME)
AC_SUBST(MOD_VERSION)
AC_SUBST(LIB_VERSION)

AC_CONFIG_SRCDIR([osbf_disk.h])
AC_CONFIG_HEADER([config.h])


# Checks for programs.
AC_PROG_CPP
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_LN_S
AC_PROG_MAKE_SET
AC_CHECK_PROGS(PKGCONFIG,[pkg-config],no)

AC_DISABLE_STATIC
AC_PROG_LIBTOOL

# Checks for libraries.
AC_CHECK_LIB([m], [floor])

# Checks for header files.
AC_HEADER_DIRENT
AC_HEADER_STDC
#AC_CHECK_HEADERS([fcntl.h float.h inttypes.h stddef.h stdlib.h string.h unistd.h])
AC_CHECK_HEADERS([float.h inttypes.h stddef.h stdlib.h string.h unistd.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_C_CONST
AC_TYPE_INT32_T
AC_TYPE_OFF_T
AC_TYPE_SIZE_T
AC_TYPE_UINT32_T
AC_TYPE_UINT64_T

# Checks for library functions.
AC_FUNC_CLOSEDIR_VOID
AC_FUNC_MALLOC
AC_FUNC_MMAP
AC_FUNC_REALLOC
AC_TYPE_SIGNAL
AC_FUNC_STAT
AC_CHECK_FUNCS([floor getcwd memchr memmove memset munmap pow strchr strerror strstr])


test "$prefix" = "NONE" && prefix=$ac_default_prefix

dnl Check for Lua.
AC_PATH_PROGS(LUA, lua lua5.1, no)

COMP_LUA=
if test "$LUA" = "no"; then
  AC_MSG_ERROR([You need Lua 5.1 or superior installed before running configure.])
fi

AC_MSG_CHECKING(for lua >= 5.1)
read LUA_MAJOR LUA_MINOR LUA_POINT <<LUA_EOF
  $($LUA -v 2>&1 | cut -f2 -d' ' | sed -e 's/\./ /g')
LUA_EOF
if test 0$LUA_MAJOR -lt 5 -o 0$LUA_MAJOR -eq 5 -a  0$LUA_MAJOR -eq 0; then
  AC_MSG_RESULT([no, version found is $LUA_MAJOR.$LUA_MINOR])
else
  AC_MSG_RESULT([$LUA_MAJOR.$LUA_MINOR found])
  lua_vdot=$LUA_MAJOR.$LUA_MINOR
  lua_vndot=$LUA_MAJOR$LUA_MINOR
  lua_version=$LUA_MAJOR.$LUA_MINOR.$LUA_POINT
  AC_CHECK_HEADERS(lua$lua_vndot/lua.h,
    [AC_CHECK_HEADERS(lua$lua_vndot/lualib.h,
      [AC_CHECK_HEADER(lua$lua_vndot/lauxlib.h,
        [lua_headerdir=lua$lua_vndot],
        [])],
      [])],
    [AC_CHECK_HEADERS(lua$lua_vdot/lua.h,
      [AC_CHECK_HEADERS(lua$lua_vdot/lualib.h,
        [AC_CHECK_HEADER(lua$lua_vdot/lauxlib.h,
          [lua_headerdir=lua$lua_vdot],
          [])],
        [])],
      [AC_CHECK_HEADERS(lua.h,
        [AC_CHECK_HEADERS(lualib.h,
          [AC_CHECK_HEADER(lauxlib.h,
            [lua_headerdir=""],
            [lua_headerdir="no"])],
          [])],
        [])])])

  if test "$lua_headerdir" = "no"; then
    AC_MSG_ERROR([Lua headers lua.h, lualib.h and lualib.h not found. Please install the -dev packages for Lua $lua_vdot])
  else
    COMP_LUA=lua
  fi

  if test "$COMP_LUA" != "lua"; then
    AC_MSG_ERROR([Lua $lua_vdot found but not lua.h, lualib.h and lauxlib.h! Please install the -dev packages for Lua $lua_vdot])
  else
    # OK, headers found, let's check the libraries (LIBS is not used)
    LIBS=
    lua_havelib=no
    LUA_HAVE_COMPAT51=DONT_HAVE_COMPAT51
    AC_SEARCH_LIBS(lua_call, lua$lua_vdot lua$lua_vndot lua,
      [AC_SEARCH_LIBS(luaL_register, lua$lua_vdot lua$lua_vndot lua,
        [lua_havelib=LUA$lua_vndot],
        [AC_SEARCH_LIBS(luaL_module, lualib$lua_vndot lualib$lua_vdot lualib,
          [lua_havelib=$lua_vndot; $LUA -l compat-5.1 2>/dev/null;
           test "$?" = "0" && LUA_HAVE_COMPAT51=HAVE_COMPAT51],
          [AC_SEARCH_LIBS(luaL_openlib, lualib$lua_vdot lualib$lua_vndot lualib,
            [lua_havelib=$lua_vndot],
            [COMP_LUA=], [-lm])], [-lm])], [-lm])],
      [COMP_LUA=], [-lm])
    lua_libs=$LIBS
    LIBS=

    # Options to pass when configuring Lua module
    if test  "$lua_havelib" = "no"; then
      AC_MSG_ERROR([Lua headers found but not the libraries! Please reinstall the dev packages for Lua $LUA_MAJOR.$LUA_MINOR])
    fi

    # OK, headers and libs found. Try to set lua flags
    # and modules installation dirs with pkg-config
    if test "$PKGCONFIG" != "no"; then
      if test "$lua_vndot" = "50"; then
        lua_pkg_prefix=lualib
      else
        lua_pkg_prefix=lua
      fi
      # try with dot, without dot and finally without version
      for f in $lua_pkg_prefix$lua_vdot $lua_pkg_prefix$lua_vndot $lua_pkg_prefix; do
        lua_exec_prefix=`$PKGCONFIG --variable=prefix $f 2>/dev/null`
        # same binaries?
        if test "$lua_exec_prefix/bin/lua" = "$LUA"; then
          # OK, found CFLAGS. Get Lua LFLAGS and modules install dir
          LUA_CFLAGS=`$PKGCONFIG --cflags $f 2>/dev/null`
          LUA_LFLAGS=`$PKGCONFIG --libs $f 2>/dev/null`
          LUA_INSTALL_CMOD=`$PKGCONFIG --variable=INSTALL_CMOD $f 2>/dev/null`
          LUA_INSTALL_LMOD=`$PKGCONFIG --variable=INSTALL_LMOD $f 2>/dev/null`
          break
        fi
      done
    fi

    LUA_OSBF_LIBDIR="$prefix/lib/lua/$lua_vdot"

    # if lua 5.0 can't find compat-5.1, force installation of our compat-5.1.lua
    if test "$lua_vdot" = "5.0" -a "$LUA_HAVE_COMPAT51" != "HAVE_COMPAT51"; then
      lua_need_compat51=1
      LUA_INSTALL_LMOD="$LUA_OSBF_LIBDIR"
    fi

    # if not set with pkg-config, use default values in src packages compat-5.1, lua 5.1
    if test "$LUA_CFLAGS" = ""; then
      AC_MSG_WARN(Setting Lua include and lib flags to defaults in compat-5.1 and lua 5.1 sources)
      LUA_CFLAGS="-I/usr/local/include -I/usr/local/include/lua -I/usr/local/include/lua/$lua_vdot"
      LUA_LFLAGS="-L/usr/local/lib -L/usr/local/lib/lua -L/usr/local/lib/lua/$lua_vdot $lua_libs"
      LUA_INSTALL_CMOD="/usr/local/lib/lua/$lua_vdot"
    fi

    dnl pass additional lua options
    dnl if osbf-site-install is not set, overwrite LUA_INSTALL_CMOD already
    dnl found and install in default dir: $PREFIX/lib/lua/$lua_vdot
    AC_ARG_ENABLE(osbf-site-install,
      AC_HELP_STRING([--enable-osbf-site-install], [by default the lua module is installed
                          under $prefix/lib/lua/$lua_version. If you set this
                          option, the lua modules will be installed wherever
                          your Lua setup thinks it is best.
                          WARNING: if you set this option, existing osbf
                                   modules, if any, may be overwritten.]),
      [],
      [LUA_INSTALL_CMOD="$LUA_OSBF_LIBDIR"; LUA_INSTALL_LMOD="$LUA_OSBF_LIBDIR"])

    dnl detect locking method to be used
    AC_ARG_ENABLE([lock],
      [AS_HELP_STRING([--enable-lock[[[[=lockfile|fcntl|no]]]]],
        [default is to search for liblockfile or fcntl, in this order, and use the first found or abort if none is available. You can force one of them or disable locking.])],
      [],
      dnl force search for lock method
      [enable_lock=yes])
      
    no_lock=1; lockfile=2; fcntl_lock=3
    AS_IF(
      [test "$enable_lock" = "lockfile"],
        [AC_CHECK_LIB([liblockfile], [lockfile_create],
          [lock_method=$lockfile; lock_method_name=liblockfile],
          [AC_MSG_FAILURE(
            [--enable-lock=lockfile was given, but test for liblockfile failed])])],
      [test "$enable_lock" = "fcntl"],
        [AC_CHECK_FUNC(fcntl,
          [lock_method=$fcntl_lock; lock_method_name=fcntl],
          [AC_MSG_FAILURE([--enable-lock=fcntl was given, but test for fcntl failed])])],
      [test "$enable_lock" = "no"],
        [lock_method=$no_lock; lock_method_name=none],
      [test "$enable_lock" = "yes"],
        [AC_CHECK_HEADER(lockfile.h,
          [lock_method=$lockfile; lock_method_name=liblockfile],
          [AC_CHECK_HEADER(fcntl.h,
            [lock_method=$fcntl_lock; lock_method_name=fcntl],
            [AC_MSG_FAILURE([Neither lockfile.h nor fnctl.h found!])])])],
      [AC_MSG_FAILURE([Invalid lock method: "$enable_lock"])])

    LUA_DEFINES="-DLUA$lua_vndot -D$LUA_HAVE_COMPAT51 -DLOCK_METHOD=$lock_method"
    AC_SUBST(LUA)
    AC_SUBST(COMP_LUA)
    AC_SUBST(LUA_INSTALL_CMOD)
    AC_SUBST(LUA_INSTALL_LMOD)
    AC_SUBST(LUA_CFLAGS)
    AC_SUBST(LUA_LFLAGS)
    AC_SUBST(LUA_DEFINES)
  fi
fi

dnl If Lua 5.0, we need compat-5.1. Add ours unless already
dnl integrated as in Debian/Ubuntu 5.0 -dev packages.
AM_CONDITIONAL(USE_LOCKFILE, [test "$lock_method" = "$lockfile"])
AM_CONDITIONAL(LUA_SITE_CINSTALL,
      [test "$LUA_INSTALL_CMOD" != "$LUA_OSBF_LIBDIR"])
AM_CONDITIONAL(LUA_SITE_LINSTALL,
      [test "$LUA_INSTALL_LMOD" != "$LUA_OSBF_LIBDIR"])
AM_CONDITIONAL(LUA50, [test "$lua_vndot" = "50"])

AC_CONFIG_FILES([mkconfig])
AC_CONFIG_FILES([Makefile lua/Makefile docs/Makefile])
AC_CONFIG_FILES([testing/Makefile  examples/Makefile examples-autoconfed/Makefile])
AC_CONFIG_FILES([osbf-modname.h])

dnl used only to rename files
AC_CONFIG_FILES([lua/${MOD_NAME}:lua/osbf])
AC_CONFIG_FILES([lua/${MOD_NAME}.lua:lua/osbf.lua])

AC_CONFIG_FILES([examples-autoconfed/count], [chmod a+x examples/count])
AC_CONFIG_FILES([examples-autoconfed/deltas], [chmod a+x examples/deltas])
AC_CONFIG_FILES([examples-autoconfed/dir-classify], [chmod a+x examples/dir-classify])
AC_CONFIG_FILES([examples-autoconfed/dir-train], [chmod a+x examples/dir-train])
AC_CONFIG_FILES([examples-autoconfed/hand-labels], [chmod a+x examples/hand-labels])
AC_CONFIG_FILES([examples-autoconfed/label-by-hand], [chmod a+x examples/label-by-hand])
AC_CONFIG_FILES([examples-autoconfed/low-prob], [chmod a+x examples/low-prob])
AC_CONFIG_FILES([examples-autoconfed/msg-strings], [chmod a+x examples/msg-strings])
AC_CONFIG_FILES([examples-autoconfed/parse-message], [chmod a+x examples/parse-message])
AC_CONFIG_FILES([examples-autoconfed/priors], [chmod a+x examples/priors])
AC_CONFIG_FILES([examples-autoconfed/test-parser], [chmod a+x examples/test-parser])
AC_OUTPUT

echo
echo "--------------------------------------------------------"
echo " Module name:         $MOD_NAME"
echo " Lock method:         $lock_method_name"
echo " Lua binary:          $LUA"
echo " Lua version:         $lua_version"
echo " Lua C-modules dir:   $LUA_INSTALL_CMOD"
echo "--------------------------------------------------------"

