/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Gee;

class LombardFetcherCompletion : Model.FetcherCompletion {
    Model.Project project;
    
    public LombardFetcherCompletion(Model.Project project) {
        base();
        this.project = project;
    }
    
    public override void complete(Model.ClipFetcher fetch) {
        base.complete(fetch);
        project.add_clipfile(fetch.clipfile);
        project.append(fetch.clipfile);
    }
}

class App : Gtk.Window {
    Gtk.DrawingArea drawing_area;
    
    Model.VideoProject project;
    TimeLine timeline;
    ClipLibraryView library;
    StatusBar status_bar;
    
    Gtk.HPaned h_pane;
    
    Gtk.ScrolledWindow library_scrolled;
    Gtk.ScrolledWindow timeline_scrolled;
    Gtk.Adjustment h_adjustment;
    
    double prev_adjustment_lower;
    double prev_adjustment_upper;
    
    Gtk.Action export_action;
    Gtk.Action delete_action;
    Gtk.Action delete_lift_action;
    Gtk.Action cut_action;
    Gtk.Action cut_lift_action;
    Gtk.Action copy_action;
    Gtk.Action paste_action;
    Gtk.Action paste_overwrite_action;
    Gtk.Action split_at_playhead_action;
    Gtk.Action trim_to_playhead_action;
    Gtk.Action revert_to_original_action;
    Gtk.Action clip_properties_action;
    Gtk.Action zoom_to_project_action;
    
    Gtk.ToggleAction library_view_action;
    
    Model.LibraryImporter importer;
    
    bool done_zoom = false;
    
    Gtk.VBox vbox = null;
    Gtk.MenuBar menubar;
    
    string project_filename;

    public static const string NAME = "lombard";
   
