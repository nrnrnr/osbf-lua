#include "osbf_lockfile.h"

#include <stdio.h>
#include <string.h>
#include <lockfile.h>

static int make_linkname(const char *classname, char *linkname, int size);
static int make_linkname(const char *classname, char *linkname, int size) {
  int len = strlen(classname);

  if (len+4 > size-1)
    return -1;

  strncpy(linkname, classname, size);
  strncat(linkname, ".lock", size-len);
  return 0;
}

static int lock_file_lockfile(const char *filename)
{
  int max_lock_attempts = 20;
  char linkname[512]; /* temporary, for tests */

  if (make_linkname(filename, linkname, sizeof(linkname)) != 0)
    return -1;
  return  lockfile_create(linkname, max_lock_attempts, 0);
}

static int unlock_file_lockfile(const char *filename)
{
  char linkname[512]; /* temporary, for tests */

  if (filename != NULL) {
    if (make_linkname(filename, linkname, sizeof(linkname)) != 0)
      return -1;
    return lockfile_remove(linkname);
  } else {
    fprintf(stderr, "Warning: Trying to unlock NULL file\n");
    return 0;
  }
}

int osbf_lock_class(CLASS_STRUCT *class, uint32_t start, uint32_t len)
{
  (void)start, (void)len; /* keep compiler quiet */
  return lock_file_lockfile(class->classname);
}


int
osbf_unlock_class (CLASS_STRUCT *class, uint32_t start, uint32_t len)
{
  (void) start, (void) len; /* keep compiler quiet */
  return unlock_file_lockfile(class->classname);
}
