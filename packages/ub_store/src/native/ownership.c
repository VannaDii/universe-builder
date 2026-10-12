/* Minimal OS bridge for descriptor metadata, protected creation and locking. */
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>

#if defined(_WIN32)
#define UB_EXPORT __declspec(dllexport)
/* Windows ACL and handle ownership are a separate platform port. Fail closed. */
UB_EXPORT int32_t ub_private_dir(const char *path) { (void)path; return 50; }
UB_EXPORT int32_t ub_protected_file(const char *path, int32_t create) {
  (void)path; (void)create; return 50;
}
UB_EXPORT void *ub_lock_acquire(const char *path, int32_t *error) {
  (void)path; *error = 50; return NULL;
}
UB_EXPORT void ub_lock_release(void *handle) { (void)handle; }
UB_EXPORT int32_t ub_sync_private(const char *path, const char *directory) {
  (void)path; (void)directory; return 50;
}
#else
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#define UB_EXPORT __attribute__((visibility("default")))

static int protected_open(const char *path, int32_t create, int *error) {
  int flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC;
  if (create != 0) flags |= O_CREAT;
  if (create == 2) flags |= O_EXCL;
  int fd = open(path, flags, 0600);
  if (fd < 0) { *error = errno; return -1; }
  struct stat info;
  if (fstat(fd, &info) != 0) {
    *error = errno; close(fd); return -1;
  }
  if (!S_ISREG(info.st_mode) || info.st_nlink != 1 ||
      info.st_uid != geteuid() || (info.st_mode & 0077) != 0) {
    *error = EACCES; close(fd); return -1;
  }
  return fd;
}

UB_EXPORT int32_t ub_private_dir(const char *path) {
  if (mkdir(path, 0700) != 0 && errno != EEXIST) return errno;
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return errno;
  struct stat info;
  int error = 0;
  if (fstat(fd, &info) != 0) error = errno;
  else if (!S_ISDIR(info.st_mode) || info.st_uid != geteuid() ||
           (info.st_mode & 0077) != 0) error = EACCES;
  close(fd);
  return error;
}

UB_EXPORT int32_t ub_protected_file(const char *path, int32_t create) {
  int error = 0;
  int fd = protected_open(path, create, &error);
  if (fd >= 0) close(fd);
  return error;
}

struct owned_lock { int fd; };

UB_EXPORT int32_t ub_sync_private(const char *path, const char *directory) {
  int error = 0;
  int file = protected_open(path, 0, &error);
  if (file < 0) return error;
  if (fsync(file) != 0) error = errno;
  close(file);
  if (error != 0) return error;
  int dir = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (dir < 0) return errno;
  struct stat info;
  if (fstat(dir, &info) != 0) error = errno;
  else if (info.st_uid != geteuid() || (info.st_mode & 0077) != 0) error = EACCES;
  else if (fsync(dir) != 0) error = errno;
  close(dir);
  return error;
}

UB_EXPORT void *ub_lock_acquire(const char *path, int32_t *error) {
  *error = 0;
  int fd = protected_open(path, 1, error);
  if (fd < 0) return NULL;
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
    *error = errno; close(fd); return NULL;
  }
  struct owned_lock *handle = malloc(sizeof(*handle));
  if (handle == NULL) {
    *error = ENOMEM; flock(fd, LOCK_UN); close(fd); return NULL;
  }
  handle->fd = fd;
  return handle;
}

UB_EXPORT void ub_lock_release(void *opaque) {
  struct owned_lock *handle = opaque;
  if (handle == NULL) return;
  /* Explicit unlock prevents inherited descriptors from retaining ownership. */
  flock(handle->fd, LOCK_UN);
  close(handle->fd);
  free(handle);
}
#endif