    const Gtk.ActionEntry[] entries = {
        { "File", null, "_File", null, null, null },
        { "Open", Gtk.STOCK_OPEN, "_Open...", null, null, on_open },
        { "Save", Gtk.STOCK_SAVE, null, null, null, on_save },
        { "SaveAs", Gtk.STOCK_SAVE_AS, "Save _As...", null, null, on_save_as },
        { "Play", Gtk.STOCK_MEDIA_PLAY, "_Play / Pause", "space", null, on_play_pause },
        { "Export", null, "_Export...", "<Control>E", null, on_export },
        { "Quit", Gtk.STOCK_QUIT, null, null, null, Gtk.main_quit },

        { "Edit", null, "_Edit", null, null, null },
        { "Cut", Gtk.STOCK_CUT, null, null, null, on_cut },
        { "CutLift", null, "Lift Cut", "<Shift><Control>X", null, on_cut_lift },
        { "Copy", Gtk.STOCK_COPY, null, null, null, on_copy },
        { "Paste", Gtk.STOCK_PASTE, null, null, null, on_paste },
        { "PasteOver", null, "Paste Overwrite", 
          "<Shift><Control>V", null, on_paste_over },
        { "Delete", Gtk.STOCK_DELETE, null, "Delete", null, on_delete },
        { "DeleteLift", null, "Lift Delete", "<Shift>Delete", null, on_delete_lift },
        { "SplitAtPlayhead", null, "Split at Playhead", "<Control>P", null, on_split_at_playhead },
        { "TrimToPlayhead", null, "Trim to Playhead", "<Control>T", null, on_trim_to_playhead },
        { "RevertToOriginal", Gtk.STOCK_REVERT_TO_SAVED, "Revert to Original",
          "<Control>R", null, on_revert_to_original },
        { "ClipProperties", Gtk.STOCK_PROPERTIES, "Properties", "<Alt>Return", 
            null, on_clip_properties },

        { "View", null, "_View", null, null, null },
        { "ZoomIn", Gtk.STOCK_ZOOM_IN, "Zoom _in", "equal", null, on_zoom_in },
        { "ZoomOut", Gtk.STOCK_ZOOM_OUT, "Zoom _out", "minus", null, on_zoom_out },
        { "ZoomProject", null, "Fit to Window", "<Shift>Z", null, on_zoom_to_project },

        { "Go", null, "_Go", null, null, null },
        { "Start", Gtk.STOCK_GOTO_FIRST, "_Start", "Home", null, on_go_start },
        { "End", Gtk.STOCK_GOTO_LAST, "_End", "End", null, on_go_end },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, null, null, null, on_about }
    };

    const Gtk.ToggleActionEntry[] check_actions = { 
        { "Library", null, "Library", "F9", null, on_view_library, true }
    };
    
    const string ui = """
<ui>
  <menubar name="MenuBar">
    <menu name="FileMenu" action="File">
      <menuitem name="FileOpen" action="Open"/>
      <menuitem name="FileSave" action="Save"/>
      <menuitem name="FileSaveAs" action="SaveAs"/>
      <separator/>
      <menuitem name="FilePlay" action="Play"/>
      <separator/>
      <menuitem name="FileExport" action="Export"/>
      <menuitem name="FileQuit" action="Quit"/>
    </menu>
    <menu name="EditMenu" action="Edit">
      <menuitem name="EditDelete" action="Delete"/>
      <menuitem name="EditDeleteLift" action="DeleteLift"/>
      <menuitem naem="EditCut" action="Cut"/>
      <menuitem name="EditCutLift" action="CutLift"/>
      <menuitem name="EditCopy" action="Copy"/>
      <menuitem name="EditPaste" action="Paste"/>
      <menuitem name="EditPasteOver" action="PasteOver"/>
      <separator/>
      <menuitem name="ClipSplitAtPlayhead" action="SplitAtPlayhead"/>
      <menuitem name="ClipTrimToPlayhead" action="TrimToPlayhead"/>
      <menuitem name="ClipRevertToOriginal" action="RevertToOriginal"/>
      <menuitem name="ClipViewProperties" action="ClipProperties"/>
    </menu>
    <menu name="ViewMenu" action="View">
        <menuitem name="ViewZoomIn" action="ZoomIn"/>
        <menuitem name="ViewZoomOut" action="ZoomOut"/>
        <separator />
        <menuitem name="ViewZoomProject" action="ZoomProject"/>
    </menu>
    <menu name="GoMenu" action="Go">
      <menuitem name="GoStart" action="Start"/>
      <menuitem name="GoEnd" action="End"/>
    </menu>
    <menu name="HelpMenu" action="Help">
      <menuitem name="HelpAbout" action="About"/>
    </menu>
  </menubar>
  
  <popup name="ClipContextMenu">
    <menuitem name="ClipContextCut" action="Cut"/>
    <menuitem name="ClipContextCopy" action="Copy"/>
    <menuitem name="ClipContextRevert" action="RevertToOriginal"/>
    <menuitem name="ClipContextProperties" action="ClipProperties"/>
  </popup>
</ui>
""";

    const DialogUtils.filter_description_struct[] filters = {
        { "Lombard Project Files", Model.Project.LOMBARD_FILE_EXTENSION },
        { "Fillmore Project Files", Model.Project.FILLMORE_FILE_EXTENSION }
    };

    const DialogUtils.filter_description_struct[] export_filters = {
        { "Ogg Files", "ogg" }
    };

    public App(string? project_file) {
        set_default_size(600, 500);
        project_filename = project_file;
        
        drawing_area = new Gtk.DrawingArea();
        drawing_area.realize += on_drawing_realize;
        drawing_area.modify_bg(Gtk.StateType.NORMAL, parse_color("#000"));
        
        Gtk.ActionGroup group = new Gtk.ActionGroup("main");
        group.add_actions(entries, this);
        
        Gtk.ActionGroup view_library_action_group = new Gtk.ActionGroup("viewlibrary");
        view_library_action_group.add_toggle_actions(check_actions, this);
  
        export_action = group.get_action("Export");
        delete_action = group.get_action("Delete");
        delete_lift_action = group.get_action("DeleteLift");
        cut_action = group.get_action("Cut");
        cut_lift_action = group.get_action("CutLift");
        copy_action = group.get_action("Copy");
        paste_action = group.get_action("Paste");
        paste_overwrite_action = group.get_action("PasteOver");
        split_at_playhead_action = group.get_action("SplitAtPlayhead");
        trim_to_playhead_action = group.get_action("TrimToPlayhead");
        revert_to_original_action = group.get_action("RevertToOriginal");
        clip_properties_action = group.get_action("ClipProperties");
        zoom_to_project_action = group.get_action("ZoomProject");
        library_view_action = (Gtk.ToggleAction) view_library_action_group.get_action("Library");

        Gtk.UIManager manager = new Gtk.UIManager();
        manager.insert_action_group(group, 0);
        try {
            manager.add_ui_from_string(ui, -1);
        } catch (Error e) { error("%s", e.message); }

        manager.insert_action_group(view_library_action_group, 1);
        
        uint view_merge_id = manager.new_merge_id();
        manager.add_ui(view_merge_id, "/MenuBar/ViewMenu/ViewZoomProject",
                    "Library", "Library", Gtk.UIManagerItemType.MENUITEM, false);

        
        menubar = (Gtk.MenuBar) get_widget(manager, "/MenuBar");

        project = new Model.VideoProject(project_filename);
        project.name_changed += set_project_name;
        project.load_error += on_load_error;
        project.load_success += on_load_success;
        project.error_occurred += do_error_dialog;
        // TODO: this is a hack to deal with project loading.  Lombard assumes one video
        // track and one audio track.  It was non-trivial to delete and recreate tracks.
        project.clear_tracks = false;

        project.add_track(new Model.VideoTrack(project));
        project.add_track(new Model.AudioTrack(project, "Audio Track"));
        
        timeline = new TimeLine(project);
        timeline.selection_changed += on_timeline_selection_changed;
        timeline.track_changed += on_track_changed;
        project.position_changed += on_position_changed;
        timeline.context_menu = (Gtk.Menu) manager.get_widget("/ClipContextMenu");

        library = new ClipLibraryView(project);
        library.selection_changed += on_library_selection_changed;
        
        status_bar = new StatusBar(project);
        
        library_scrolled = new Gtk.ScrolledWindow(null, null);
        library_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        library_scrolled.add_with_viewport(library);

        toggle_library(true);
        
        add_accel_group(manager.get_accel_group());
        
        set_project_name(null);
        Gtk.drag_dest_set(timeline, Gtk.DestDefaults.ALL, drag_target_entries, 
                                                                  Gdk.DragAction.COPY);
        Gtk.drag_dest_set(library, Gtk.DestDefaults.ALL, drag_target_entries, Gdk.DragAction.COPY);
        
        timeline.drag_data_received += on_drag_data_received;
        library.drag_data_received += on_drag_data_received;
        
        destroy += Gtk.main_quit;
        
        update_menu();
        show_all();
    }
    
    void toggle_library(bool showing) {
        if (vbox == null) {
            vbox = new Gtk.VBox(false, 0);
            vbox.pack_start(menubar, false, false, 0);

            h_pane = new Gtk.HPaned();        
            h_pane.set_position(300);
            
            if (showing) {
                h_pane.add1(library_scrolled);
                h_pane.add2(drawing_area);            
            } else
                h_pane.add2(drawing_area);
            vbox.pack_start(h_pane, true, true, 0);
            
            vbox.pack_start(new Gtk.HSeparator(), false, false, 0);
            vbox.pack_start(status_bar, false, false, 0);

            timeline_scrolled = new Gtk.ScrolledWindow(null, null);
            timeline_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
            timeline_scrolled.add_with_viewport(timeline);

            h_adjustment = timeline_scrolled.get_hadjustment();
            h_adjustment.changed += on_adjustment_changed;
            prev_adjustment_lower = h_adjustment.get_lower();
            prev_adjustment_upper = h_adjustment.get_upper();
            vbox.pack_start(timeline_scrolled, false, false, 0);
            
            add(vbox);
        } else {
            if (showing)
                h_pane.add1(library_scrolled);
            else
                h_pane.remove(library_scrolled);
        }
        show_all();
    }
    
    void on_drawing_realize() {
        project.load(project_filename);
        project.set_output_widget(drawing_area);
    }
    
    void on_adjustment_changed(Gtk.Adjustment a) {
        if (prev_adjustment_upper != a.get_upper() ||
            prev_adjustment_lower != a.get_lower()) {

            prev_adjustment_lower = a.get_lower();
            prev_adjustment_upper = a.get_upper();
            
            if (done_zoom)
                on_position_changed();
        }
        done_zoom = false;
    }
    
    public void set_project_name(string? filename) {
        if (filename == null)
            set_title ("Unsaved Project - %s".printf(App.NAME));
        else {
            string dir = Path.get_dirname(filename);
            string name = Path.get_basename(filename);
            string home_path = GLib.Environment.get_home_dir();

            if (dir == ".")
                dir = GLib.Environment.get_current_dir();

            if (dir.has_prefix(home_path))
                dir = "~" + dir.substring(home_path.length);
            set_title("%s (%s) - %s".printf(name, dir, App.NAME));
        }
    }

    public void do_error_dialog(string message) {
        DialogUtils.error("Error", message);
    }
    
    public void on_load_error(string message) {
        do_error_dialog(message);
    }
    
    public void on_load_success() {
        on_zoom_to_project();
    }
    
    // Loader code
    
    public void load_file(string name, Model.LibraryImporter im) {
        if (get_file_extension(name) == Model.Project.LOMBARD_FILE_EXTENSION)
            load_project(name);
        else {
            im.add_file(name);
        }
    }
    
    void create_clip_importer(bool timeline_add) {
        if (timeline_add)
            importer = new Model.TimelineImporter(project);
        else
            importer = new Model.LibraryImporter(project);            
        importer.started += on_importer_started;       
    }
    
    void on_open() {
        Gtk.FileChooserDialog d = new Gtk.FileChooserDialog("Open Files", this, 
                                                            Gtk.FileChooserAction.OPEN,
                                                            Gtk.STOCK_CANCEL, 
                                                            Gtk.ResponseType.CANCEL,
                                                            Gtk.STOCK_OPEN, 
                                                            Gtk.ResponseType.ACCEPT, null);
        Gtk.FileFilter filter = new Gtk.FileFilter();
        filter.set_name("Project Files");
        filter.add_pattern(Model.Project.LOMBARD_FILE_FILTER);
        
        d.add_filter(filter);
        
        filter = new Gtk.FileFilter();
        filter.set_name("All Files");
        filter.add_pattern("*");
        
        d.add_filter(filter);

        create_clip_importer(false);

        d.set_select_multiple(true);
        if (d.run() == Gtk.ResponseType.ACCEPT) {
            foreach (string s in d.get_filenames()) {
                string str;
                try {
                    str = GLib.Filename.from_uri(s);
                } catch (GLib.ConvertError e) { str = s; }
                load_file(str, importer);
            }
        }                                                    
        d.destroy();
        importer.start();
    }

    void do_save_dialog() {
        string filename;
        if (DialogUtils.save(this, "Save Project", filters, out filename)) {
            project.save(filename);
        }
    }
    
    void on_save_as() {
        do_save_dialog();
    }
    
    void on_save() {
        if (project.project_file == null)
            do_save_dialog();
        else save_project(null);
    }
    
    public void load_project(string filename) {
        project.load(filename);
    }
    
    void save_project(string? filename) {
        project.save(filename);
    }          
    
    const float SCROLL_MARGIN = 0.05f;
    
    // Scroll if necessary so that horizontal position xpos is visible in the window.
    void scroll_to(int xpos) {
        float margin = project.is_playing() ? 0.0f : SCROLL_MARGIN;
        int page_size = (int) h_adjustment.page_size;
        
        if (xpos < h_adjustment.value + page_size * margin)  // too far left
            h_adjustment.set_value(xpos - h_adjustment.page_size / 3);
        else if (xpos > h_adjustment.value + page_size * (1 - margin))   // too far right
            h_adjustment.set_value(xpos - h_adjustment.page_size * 2 / 3);
    }
    
    void scroll_toward_center(int xpos) {
        int cursor_pos = xpos - (int) h_adjustment.value;
        
        // Move the cursor position toward the center of the window.  We compute
        // the remaining distance and move by its square root; this results in
        // a smooth decelerating motion.
        int page_size = (int) h_adjustment.page_size;
        int diff = page_size / 2 - cursor_pos;
        int d = sign(diff) * (int) Math.sqrt(diff.abs());
        cursor_pos += d;
        
        h_adjustment.set_value(xpos - cursor_pos);
    }
    
    public void on_split_at_playhead() {
        project.split_at_playhead();
    }
    
    public void on_trim_to_playhead() {
        project.trim_to_playhead();
    }
    
    public void on_revert_to_original() {
        Model.Clip clip = timeline.get_selected_clip();
        Model.Track? track = track_from_clip_file(clip.clipfile);
        if (track != null) {
            track.revert_to_original(clip);
        }
    }
  
    public void on_clip_properties() {
        timeline.show_clip_properties(this);
    }
    
    public void on_position_changed() {
        int xpos = timeline.time_to_xpos(project.get_position());
        scroll_to(xpos);
        if (project.is_playing())
            scroll_toward_center(xpos);  
        update_menu();
    }
    
    public void on_track_changed() {
        update_menu();
    }
    
    void on_importer_started(Model.ClipImporter i, int num) {
        new MultiFileProgress(this, num, "Import", i);
    }

    Model.Track? track_from_clip_file(Model.ClipFile cf) {
        if (cf.video_caps != null) {
            return project.find_video_track();
        } else if (cf.audio_caps != null) {
            return project.find_audio_track();
        } else {
            return null;
        }
    }
        
    public void on_drag_data_received(Gtk.Widget w, Gdk.DragContext context, int x, int y,
                                            Gtk.SelectionData selection_data, uint drag_info,
                                            uint time) {
        string[] a = selection_data.get_uris();
        Gtk.drag_finish(context, true, false, time);
        
        create_clip_importer(w == timeline);

        foreach (string s in a) {
            string filename;
            try {
                filename = GLib.Filename.from_uri(s);
            } catch (GLib.ConvertError e) { continue; }
            load_file(filename, importer);
        }
        importer.start();
        present();
    }

    void update_menu() {
        bool b = timeline.is_clip_selected();
        
        delete_action.set_sensitive(b || timeline.gap_selected() || library.has_selection());
        delete_lift_action.set_sensitive(b || timeline.gap_selected());
        cut_action.set_sensitive(b);
        cut_lift_action.set_sensitive(b);
        copy_action.set_sensitive(b);
        paste_action.set_sensitive(timeline.clipboard_clip != null);
        paste_overwrite_action.set_sensitive(timeline.clipboard_clip != null);
        
        revert_to_original_action.set_sensitive(b && timeline.get_selected_clip().is_trimmed());
        clip_properties_action.set_sensitive(b);
        
        b = project.playhead_on_clip();
        split_at_playhead_action.set_sensitive(b);
        
        bool dir;
        trim_to_playhead_action.set_sensitive(project.can_trim(out dir));
        
        zoom_to_project_action.set_sensitive(project.get_length() != 0);
    
        export_action.set_sensitive(project.can_export());
    }
    
    public void on_timeline_selection_changed(bool selected) { 
        if (selected)
            library.unselect_all();
        update_menu();
    }
    
    public void on_library_selection_changed(bool selected) {
        if (selected)
            timeline.unselect_clip();
        update_menu();
    }
    
    // constants from gdkkeysyms.h
    const int GDK_LEFT = 0xff51;
    const int GDK_UP = 0xff52;
    const int GDK_RIGHT = 0xff53;
    const int GDK_DOWN = 0xff54;
    const int GDK_MINUS = 0x002d;
    const int GDK_PLUS = 0x003d;
    const int GDK_SHIFT_LEFT = 0xffe1;
    const int GDK_SHIFT_RIGHT = 0xffe2;
    const int GDK_ESCAPE = 0xff1b;
    const int GDK_CONTROL_LEFT = 0xffe3;
    const int GDK_CONTROL_RIGHT = 0xffe4;
    
    // We must use a key press event to handle the up arrow and down arrow keys,
    // since GTK does not allow them to be used as accelerators.
    public override bool key_press_event(Gdk.EventKey event) {
        switch (event.keyval) {
            case GDK_UP:
                project.go_previous();
                return true;
            case GDK_DOWN:
                project.go_next();
                return true;
            case GDK_LEFT:
                project.go_previous_frame();
                return true;
            case GDK_RIGHT:
                project.go_next_frame();
                return true;
            case GDK_SHIFT_LEFT:
            case GDK_SHIFT_RIGHT:
                timeline.set_shift_pressed(true);
                return true;
            case GDK_ESCAPE:
                timeline.escape_pressed();
                return true;
            case GDK_CONTROL_LEFT:
            case GDK_CONTROL_RIGHT:
                timeline.set_control_pressed(true);
                return true;
        }
        return base.key_press_event(event);
    }
    
    public override bool key_release_event(Gdk.EventKey event) {
        switch (event.keyval) {
            case GDK_SHIFT_LEFT:
            case GDK_SHIFT_RIGHT:
                timeline.set_shift_pressed(false);
                return true;
            case GDK_CONTROL_LEFT:
            case GDK_CONTROL_RIGHT:
                timeline.set_control_pressed(false);
                return true;
        }
        return base.key_release_event(event);
    }
    
    void on_view_library() {
        toggle_library(library_view_action.get_active());
    }
    
    void on_zoom_in() {
        timeline.zoom(0.1f);
        done_zoom = true;
    }
    
    void on_zoom_out() {
        timeline.zoom(-0.1f);
        done_zoom = true;
    }
    
    void on_zoom_to_project() {
        //The 12.0 is just a magic number to completely get rid of the scrollbar on this operation
        timeline.zoom_to_project(h_adjustment.page_size - 12.0);
    }
    
    // File commands
    
    void on_play_pause() {
        if (project.is_playing())
            project.pause();
        else {
        // TODO: we should be calling play() here, which in turn would call 
        // do_play(Model.PlayState).  This is not currently how the code is organized.
        // This is part of a checkin that is already large, so putting this off for another
        // checkin for ease of testing.
            project.do_play(Model.PlayState.PLAYING);
        }
    }
    
    void on_export() {
        string filename;
        if (DialogUtils.save(this, "Export", export_filters, out filename)) {
            MultiFileProgress export_dialog = new MultiFileProgress(this, 1, "Export", project);
            project.start_export(filename);
        }
    }
    
    // Edit commands
    
    void on_delete() {
        if (library.has_selection())
            library.delete_selection();
        else
            timeline.delete_selection(true);
    }
    
    void on_delete_lift() {
        timeline.delete_selection(false);
    }
    
    void on_cut() {
        timeline.do_cut(true);
    }
    
    void on_cut_lift() {
        timeline.do_cut(false);
    }
    
    void on_copy() {
        timeline.do_copy();
    }
    
    void on_paste() {
        timeline.paste(false);
    }
    
    void on_paste_over() {
        timeline.paste(true);
    }

    // Go commands
    
    void on_go_start() { project.go_start(); }
    
    void on_go_end() { project.go_end(); }

    // Help commands
    
    void on_about() {
        Gtk.show_about_dialog(this,
          "version", "0.1",
          "comments", "a video editor",
          "copyright", "(c) 2009 yorba"
        );
    }
}

// Versions of Gnonlin before 0.10.10.3 hang when seeking near the end of a video.
const string MIN_GNONLIN = "0.10.10.3";
    
void main(string[] args) {
    Gtk.init(ref args);
    GLib.Environment.set_application_name("lombard");
    
    Gst.init(ref args);

    if (args.length > 2) {
        stderr.printf("usage: %s [project-file]\n", args[0]);
        return;
    }
    string project_file = args.length > 1 ? args[1] : null;
    
    Gst.Registry registry = Gst.Registry.get_default();
    Gst.Plugin gnonlin = registry.find_plugin("gnonlin");
    if (gnonlin == null) {
        stderr.puts("This program requires Gnonlin, which is not installed.  Exiting.\n");
        return;
    }
    
    string version = gnonlin.get_version();
    if (!version_at_least(version, MIN_GNONLIN)) {
        stderr.printf(
            "You have Gnonlin version %s, but this program requires version %s.  Exiting.\n",
            version, MIN_GNONLIN);
        return;
    }
    
    string str = GLib.Environment.get_variable("LOMBARD_DEBUG");
    debug_enabled = (str != null && (str[0] >= '1'));

    new App(project_file);
    Gtk.main();
}

