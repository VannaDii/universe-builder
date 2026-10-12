/* Fixed installation-key operations; no command-line or plaintext-file path. */
#include <stdint.h>
#include <string.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_OSX
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <pthread.h>
#define UB_EXPORT __attribute__((visibility("default")))

/* File-based macOS Keychain supports unsigned headless development binaries.
 * Packaged app/helper access must be qualified with their actual signatures.
 * Legacy Keychain UI control is process-wide: serialize our calls and restore
 * the previous setting, so the bridge never starts an authentication dialog. */
static pthread_mutex_t interaction_lock = PTHREAD_MUTEX_INITIALIZER;

static CFMutableDictionaryRef query(const char *reference) {
  CFStringRef account = CFStringCreateWithCString(NULL, reference, kCFStringEncodingUTF8);
  if (!account) return NULL;
  CFMutableDictionaryRef result = CFDictionaryCreateMutable(NULL, 0,
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  if (result) {
    CFDictionarySetValue(result, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(result, kSecAttrService, CFSTR("Universe Builder Installation Encryption v1"));
    CFDictionarySetValue(result, kSecAttrAccount, account);
    CFDictionarySetValue(result, kSecAttrSynchronizable, kCFBooleanFalse);
    CFDictionarySetValue(result, kSecUseDataProtectionKeychain, kCFBooleanFalse);
  }
  CFRelease(account);
  return result;
}

static OSStatus begin_call(Boolean *previous) {
  pthread_mutex_lock(&interaction_lock);
  OSStatus status = SecKeychainGetUserInteractionAllowed(previous);
  if (status == errSecSuccess) status = SecKeychainSetUserInteractionAllowed(false);
  if (status != errSecSuccess) pthread_mutex_unlock(&interaction_lock);
  return status;
}

static void end_call(Boolean previous) {
  SecKeychainSetUserInteractionAllowed(previous);
  pthread_mutex_unlock(&interaction_lock);
}

UB_EXPORT int32_t ub_key_create(const char *reference, const uint8_t *key) {
  CFMutableDictionaryRef attributes = query(reference);
  if (!attributes) return errSecParam;
  CFDataRef bytes = CFDataCreate(NULL, key, 32);
  if (!bytes) { CFRelease(attributes); return errSecAllocate; }
  CFDictionarySetValue(attributes, kSecValueData, bytes);
  CFDictionarySetValue(attributes, kSecAttrLabel, CFSTR("Universe Builder installation encryption key"));
  Boolean previous;
  OSStatus status = begin_call(&previous);
  if (status == errSecSuccess) {
    /* Add only: never replace the key that decrypts existing configuration. */
    status = SecItemAdd(attributes, NULL);
    end_call(previous);
  }
  CFRelease(bytes);
  CFRelease(attributes);
  return status;
}

UB_EXPORT int32_t ub_key_read(const char *reference, uint8_t *key) {
  memset(key, 0, 32);
  CFMutableDictionaryRef attributes = query(reference);
  if (!attributes) return errSecParam;
  CFDictionarySetValue(attributes, kSecReturnData, kCFBooleanTrue);
  CFDictionarySetValue(attributes, kSecMatchLimit, kSecMatchLimitOne);
  CFTypeRef result = NULL;
  Boolean previous;
  OSStatus status = begin_call(&previous);
  if (status == errSecSuccess) {
    status = SecItemCopyMatching(attributes, &result);
    end_call(previous);
  }
  if (status == errSecSuccess) {
    if (!result || CFGetTypeID(result) != CFDataGetTypeID() ||
        CFDataGetLength((CFDataRef) result) != 32) {
      status = errSecDecode;
    } else {
      memcpy(key, CFDataGetBytePtr((CFDataRef) result), 32);
    }
  }
  if (result) CFRelease(result);
  CFRelease(attributes);
  return status;
}

UB_EXPORT int32_t ub_key_delete(const char *reference) {
  CFMutableDictionaryRef attributes = query(reference);
  if (!attributes) return errSecParam;
  Boolean previous;
  OSStatus status = begin_call(&previous);
  if (status == errSecSuccess) {
    /* Exact fixed service + unique account; never enumerate/delete broadly. */
    status = SecItemDelete(attributes);
    end_call(previous);
  }
  CFRelease(attributes);
  return status;
}
#else
#if defined(_WIN32)
#define UB_EXPORT __declspec(dllexport)
#else
#define UB_EXPORT __attribute__((visibility("default")))
#endif
/* Other OS adapters remain explicit ports; no plaintext fallback. */
UB_EXPORT int32_t ub_key_create(const char *reference, const uint8_t *key) {
  (void)reference; (void)key; return -4;
}
UB_EXPORT int32_t ub_key_read(const char *reference, uint8_t *key) {
  (void)reference; memset(key, 0, 32); return -4;
}
UB_EXPORT int32_t ub_key_delete(const char *reference) {
  (void)reference; return -4;
}
#endif
