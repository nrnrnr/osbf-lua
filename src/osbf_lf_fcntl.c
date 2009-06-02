#include "osbf_lockfile.h"

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

static int lock_file_fcntl(int fd, uint32_t start, uint32_t len)
{
  int max_lock_attempts = 20;
  int r;
  struct flock fl;

  fl.l_type = F_WRLCK;          /* write lock */
  fl.l_whence = SEEK_SET;
  fl.l_start = start;
  fl.l_len = len;

  do {
      r = fcntl(fd, F_SETLK, &fl);
  } while (r == -1 && (errno == EAGAIN || errno == EACCES) &&
           (max_lock_attempts-- > 0) && (sleep(1) || 1));

  return r;
}

static int unlock_file_fcntl(int fd, uint32_t start, uint32_t len)
{
  struct flock fl;

  fl.l_type = F_UNLCK;
  fl.l_whence = SEEK_SET;
  fl.l_start = start;
  fl.l_len = len;
  if (fcntl (fd, F_SETLK, &fl) == -1)
    return -1;
  else
    return 0;
}

int osbf_lock_class(CLASS_STRUCT *class, uint32_t start, uint32_t len) {
  return lock_file_fcntl(class->fd, start, len);
}

int osbf_unlock_class (CLASS_STRUCT *class, uint32_t start, uint32_t len) {
  return unlock_file_fcntl(class->fd, start, len);
}
