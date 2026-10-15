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
#elif defined(__linux__) && !defined(__ANDROID__)
#include <libsecret/secret.h>
#define UB_EXPORT __attribute__((visibility("default")))
#define UB_KEY_UNAVAILABLE (-4)
#define UB_KEY_MISSING (-25300)

/* Use libsecret's session/encryption implementation. A private proxy refuses
 * both prompt paths, including prompts caused by a concurrent keyring lock. */
typedef struct { SecretService parent; } UbSecretService;
typedef struct { SecretServiceClass parent; } UbSecretServiceClass;
G_DEFINE_TYPE(UbSecretService, ub_secret_service, SECRET_TYPE_SERVICE)

static GVariant *refuse_prompt(SecretService *self, SecretPrompt *prompt,
    GCancellable *cancel, const GVariantType *type, GError **error) {
  (void)self; (void)prompt; (void)cancel; (void)type;
  g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_PERMISSION_DENIED,
      "Credential store requires user interaction");
  return NULL;
}

static void refuse_prompt_async(SecretService *self, SecretPrompt *prompt,
    const GVariantType *type, GCancellable *cancel,
    GAsyncReadyCallback callback, gpointer data) {
  (void)prompt; (void)type;
  GTask *task = g_task_new(self, cancel, callback, data);
  g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_PERMISSION_DENIED,
      "Credential store requires user interaction");
  g_object_unref(task);
}

static GVariant *refuse_prompt_finish(SecretService *self,
    GAsyncResult *result, GError **error) {
  (void)self;
  return g_task_propagate_pointer(G_TASK(result), error);
}

static void ub_secret_service_class_init(UbSecretServiceClass *klass) {
  SecretServiceClass *service = SECRET_SERVICE_CLASS(klass);
  service->prompt_sync = refuse_prompt;
  service->prompt_async = refuse_prompt_async;
  service->prompt_finish = refuse_prompt_finish;
}
static void ub_secret_service_init(UbSecretService *self) { (void)self; }

static SecretService *open_service(GError **error) {
  return secret_service_open_sync(ub_secret_service_get_type(), NULL,
      SECRET_SERVICE_OPEN_SESSION, NULL, error);
}

static GHashTable *key_attributes(const char *reference) {
  GHashTable *attrs = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
  g_hash_table_insert(attrs, g_strdup("service"),
      g_strdup("Universe Builder Installation Encryption v1"));
  g_hash_table_insert(attrs, g_strdup("account"), g_strdup(reference));
  return attrs;
}

UB_EXPORT int32_t ub_key_create(const char *reference, const uint8_t *key) {
  g_autoptr(GError) error = NULL;
  g_autoptr(SecretService) service = open_service(&error);
  if (!service) return UB_KEY_UNAVAILABLE;
  g_autoptr(GHashTable) attrs = key_attributes(reference);
  g_autolist(SecretItem) existing = secret_service_search_sync(service, NULL,
      attrs, SECRET_SEARCH_ALL, NULL, &error);
  if (error || existing) return UB_KEY_UNAVAILABLE; /* Add only. */
  g_autoptr(SecretCollection) collection = secret_collection_for_alias_sync(
      service, "default", SECRET_COLLECTION_NONE, NULL, &error);
  if (!collection || secret_collection_get_locked(collection)) return UB_KEY_UNAVAILABLE;
  g_autoptr(SecretValue) value = secret_value_new((const gchar *)key, 32,
      "application/octet-stream");
  g_autoptr(SecretItem) item = secret_item_create_sync(collection, NULL, attrs,
      "Universe Builder installation encryption key", value,
      SECRET_ITEM_CREATE_NONE, NULL, &error);
  return item && !error ? 0 : UB_KEY_UNAVAILABLE;
}

UB_EXPORT int32_t ub_key_read(const char *reference, uint8_t *key) {
  memset(key, 0, 32);
  g_autoptr(GError) error = NULL;
  g_autoptr(SecretService) service = open_service(&error);
  if (!service) return UB_KEY_UNAVAILABLE;
  g_autoptr(GHashTable) attrs = key_attributes(reference);
  g_autolist(SecretItem) items = secret_service_search_sync(service, NULL, attrs,
      SECRET_SEARCH_ALL | SECRET_SEARCH_LOAD_SECRETS, NULL, &error);
  if (error) return UB_KEY_UNAVAILABLE;
  if (!items) return UB_KEY_MISSING;
  if (items->next || secret_item_get_locked(items->data)) return UB_KEY_UNAVAILABLE;
  g_autoptr(SecretValue) value = secret_item_get_secret(items->data);
  if (!value) return UB_KEY_UNAVAILABLE;
  gsize length = 0;
  const gchar *bytes = secret_value_get(value, &length);
  /* Providers can normalize the MIME hint. The key contract is exactly 32
   * bytes; endpoint authentication detects a missing/wrong key independently. */
  if (!bytes || length != 32) return UB_KEY_UNAVAILABLE;
  memcpy(key, bytes, 32);
  return 0;
}

UB_EXPORT int32_t ub_key_delete(const char *reference) {
  g_autoptr(GError) error = NULL;
  g_autoptr(SecretService) service = open_service(&error);
  if (!service) return UB_KEY_UNAVAILABLE;
  g_autoptr(GHashTable) attrs = key_attributes(reference);
  g_autolist(SecretItem) items = secret_service_search_sync(service, NULL, attrs,
      SECRET_SEARCH_ALL, NULL, &error);
  if (error) return UB_KEY_UNAVAILABLE;
  if (!items) return UB_KEY_MISSING;
  if (items->next || secret_item_get_locked(items->data)) return UB_KEY_UNAVAILABLE;
  return secret_item_delete_sync(items->data, NULL, &error) && !error
      ? 0 : UB_KEY_UNAVAILABLE;
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
