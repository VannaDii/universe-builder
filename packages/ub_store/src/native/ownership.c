/* Minimal OS bridge for descriptor metadata, protected creation and locking. */
#if defined(__linux__)
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#define UB_EXPORT __declspec(dllexport)
UB_EXPORT int32_t ub_peer_options(int32_t *level, int32_t *option, int32_t *length) {
  (void)level; (void)option; (void)length; return 50;
}
UB_EXPORT int32_t ub_peer_matches(const uint8_t *bytes, int32_t length) {
  (void)bytes; (void)length; return 50;
}
UB_EXPORT int32_t ub_socket_path(const char *path, int32_t action) {
  (void)path; (void)action; return 50;
}
UB_EXPORT int32_t ub_owned_socket(const char *path, char *device, char *inode, int32_t action) {
  (void)path; (void)device; (void)inode; (void)action; return 50;
}
UB_EXPORT int32_t ub_publish_socket(const char *source, const char *destination) {
  (void)source; (void)destination; return 50;
}
/* Windows ACL and handle ownership are a separate platform port. Fail closed. */
UB_EXPORT int32_t ub_private_dir(const char *path) { (void)path; return 50; }
UB_EXPORT int32_t ub_private_temp_dir(char *path) { (void)path; return 50; }
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
#else
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/socket.h>
#if defined(__APPLE__)
#include <sys/un.h>
#include <sys/ucred.h>
#endif
#if defined(__linux__)
#include <sys/syscall.h>
#endif
#if defined(__ANDROID__)
#include <linux/fs.h>
#endif
#define UB_EXPORT __attribute__((visibility("default")))

/* Dart obtains getsockopt bytes from its owned socket. Keep ABI/layout and
 * effective-user comparison here instead of guessing struct offsets in Dart. */
UB_EXPORT int32_t ub_peer_options(int32_t *level, int32_t *option, int32_t *length) {
#if defined(__APPLE__)
  *level = SOL_LOCAL; *option = LOCAL_PEERCRED; *length = sizeof(struct xucred); return 0;
#elif defined(__linux__)
  *level = SOL_SOCKET; *option = SO_PEERCRED; *length = sizeof(struct ucred); return 0;
#else
  return ENOTSUP;
#endif
}

UB_EXPORT int32_t ub_peer_matches(const uint8_t *bytes, int32_t length) {
#if defined(__APPLE__)
  if (length != sizeof(struct xucred)) return EINVAL;
  struct xucred peer; memcpy(&peer, bytes, sizeof(peer));
  return peer.cr_version == XUCRED_VERSION && peer.cr_uid == geteuid() ? 0 : EACCES;
#elif defined(__linux__)
  if (length != sizeof(struct ucred)) return EINVAL;
  struct ucred peer; memcpy(&peer, bytes, sizeof(peer));
  return peer.uid == geteuid() ? 0 : EACCES;
#else
  return ENOTSUP;
#endif
}

UB_EXPORT int32_t ub_socket_path(const char *path, int32_t action) {
  if (action < 0 || action > 2) return EINVAL;
  struct stat info;
  if (lstat(path, &info) != 0) return errno;
  if (!S_ISSOCK(info.st_mode) || info.st_uid != geteuid() || info.st_nlink != 1) return EACCES;
  if (action == 0) return (info.st_mode & 0077) == 0 ? 0 : EACCES;
  if (action == 1) return chmod(path, 0600) == 0 ? 0 : errno;
  return unlink(path) == 0 ? 0 : errno;
}

/* Capture the newly bound endpoint, then unlink only that same socket. */
UB_EXPORT int32_t ub_owned_socket(const char *path, char *device, char *inode, int32_t action) {
  struct stat info;
  if (action != 0 && action != 1) return EINVAL;
  if (lstat(path, &info) != 0) return action == 1 && errno == ENOENT ? 0 : errno;
  if (!S_ISSOCK(info.st_mode) || info.st_uid != geteuid() || info.st_nlink != 1) return EACCES;
  char actual_device[21], actual_inode[21];
  snprintf(actual_device, sizeof(actual_device), "%llu", (unsigned long long)info.st_dev);
  snprintf(actual_inode, sizeof(actual_inode), "%llu", (unsigned long long)info.st_ino);
  if (action == 0) {
    memcpy(device, actual_device, strlen(actual_device) + 1);
    memcpy(inode, actual_inode, strlen(actual_inode) + 1);
    return 0;
  }
  if (strcmp(device, actual_device) || strcmp(inode, actual_inode)) return EACCES;
  return unlink(path) == 0 ? 0 : errno;
}

/* Publish without replacing an existing endpoint. The Dart listener retains
   its private staging pathname for automatic unlink on close. */
UB_EXPORT int32_t ub_publish_socket(const char *source, const char *destination) {
  struct stat info;
  if (lstat(source, &info) != 0) return errno;
  if (!S_ISSOCK(info.st_mode) || info.st_uid != geteuid() || info.st_nlink != 1 ||
      (info.st_mode & 0077) != 0) return EACCES;
  if (link(source, destination) != 0) return errno;
  if (unlink(source) == 0) return 0;
  int error = errno;
  unlink(destination);
  return error;
}


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

/* mkdtemp creates 0700 atomically, independently of a permissive process umask. */
UB_EXPORT int32_t ub_private_temp_dir(char *path) {
  return mkdtemp(path) ? 0 : errno;
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
#if defined(__ANDROID__)
  /* App SELinux domains cannot create hard links. Keep atomic create-only
     publication with the kernel operation (libc exposes it only from API 30). */
  if (!error && syscall(__NR_renameat2, AT_FDCWD, source, AT_FDCWD,
                        destination, RENAME_NOREPLACE) != 0) error = errno;
#else
  if (!error && link(source, destination) != 0) error = errno;
  if (!error && unlink(source) != 0) error = errno;
#endif
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
