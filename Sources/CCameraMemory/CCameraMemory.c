#include "CCameraMemory.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

/* C's variadic shm_open is unavailable directly to Swift. Keep this ABI shim
   small: private shared RAM, immediately unnamed, no persistent image files. */
int photo_camera_memory_create(const char *name, size_t size) {
  int descriptor = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
  if (descriptor < 0) return -1;
  if (shm_unlink(name) != 0 || ftruncate(descriptor, (off_t)size) != 0) {
    int saved = errno;
    close(descriptor);
    shm_unlink(name);
    errno = saved;
    return -1;
  }
  return descriptor;
}
