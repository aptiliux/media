/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

public class ClipLibraryView : Gtk.EventBox {
    Model.Project project;
    Gtk.TreeView tree_view;
    Gtk.TreeSelection selection;
    Gtk.Label label = null;
    Gtk.ListStore list_store;
    int num_clipfiles;
    Gee.ArrayList<string> files_dragging = new Gee.ArrayList<string>();

    Gtk.IconTheme icon_theme;

    Gdk.Pixbuf default_audio_icon;
    Gdk.Pixbuf default_video_icon;
    Gdk.Pixbuf default_error_icon;

    enum SortMode {
        NONE,
        ABC
    }

    enum ColumnType {
        THUMBNAIL,
        NAME,
        DURATION,
        FILENAME
    }

    public signal void selection_changed(bool selected);

    SortMode sort_mode;
    Model.TimeSystem time_provider;

    public ClipLibraryView(Model.Project p, Model.TimeSystem time_provider, string? drag_message) {
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, drag_target_entries, Gdk.DragAction.COPY);
        project = p;
        this.time_provider = time_provider;

        icon_theme = Gtk.IconTheme.get_default();

        list_store = new Gtk.ListStore(4, typeof (Gdk.Pixbuf), typeof (string),
                                       typeof (string), typeof (string), -1);
                                       
        tree_view = new Gtk.TreeView.with_model(list_store);

        add_column(ColumnType.THUMBNAIL);
        add_column(ColumnType.NAME);
        add_column(ColumnType.DURATION);

        num_clipfiles = 0;
        if (drag_message != null) {
            label = new Gtk.Label(drag_message);
            label.modify_fg(Gtk.StateType.NORMAL, parse_color("#fff"));
        }

        modify_bg(Gtk.StateType.NORMAL, parse_color("#444"));
        tree_view.modify_base(Gtk.StateType.NORMAL, parse_color("#444"));

        tree_view.set_headers_visible(false);
        project.clipfile_added += on_clipfile_added;
        project.cleared += remove_all_rows;

        Gtk.drag_source_set(tree_view, Gdk.ModifierType.BUTTON1_MASK, drag_target_entries,
                            Gdk.DragAction.COPY);
        tree_view.drag_begin += on_drag_begin;
        tree_view.drag_data_get += on_drag_data_get;
        tree_view.cursor_changed += on_cursor_changed;

        selection = tree_view.get_selection();
        selection.set_mode(Gtk.SelectionMode.MULTIPLE);
        if (label != null) {
            add(label);
        }

        // We have to have our own button press and release handlers
        // since the normal drag-selection handling does not allow you
        // to click outside any cell in the library to clear your selection,
        // and also does not allow dragging multiple clips from the library
        // to the timeline
        tree_view.button_press_event += on_button_pressed;
        tree_view.button_release_event += on_button_released;

        try {
            default_audio_icon =
                icon_theme.load_icon("audio-x-generic", 32, (Gtk.IconLookupFlags) 0);
            default_video_icon =
                icon_theme.load_icon("video-x-generic", 32, (Gtk.IconLookupFlags) 0);
            default_error_icon =
                icon_theme.load_icon("error", 32, (Gtk.IconLookupFlags) 0);
        } catch (GLib.Error e) {
            // TODO: what shall we do if these icons are not available?
        }

