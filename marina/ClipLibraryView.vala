/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class ClipLibraryView : Gtk.EventBox {
    Model.Project project;
    Gtk.TreeView tree_view;
    Gtk.TreeSelection selection;
    Gtk.Label label;
    Gtk.ListStore list_store;
    int num_clipfiles;
    Gee.ArrayList<string> files_dragging = new Gee.ArrayList<string>();

    enum ColumnType {
        NAME,
        DURATION,
        FILENAME
    }

    public signal void selection_changed(bool selected);

    public ClipLibraryView(Model.Project p) {
        project = p;
        
        list_store = new Gtk.ListStore(3, typeof (string), typeof (string), typeof (string), -1);
        tree_view = new Gtk.TreeView.with_model(list_store);
        
        add_column();
        add_column();
        
        num_clipfiles = 0;
        label = new Gtk.Label("Drag clips here.");
        label.modify_fg(Gtk.StateType.NORMAL, parse_color("#fff"));
        
        modify_bg(Gtk.StateType.NORMAL, parse_color("#444"));
        tree_view.modify_base(Gtk.StateType.NORMAL, parse_color("#444"));

        tree_view.set_headers_visible(false);
        project.clipfile_added += on_clipfile_added;
        
        Gtk.drag_source_set(tree_view, Gdk.ModifierType.BUTTON1_MASK, drag_target_entries,
                                    Gdk.DragAction.COPY);                    
        tree_view.drag_begin += on_drag_begin;
        tree_view.drag_data_get += on_drag_data_get;
        tree_view.cursor_changed += on_cursor_changed;
        
        selection = tree_view.get_selection();
        selection.set_mode(Gtk.SelectionMode.MULTIPLE);

        add(label);
    }
    
    void on_cursor_changed() {
        selection_changed(has_selection());
    }
    
    public void unselect_all() {
        selection.unselect_all();
        selection_changed(false);
    }
    
    void on_drag_data_get(Gtk.Widget w, Gdk.DragContext context, Gtk.SelectionData data, 
                            uint info, uint time) {
        string uri;
        string[] uri_array = new string[0];
        
        foreach (string s in files_dragging) {
            try {
                uri = GLib.Filename.to_uri(s);
            } catch (GLib.ConvertError e) {
                uri = s;        
                print_debug("Cannot get URI for %s! (%s)\n".printf(s, e.message));
            }
            uri_array += uri;
        }
        data.set_uris(uri_array);                     
    }
    
    bool get_selected_rows(out Gtk.TreeModel model, 
                                                    out GLib.List<Gtk.TreePath> paths) {
        paths = selection.get_selected_rows(out model);
        return paths.length() != 0;
    }
    
    void on_drag_begin(Gdk.DragContext c) {
        Gtk.TreeModel model;
        GLib.List<Gtk.TreePath> paths;
        if (get_selected_rows(out model, out paths)) {        
            files_dragging.clear();
            foreach (Gtk.TreePath t in paths) {
                Gtk.TreeIter iter;
                model.get_iter(out iter, t);
                
                string filename;
                model.get(iter, ColumnType.FILENAME, out filename, -1);
                files_dragging.add(filename);
            }
        }
    }
    
    void add_column() {
        Gtk.TreeViewColumn column = new Gtk.TreeViewColumn();
        
        Gtk.CellRendererText renderer = new Gtk.CellRendererText();
        Gdk.Color c = parse_color("#FFF");
        renderer.set("foreground-gdk", &c);        
        
        column.pack_start(renderer, true);
        column.set_resizable(true);
        column.add_attribute(renderer, "text", tree_view.append_column(column) - 1);
    }
    
    void on_clipfile_added(Model.ClipFile f) {
        Gtk.TreeIter it;
        
        if (num_clipfiles == 0) {
            remove(label);
            add(tree_view);
            tree_view.show();
        }
        num_clipfiles++;
        
        list_store.append(out it);
        
        TimeCode t = {};
        t = project.get_clip_time(f);
        
        list_store.set(it, ColumnType.NAME, isolate_filename(f.filename), 
                            ColumnType.DURATION, t.to_string(), 
                            ColumnType.FILENAME, f.filename, -1);        
    }
    
    void delete_row(Gtk.TreeModel model, Gtk.TreePath path) {
        Gtk.TreeIter it;
        list_store.get_iter(out it, path);
        
        string filename;
        model.get(it, 2, out filename, -1);
        
        if (project.remove_clipfile(filename)) { 
            list_store.remove(it);
            num_clipfiles--;
            if (num_clipfiles == 0) {
                remove(tree_view);
                add(label);
                label.show();
            }
        } else {
            Gtk.Dialog d = create_error_dialog("Error", 
                            "Cannot remove clip file that exists on a track!");
            d.run();
            d.destroy();
        }
    }
    
    public bool has_selection() {
        Gtk.TreeModel model;
        GLib.List<Gtk.TreePath> paths;
        return get_selected_rows(out model, out paths);
    }
    
    public void delete_selection() {
        Gtk.TreeModel model;
        GLib.List<Gtk.TreePath> paths;
        
        if (get_selected_rows(out model, out paths)) { 
            foreach (Gtk.TreePath p in paths)
                delete_row(model, paths.nth_data(0));
        }
    }
}
