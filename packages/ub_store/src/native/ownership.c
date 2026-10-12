/* Minimal OS bridge for descriptor metadata, protected creation and locking. */
#if defined(__linux__)
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <stdio.h>

#if defined(_WIN32)
#define UB_EXPORT __declspec(dllexport)
/* Windows ACL and handle ownership are a separate platform port. Fail closed. */
UB_EXPORT int32_t ub_private_dir(const char *path) { (void)path; return 50; }
UB_EXPORT int32_t ub_sync_directory(const char *path) { (void)path; return 50; }
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
UB_EXPORT int32_t ub_file_identity(const char *path, char *device, char *inode) {
  (void)path; (void)device; (void)inode; return 50;
}
UB_EXPORT int32_t ub_read_image(const char *path, uint8_t *bytes, int32_t capacity, int32_t *length) {
  (void)path; (void)bytes; (void)capacity; (void)length; return 50;
}
UB_EXPORT int32_t ub_publish_snapshot(const char *source, const char *destination, const char *directory) {
  (void)source; (void)destination; (void)directory; return 50;
}
UB_EXPORT int32_t ub_publish_conversion(const char *source, const char *destination, const char *directory) {
  (void)source; (void)destination; (void)directory; return 50;
}
UB_EXPORT int32_t ub_read_credential(const char *path, uint8_t *bytes, int32_t capacity, int32_t *length) {
  (void)path; (void)bytes; (void)capacity; (void)length; return 50;
}
#else
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/syscall.h>
#endif
#define UB_EXPORT __attribute__((visibility("default")))

/* Read the same checked descriptor; never follow a final symlink or block on a FIFO. */
UB_EXPORT int32_t ub_read_image(const char *path, uint8_t *bytes, int32_t capacity, int32_t *length) {
  if (capacity != 10485761) return EINVAL;
  int fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) return errno;
  struct stat info;
  int error = 0;
  if (fstat(fd, &info) != 0) error = errno;
  else if (!S_ISREG(info.st_mode)) error = EINVAL;
  int32_t total = 0;
  while (!error && total < capacity) {
    ssize_t count = read(fd, bytes + total, (size_t)(capacity - total));
    if (count == 0) break;
    if (count < 0) {
      if (errno == EINTR) continue;
      error = errno;
    } else total += (int32_t)count;
  }
  close(fd);
  *length = total;
  return error;
}

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

/* Legacy credential input is read through the same checked read-only descriptor. */
UB_EXPORT int32_t ub_read_credential(const char *path, uint8_t *bytes, int32_t capacity, int32_t *length) {
  if (capacity != 4097) return EINVAL;
  int fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) return errno;
  struct stat info;
  int error = 0;
  if (fstat(fd, &info) != 0) error = errno;
  else if (!S_ISREG(info.st_mode) || info.st_nlink != 1 ||
           info.st_uid != geteuid() || (info.st_mode & 0077) != 0) error = EACCES;
  else if (info.st_size > 4096) error = EFBIG;
  int32_t total = 0;
  while (!error && total < capacity) {
    ssize_t count = read(fd, bytes + total, (size_t)(capacity - total));
    if (count == 0) break;
    if (count < 0) {
      if (errno == EINTR) continue;
      error = errno;
    } else total += (int32_t)count;
  }
  if (!error && total > 4096) error = EFBIG;
  close(fd);
  *length = total;
  return error;
}

/* Offline conversion publishes exclusively by rename, with no extra hard link. */
UB_EXPORT int32_t ub_publish_conversion(const char *source, const char *destination, const char *directory) {
  int error = 0;
  int fd = protected_open(source, 0, &error);
  if (fd < 0) return error;
  int parent = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (parent < 0) { error = errno; close(fd); return error; }
  struct stat info;
  if (fstat(parent, &info) != 0) error = errno;
  else if (info.st_uid != geteuid() || (info.st_mode & 0077) != 0) error = EACCES;
  if (!error && fsync(fd) != 0) error = errno;
  if (!error) {
#if defined(__APPLE__)
    if (renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, RENAME_EXCL) != 0) error = errno;
#elif defined(__linux__)
    if (syscall(SYS_renameat2, AT_FDCWD, source, AT_FDCWD, destination, 1 /* RENAME_NOREPLACE */) != 0) error = errno;
#else
    error = ENOTSUP;
#endif
  }
  if (!error && fsync(parent) != 0) error = errno;
  close(parent);
  close(fd);
  return error;
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

UB_EXPORT int32_t ub_sync_directory(const char *path) {
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return errno;
  int error = fsync(fd) == 0 ? 0 : errno;
  close(fd);
  return error;
}

UB_EXPORT int32_t ub_protected_file(const char *path, int32_t create) {
  int error = 0;
  int fd = protected_open(path, create, &error);
  if (fd >= 0) close(fd);
  return error;
}

/* Atomic publication refuses any existing destination, including a symlink. */
UB_EXPORT int32_t ub_publish_snapshot(const char *source, const char *destination, const char *directory) {
  int error = 0;
  int fd = protected_open(source, 0, &error);
  if (fd < 0) return error;
  int parent = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (parent < 0) { error = errno; close(fd); return error; }
  if (fsync(fd) != 0) error = errno;
  if (!error && link(source, destination) != 0) error = errno;
  if (!error && unlink(source) != 0) error = errno;
  if (!error && fsync(parent) != 0) error = errno;
  close(parent);
  close(fd);
  return error;
}

struct owned_lock { int fd; };

UB_EXPORT int32_t ub_file_identity(const char *path, char *device, char *inode) {
  struct stat info;
  if (lstat(path, &info) != 0) return errno;
  if (!S_ISREG(info.st_mode) || info.st_nlink != 1) return EACCES;
  /* Decimal text preserves full unsigned metadata without Dart int coercion. */
  snprintf(device, 21, "%llu", (unsigned long long) info.st_dev);
  snprintf(inode, 21, "%llu", (unsigned long long) info.st_ino);
  return 0;
}

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