        sort_mode = SortMode.ABC;
    }

    Gtk.TreePath? find_first_selected() {
        Gtk.TreeIter it;
        Gtk.TreeModel model = tree_view.get_model();

        bool b = model.get_iter_first(out it);
        while (b) {
            Gtk.TreePath path = model.get_path(it);
            if (selection.path_is_selected(path))
                return path;

            b = model.iter_next(ref it);
        }
        return null;
    }

    bool on_button_pressed(Gdk.EventButton b) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_button_pressed");
        Gtk.TreePath path;
        int cell_x;
        int cell_y;

        tree_view.get_path_at_pos((int) b.x, (int) b.y, out path, null, out cell_x, out cell_y);

        if (path == null) {
            selection.unselect_all();
            return true;
        }

        bool shift_pressed = (b.state & Gdk.ModifierType.SHIFT_MASK) != 0;
        bool control_pressed = (b.state & Gdk.ModifierType.CONTROL_MASK) != 0;

        if (!control_pressed &&
            !shift_pressed) {
            if (!selection.path_is_selected(path))
                selection.unselect_all();
        } else {
            if (shift_pressed) {
                Gtk.TreePath first = find_first_selected();

                if (first != null)
                    selection.select_range(first, path);
            }
        }
        selection.select_path(path);

        return true;
    }

    bool on_button_released(Gdk.EventButton b) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_button_released");
        Gtk.TreePath path;
        Gtk.TreeViewColumn column;

        int cell_x;
        int cell_y;

        tree_view.get_path_at_pos((int) b.x, (int) b.y, out path, 
                                  out column, out cell_x, out cell_y);

       // The check for cell_x == 0 and cell_y == 0 is here since for whatever reason, this 
       // function is called when we drop some clips onto the timeline.  We only need to mess with 
       // the selection if we've actually clicked in the tree view, but I cannot find a way to 
       // guarantee this, since the coordinates that the Gdk.EventButton structure and the 
       // (cell_x, cell_y) pair give are always 0, 0 when this happens. 
       // I can assume that clicking on 0, 0 exactly is next to impossible, so I feel this
       // strange check is okay.

        if (path == null ||
            (cell_x == 0 && cell_y == 0)) {
            selection_changed(false);
            return true;
        }

        bool shift_pressed = (b.state & Gdk.ModifierType.SHIFT_MASK) != 0;
        bool control_pressed = (b.state & Gdk.ModifierType.CONTROL_MASK) != 0;

        if (!control_pressed &&
            !shift_pressed) {
            if (selection.path_is_selected(path))
                selection.unselect_all();
        }
        selection.select_path(path);
        selection_changed(true);

        return true;
    }

    void on_cursor_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_cursor_changed");
        selection_changed(has_selection());
    }

    public void unselect_all() {
        selection.unselect_all();
        selection_changed(false);
    }

    public override void drag_data_received(Gdk.DragContext context, int x, int y,
                                            Gtk.SelectionData selection_data, uint drag_info,
                                            uint time) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_drag_data_received");
        string[] a = selection_data.get_uris();
        Gtk.drag_finish(context, true, false, time);

        project.create_clip_importer(null, false, 0);

        foreach (string s in a) {
            string filename;
            try {
                filename = GLib.Filename.from_uri(s);
            } catch (GLib.ConvertError e) { continue; }
            project.importer.add_file(filename);
        }
        project.importer.start();
    }

    
    void on_drag_data_get(Gtk.Widget w, Gdk.DragContext context, Gtk.SelectionData data, 
                            uint info, uint time) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_drag_data_get");
        string uri;
        string[] uri_array = new string[0];

        foreach (string s in files_dragging) {
            try {
                uri = GLib.Filename.to_uri(s);
            } catch (GLib.ConvertError e) {
                uri = s;
                warning("Cannot get URI for %s! (%s)\n", s, e.message);
            }
            uri_array += uri;
        }
        data.set_uris(uri_array);

        Gtk.drag_set_icon_default(context);
    }

    int get_selected_rows(out Gtk.TreeModel model, out GLib.List<Gtk.TreePath> paths) {
        paths = selection.get_selected_rows(out model);
        return (int) paths.length();
    }

    void on_drag_begin(Gdk.DragContext c) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_drag_begin");
        Gtk.TreeModel model;
        GLib.List<Gtk.TreePath> paths;
        if (get_selected_rows(out model, out paths) > 0) {
            bool set_pixbuf = false;
            files_dragging.clear();
            foreach (Gtk.TreePath t in paths) {
                Gtk.TreeIter iter;
                model.get_iter(out iter, t);

                string filename;
                model.get(iter, ColumnType.FILENAME, out filename, -1);
                files_dragging.add(filename);

                if (!set_pixbuf) {
                    Gdk.Pixbuf pixbuf;
                    model.get(iter, ColumnType.THUMBNAIL, out pixbuf, -1);

                    Gtk.drag_set_icon_pixbuf(c, pixbuf, 0, 0);
                    set_pixbuf = true;
                }
            }
        }
    }

    void add_column(ColumnType c) {
        Gtk.TreeViewColumn column = new Gtk.TreeViewColumn();
        Gtk.CellRenderer renderer;

        if (c == ColumnType.THUMBNAIL) {
            renderer = new Gtk.CellRendererPixbuf();
        } else {
            renderer = new Gtk.CellRendererText();
            Gdk.Color color = parse_color("#FFF");
            renderer.set("foreground-gdk", &color);
        }

        column.pack_start(renderer, true);
        column.set_resizable(true);

        if (c == ColumnType.THUMBNAIL)
            column.add_attribute(renderer, "pixbuf", tree_view.append_column(column) - 1);
        else
            column.add_attribute(renderer, "text", tree_view.append_column(column) - 1);
    }

    void update_iter(Gtk.TreeIter it, Model.ClipFile clip_file) {
        Gdk.Pixbuf icon;

        if (clip_file.is_online()) {
            if (clip_file.thumbnail == null)
                icon = (clip_file.is_of_type(Model.MediaType.VIDEO) ? 
                                                        default_video_icon : default_audio_icon);
            else {
                icon = clip_file.thumbnail;
            }
        } else {
            icon = default_error_icon;
        }

        list_store.set(it, ColumnType.THUMBNAIL, icon,
                            ColumnType.NAME, isolate_filename(clip_file.filename),
                            ColumnType.DURATION, time_provider.get_time_string(clip_file.length),
                            ColumnType.FILENAME, clip_file.filename, -1);
    }

    int get_clipfile_position(Model.ClipFile f) {
        if (sort_mode == SortMode.ABC) {
            Model.ClipFile compare;
            int i = 0;

            while ((compare = project.get_clipfile(i)) != null) {
                if (stricmp(f.filename, compare.filename) <= 0)
                    return i;
                i++;
            }
        }
        return -1;
    }

    void on_clipfile_added(Model.ClipFile f) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_file_added");
        Gtk.TreeIter it;

        if (find_clipfile(f, out it) >= 0) {
            list_store.remove(it);
        } else {
            if (num_clipfiles == 0) {
                if (label != null) {
                    remove(label);
                }
                add(tree_view);
                tree_view.show();
            }
            num_clipfiles++;
        }

        int pos = get_clipfile_position(f);
        if (pos == -1)
            list_store.append(out it);
        else
            list_store.insert(out it, pos);

        update_iter(it, f);
    }

    int find_clipfile(Model.ClipFile f, out Gtk.TreeIter iter) {
        Gtk.TreeModel model = tree_view.get_model();

        bool b = model.get_iter_first(out iter);

        int i = 0;
        while (b) {
            string filename;
            model.get(iter, ColumnType.FILENAME, out filename);

            if (filename == f.filename)
                return i;

            i++;
            b = model.iter_next(ref iter);
        }
        return -1;
    }

    public void on_clipfile_updated(Model.ClipFile f) {
        Gtk.TreeIter iter;

        if (find_clipfile(f, out iter) >= 0)
            update_iter(iter, f);
    }

    bool remove_row(out Gtk.TreeIter it) {
        bool b = list_store.remove(it);
        num_clipfiles--;
        if (num_clipfiles == 0) {
            remove(tree_view);
            if (label != null) {
                add(label);
                label.show();
            }
        }
        return b;
    }

    void remove_all_rows() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "remove_all_rows");
        Gtk.TreeModel model = tree_view.get_model();
        Gtk.TreeIter iter;

        bool b = model.get_iter_first(out iter);

        while (b) {
            b = remove_row(out iter);
        }
    }

    void delete_row(Gtk.TreeModel model, Gtk.TreePath path) {
        Gtk.TreeIter it;
        list_store.get_iter(out it, path);

        string filename;
        model.get(it, ColumnType.FILENAME, out filename, -1);

        if (project.clipfile_on_track(filename)) {
            if (DialogUtils.delete_cancel("Clip is in use.  Delete anyway?") !=
                Gtk.ResponseType.YES)
                return;
        }

        project.remove_clipfile(filename);

        if (Path.get_dirname(filename) == project.get_audio_path()) {
            if (DialogUtils.delete_cancel("Delete clip from disk?  This action is not undoable.")
                                                == Gtk.ResponseType.YES) {
                if (FileUtils.unlink(filename) != 0) {
                    project.error_occurred("Could not delete %s", filename);
                }
            }
        }
        remove_row(out it);
    }

    public bool has_selection() {
        Gtk.TreeModel model;
        GLib.List<Gtk.TreePath> paths;
        return get_selected_rows(out model, out paths) != 0;
    }

    public void delete_selection() {
        Gtk.TreeModel model;
        GLib.List<Gtk.TreePath> paths;

        if (get_selected_rows(out model, out paths) > 0) {
            for (int i = (int) paths.length() - 1; i >= 0; i--)
                delete_row(model, paths.nth_data(i));
        }
    }
}
