#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "native_files.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gchar* pending_link;
  FlMethodChannel* navigation_channel;
  FlMethodChannel* ready_channel;
  gboolean navigation_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

struct WindowPreferences {
  gint width = 1280;
  gint height = 720;
  gboolean maximized = FALSE;
};

static gchar* window_preferences_path() {
  return g_build_filename(g_get_user_config_dir(), "universe-builder",
                          "window.ini", nullptr);
}

static gboolean remember_window_size(GtkWidget* widget, GdkEventConfigure*,
                                     WindowPreferences* preferences) {
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window && !(gdk_window_get_state(window) &
                  (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN |
                   GDK_WINDOW_STATE_ICONIFIED))) {
    gtk_window_get_size(GTK_WINDOW(widget), &preferences->width,
                         &preferences->height);
  }
  return FALSE;
}

static gboolean remember_window_state(GtkWidget*, GdkEventWindowState* event,
                                      WindowPreferences* preferences) {
  preferences->maximized =
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  return FALSE;
}

static gboolean save_window_preferences(GtkWidget*, GdkEvent*,
                                         WindowPreferences* preferences) {
  g_autofree gchar* path = window_preferences_path();
  g_autofree gchar* directory = g_path_get_dirname(path);
  if (g_mkdir_with_parents(directory, 0700) != 0) return FALSE;
  g_autoptr(GKeyFile) settings = g_key_file_new();
  g_key_file_set_integer(settings, "window", "width", preferences->width);
  g_key_file_set_integer(settings, "window", "height", preferences->height);
  g_key_file_set_boolean(settings, "window", "maximized", preferences->maximized);
  // Window preferences are optional; a read-only configuration directory must
  // never prevent closing the author workspace.
  g_key_file_save_to_file(settings, path, nullptr);
  return FALSE;
}

static void restore_window_preferences(GtkWindow* window) {
  auto* preferences = new WindowPreferences();
  g_object_set_data_full(G_OBJECT(window), "ub-window-preferences", preferences,
                        [](gpointer data) {
                          delete static_cast<WindowPreferences*>(data);
                        });
  g_autofree gchar* path = window_preferences_path();
  g_autoptr(GKeyFile) settings = g_key_file_new();
  if (g_key_file_load_from_file(settings, path, G_KEY_FILE_NONE, nullptr)) {
    gint width = g_key_file_get_integer(settings, "window", "width", nullptr);
    gint height = g_key_file_get_integer(settings, "window", "height", nullptr);
    if (width > 0 && height > 0) {
      preferences->width = width;
      preferences->height = height;
    }
    preferences->maximized =
        g_key_file_get_boolean(settings, "window", "maximized", nullptr);
  }
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (!monitor && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor) {
    GdkRectangle area;
    gdk_monitor_get_workarea(monitor, &area);
    if (area.width > 0 && area.height > 0) {
      preferences->width = MIN(preferences->width, area.width);
      preferences->height = MIN(preferences->height, area.height);
    }
  }
  gtk_window_set_default_size(window, preferences->width, preferences->height);
  if (preferences->maximized) gtk_window_maximize(window);
  g_signal_connect(window, "configure-event", G_CALLBACK(remember_window_size),
                   preferences);
  g_signal_connect(window, "window-state-event", G_CALLBACK(remember_window_state),
                   preferences);
  // Flutter can quit the application before GTK emits destroy. Save before its
  // close handler runs, then let Flutter finish the normal close request.
  g_signal_connect(window, "delete-event", G_CALLBACK(save_window_preferences),
                   preferences);
}

// Native startup arguments hold a link until Dart has rendered its Router.
static void deliver_pending_link(MyApplication* self) {
  if (!self->navigation_ready || !self->pending_link) return;
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "location", fl_value_new_string(self->pending_link));
  fl_method_channel_invoke_method(self->navigation_channel, "pushRouteInformation",
                                  arguments, nullptr, nullptr, nullptr);
  g_clear_pointer(&self->pending_link, g_free);
}

static void navigation_ready(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  if (g_strcmp0(fl_method_call_get_name(call), "ready") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  MyApplication* self = MY_APPLICATION(data);
  self->navigation_ready = TRUE;
  deliver_pending_link(self);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Universe Builder");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Universe Builder");
  }

  restore_window_preferences(window);
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon = g_build_filename(directory, "data", "icons", "universe-builder.png", nullptr);
    if (g_file_test(icon, G_FILE_TEST_IS_REGULAR)) {
      gtk_window_set_icon_from_file(window, icon, nullptr);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  register_file_channels(view, window);

  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlJsonMethodCodec) navigation_codec = fl_json_method_codec_new();
  self->navigation_channel = fl_method_channel_new(messenger, "flutter/navigation",
      FL_METHOD_CODEC(navigation_codec));
  g_autoptr(FlStandardMethodCodec) ready_codec = fl_standard_method_codec_new();
  self->ready_channel = fl_method_channel_new(messenger, "universe_builder/navigation",
      FL_METHOD_CODEC(ready_codec));
  fl_method_channel_set_method_call_handler(self->ready_channel, navigation_ready,
                                             self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  for (gchar** argument = *arguments + 1; *argument; argument++) {
    if (g_strcmp0(*argument, "--link") == 0 && *(argument + 1)) {
      argument++;
      if (g_str_has_prefix(*argument, "universe-builder:")) {
        g_free(self->pending_link);
        self->pending_link = g_strdup(*argument);
      }
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->pending_link, g_free);
  g_clear_object(&self->navigation_channel);
  g_clear_object(&self->ready_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
