#include "native_files.h"

#include <cstring>
#include <string>

namespace {
struct FileOperation {
  FlMethodCall* call;
  std::string method;
  std::string argument;
  std::string destination;
  GtkFileChooserNative* chooser = nullptr;
  ~FileOperation() {
    g_clear_object(&chooser);
    g_object_unref(call);
  }
};

void failure(FileOperation* operation, const char* message) {
  fl_method_call_respond_error(operation->call, "file_unavailable", message,
                               nullptr, nullptr);
  delete operation;
}

void copied(GObject* source, GAsyncResult* result, gpointer data) {
  auto* operation = static_cast<FileOperation*>(data);
  g_autoptr(GError) error = nullptr;
  if (!g_file_copy_finish(G_FILE(source), result, &error)) {
    failure(operation, "Could not copy the file. Choose an unused filename.");
    return;
  }
  g_autoptr(FlValue) value = operation->method == "saveBackup"
      ? fl_value_new_string(operation->destination.c_str())
      : fl_value_new_bool(true);
  fl_method_call_respond_success(operation->call, value, nullptr);
  delete operation;
}

void selected(GtkNativeDialog* dialog, gint response, gpointer data) {
  auto* operation = static_cast<FileOperation*>(data);
  if (response != GTK_RESPONSE_ACCEPT) {
    g_autoptr(FlValue) cancelled = operation->method == "openBackup"
        ? fl_value_new_bool(false) : fl_value_new_null();
    fl_method_call_respond_success(operation->call, cancelled, nullptr);
    delete operation;
    return;
  }
  g_autofree gchar* filename = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
  if (!filename || !g_utf8_validate(filename, -1, nullptr)) {
    failure(operation, "Choose a local file with a UTF-8 filename.");
    return;
  }
  if (operation->method == "pickImage" || operation->method == "pickSourceText") {
    g_autoptr(FlValue) value = fl_value_new_string(filename);
    fl_method_call_respond_success(operation->call, value, nullptr);
    delete operation;
    return;
  }
  const bool save = operation->method == "saveBackup";
  g_autoptr(GFile) source = g_file_new_for_path(save ? operation->argument.c_str() : filename);
  operation->destination = save ? filename : operation->argument;
  g_autoptr(GFile) destination = g_file_new_for_path(operation->destination.c_str());
  g_autoptr(GError) error = nullptr;
  g_autoptr(GFileInfo) info = g_file_query_info(source,
      G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SIZE,
      G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, nullptr, &error);
  if (!info || g_file_info_get_file_type(info) != G_FILE_TYPE_REGULAR ||
      g_file_info_get_size(info) > static_cast<goffset>(8LL * 1024 * 1024 * 1024)) {
    failure(operation, "Choose a regular Universe Builder file no larger than 8 GiB.");
    return;
  }
  g_clear_object(&operation->chooser);
  // Never overwrite a destination. Large copies run outside the GTK UI thread.
  g_file_copy_async(source, destination, G_FILE_COPY_NOFOLLOW_SYMLINKS,
      G_PRIORITY_DEFAULT, nullptr, nullptr, nullptr, copied, operation);
}

void files(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  const char* method = fl_method_call_get_name(call);
  if (strcmp(method, "releasePickedFile") == 0) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;  // Desktop selections are original paths, not temporary cache copies.
  }
  const bool save = strcmp(method, "saveBackup") == 0;
  const bool open = strcmp(method, "openBackup") == 0;
  const bool text = strcmp(method, "pickSourceText") == 0;
  const bool image = strcmp(method, "pickImage") == 0;
  if (!save && !open && !text && !image) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* argument = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(args, save ? "source" : "destination") : nullptr;
  if ((save || open) && (!argument || fl_value_get_type(argument) != FL_VALUE_TYPE_STRING)) {
    fl_method_call_respond_error(call, "invalid_file", "File path unavailable.", nullptr, nullptr);
    return;
  }
  auto* operation = new FileOperation{FL_METHOD_CALL(g_object_ref(call)), method,
      (save || open) ? fl_value_get_string(argument) : "", "", nullptr};
  const char* title = save ? "Save Universe Builder file" : open ? "Choose Universe Builder file"
      : text ? "Choose source text" : "Choose appearance image";
  operation->chooser = gtk_file_chooser_native_new(title, GTK_WINDOW(data),
      save ? GTK_FILE_CHOOSER_ACTION_SAVE : GTK_FILE_CHOOSER_ACTION_OPEN,
      save ? "_Save" : "_Open", "_Cancel");
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(operation->chooser);
  gtk_file_chooser_set_local_only(chooser, true);
  if (save) {
    g_autofree gchar* name = g_path_get_basename(operation->argument.c_str());
    gtk_file_chooser_set_current_name(chooser, name);
  } else if (text || image) {
    GtkFileFilter* filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, text ? "Source text" : "Appearance images");
    if (text) {
      gtk_file_filter_add_mime_type(filter, "text/plain");
      gtk_file_filter_add_pattern(filter, "*.md");
    } else {
      gtk_file_filter_add_mime_type(filter, "image/png");
      gtk_file_filter_add_mime_type(filter, "image/jpeg");
      gtk_file_filter_add_mime_type(filter, "image/webp");
    }
    gtk_file_chooser_add_filter(chooser, filter);
  }
  g_signal_connect(operation->chooser, "response", G_CALLBACK(selected), operation);
  gtk_native_dialog_set_modal(GTK_NATIVE_DIALOG(operation->chooser), true);
  gtk_native_dialog_show(GTK_NATIVE_DIALOG(operation->chooser));
}
}  // namespace

void register_file_channels(FlView* view, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "universe_builder/backup_files", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, files, window, nullptr);
}
