/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

int debug_level;
const OptionEntry[] options = {
    { "debug-level", 0, 0, OptionArg.INT, &debug_level,
        "Control amount of diagnostic information",
        "[0 (minimal),5 (maximum)]" },
    { null }
};

class App : Gtk.Window, TransportDelegate {
    Gtk.DrawingArea drawing_area;

    Model.VideoProject project;
    View.VideoOutput video_output;
    View.AudioOutput audio_output;
    View.OggVorbisExport export_connector;

    TimeLine timeline;
    ClipLibraryView library;
    View.StatusBar status_bar;

    Gtk.HPaned h_pane;

    Gtk.ScrolledWindow library_scrolled;
    Gtk.ScrolledWindow timeline_scrolled;
    Gtk.Adjustment h_adjustment;

    double prev_adjustment_lower;
    double prev_adjustment_upper;

    Gtk.ActionGroup main_group;

    int64 center_time = -1;

    Gtk.VBox vbox = null;
    Gtk.MenuBar menubar;
    Gtk.UIManager manager;

    string project_filename;
    Gee.ArrayList<string> load_errors;
    bool loading;

    public const string NAME = "Lombard";
    const string LibraryToggle = "Library";

    const Gtk.ActionEntry[] entries = {
        { "Project", null, "_Project", null, null, null },
        { "Open", Gtk.STOCK_OPEN, "_Open...", null, null, on_open },
        { "Save", Gtk.STOCK_SAVE, null, null, null, on_save },
        { "SaveAs", Gtk.STOCK_SAVE_AS, "Save _As...", "<Shift><Control>S", null, on_save_as },
        { "Play", Gtk.STOCK_MEDIA_PLAY, "_Play / Pause", "space", null, on_play_pause },
        { "Export", null, "_Export...", "<Control>E", null, on_export },
        { "Quit", Gtk.STOCK_QUIT, null, null, null, on_quit },

        { "Edit", null, "_Edit", null, null, null },
        { "Undo", Gtk.STOCK_UNDO, null, "<Control>Z", null, on_undo },
        { "Cut", Gtk.STOCK_CUT, null, null, null, on_cut },
        { "Copy", Gtk.STOCK_COPY, null, null, null, on_copy },
        { "Paste", Gtk.STOCK_PASTE, null, null, null, on_paste },
        { "Delete", Gtk.STOCK_DELETE, null, "Delete", null, on_delete },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, null, "<Control>A", null, on_select_all },
        { "SplitAtPlayhead", null, "_Split at Playhead", "<Control>P", null, on_split_at_playhead },
        { "TrimToPlayhead", null, "Trim to Play_head", "<Control>H", null, on_trim_to_playhead },
        { "ClipProperties", Gtk.STOCK_PROPERTIES, "Properti_es", "<Alt>Return", 
            null, on_clip_properties },

        { "View", null, "_View", null, null, null },
        { "ZoomIn", Gtk.STOCK_ZOOM_IN, "Zoom _In", "<Control>plus", null, on_zoom_in },
        { "ZoomOut", Gtk.STOCK_ZOOM_OUT, "Zoom _Out", "<Control>minus", null, on_zoom_out },
        { "ZoomProject", null, "Fit to _Window", "<Shift>Z", null, on_zoom_to_project },

        { "Go", null, "_Go", null, null, null },
        { "Start", Gtk.STOCK_GOTO_FIRST, "_Start", "Home", null, on_go_start },
        { "End", Gtk.STOCK_GOTO_LAST, "_End", "End", null, on_go_end },

        { "Help", null, "_Help", null, null, null },
        { "Contents", Gtk.STOCK_HELP, "_Contents", "F1", 
            "More information on Lombard", on_help_contents},
        { "About", Gtk.STOCK_ABOUT, null, null, null, on_about },
        { "SaveGraph", null, "Save _Graph", null, "Save graph", on_save_graph }
    };

    const Gtk.ToggleActionEntry[] check_actions = { 
        { LibraryToggle, null, "_Library", "F9", null, on_view_library, true },
        { "Snap", null, "_Snap to Clip Edges", null, null, on_snap, true }
    };

    const string ui = """
<ui>
  <menubar name="MenuBar">
    <menu name="Project" action="Project">
      <menuitem name="Open" action="Open"/>
      <menuitem name="Save" action="Save"/>
      <menuitem name="SaveAs" action="SaveAs"/>
      <separator/>
      <menuitem name="Play" action="Play"/>
      <separator/>
      <menuitem name="Export" action="Export"/>
      <menuitem name="Quit" action="Quit"/>
    </menu>
    <menu name="EditMenu" action="Edit">
      <menuitem name="EditUndo" action="Undo"/>
      <separator/>
      <menuitem name="EditCut" action="Cut"/>
      <menuitem name="EditCopy" action="Copy"/>
      <menuitem name="EditPaste" action="Paste"/>
      <menuitem name="EditDelete" action="Delete"/>
      <separator/>
      <menuitem name="EditSelectAll" action="SelectAll"/>
      <separator/>
      <menuitem name="ClipSplitAtPlayhead" action="SplitAtPlayhead"/>
      <menuitem name="ClipTrimToPlayhead" action="TrimToPlayhead"/>
      <separator/>
      <menuitem name="ClipViewProperties" action="ClipProperties"/>
    </menu>
    <menu name="ViewMenu" action="View">
        <menuitem name="ViewLibrary" action="Library"/>
        <separator/>
        <menuitem name="ViewZoomIn" action="ZoomIn"/>
        <menuitem name="ViewZoomOut" action="ZoomOut"/>
        <menuitem name="ViewZoomProject" action="ZoomProject"/>
        <separator/>
        <menuitem name="Snap" action="Snap"/>
    </menu>
    <menu name="GoMenu" action="Go">
      <menuitem name="GoStart" action="Start"/>
      <menuitem name="GoEnd" action="End"/>
    </menu>
    <menu name="HelpMenu" action="Help">
      <menuitem name="HelpContents" action="Contents"/>
      <separator/>
      <menuitem name="HelpAbout" action="About"/>
      <menuitem name="SaveGraph" action="SaveGraph"/>
    </menu>
  </menubar>

  <popup name="ClipContextMenu">
    <menuitem name="ClipContextCut" action="Cut"/>
    <menuitem name="ClipContextCopy" action="Copy"/>
    <separator/>
    <menuitem name="ClipContextProperties" action="ClipProperties"/>
  </popup>
  <popup name="LibraryContextMenu">
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

    public App(string? project_file) throws Error {
        try {
            set_icon_from_file(
                AppDirs.get_resources_dir().get_child("lombard_icon.png").get_path());
        } catch (GLib.Error e) {
            warning("Could not load application icon: %s", e.message);
        }
        
        if (debug_level > -1) {
            set_logging_level((Logging.Level)debug_level);
        }
        ClassFactory.set_transport_delegate(this);
        set_default_size(600, 500);
        project_filename = project_file;

        load_errors = new Gee.ArrayList<string>();
        drawing_area = new Gtk.DrawingArea();
        drawing_area.realize += on_drawing_realize;
        drawing_area.modify_bg(Gtk.StateType.NORMAL, parse_color("#000"));

        main_group = new Gtk.ActionGroup("main");
        main_group.add_actions(entries, this);
        main_group.add_toggle_actions(check_actions, this);

        manager = new Gtk.UIManager();
        manager.insert_action_group(main_group, 0);
        try {
            manager.add_ui_from_string(ui, -1);
        } catch (Error e) { error("%s", e.message); }

        menubar = (Gtk.MenuBar) get_widget(manager, "/MenuBar");

        project = new Model.VideoProject(project_filename);
        project.snap_to_clip = true;
        project.name_changed += set_project_name;
        project.load_error += on_load_error;
        project.load_complete += on_load_complete;
        project.error_occurred += do_error_dialog;
        project.undo_manager.undo_changed += on_undo_changed;
        project.media_engine.post_export += on_post_export;
        project.playstate_changed += on_playstate_changed;

        audio_output = new View.AudioOutput(project.media_engine.get_project_audio_caps());
        project.media_engine.connect_output(audio_output);

        timeline = new TimeLine(project, project.time_provider,
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
        timeline.selection_changed += on_timeline_selection_changed;
        timeline.track_changed += on_track_changed;
        timeline.drag_data_received += on_drag_data_received;
        timeline.size_allocate += on_timeline_size_allocate;
        project.media_engine.position_changed += on_position_changed;
        project.media_engine.callback_pulse += on_callback_pulse;
        ClipView.context_menu = (Gtk.Menu) manager.get_widget("/ClipContextMenu");
        ClipLibraryView.context_menu = (Gtk.Menu) manager.get_widget("/LibraryContextMenu");

        library = new ClipLibraryView(project, project.time_provider, "Drag clips here.",
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
        library.selection_changed += on_library_selection_changed;
        library.drag_data_received += on_drag_data_received;

        status_bar = new View.StatusBar(project, project.time_provider, TimeLine.BAR_HEIGHT);

        library_scrolled = new Gtk.ScrolledWindow(null, null);
        library_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        library_scrolled.add_with_viewport(library);

        toggle_library(true);

        Gtk.MenuItem? save_graph = (Gtk.MenuItem?) 
            get_widget(manager, "/MenuBar/HelpMenu/SaveGraph");

        // TODO: only destroy it if --debug is not specified on the command line
        // or conversely, only add it if --debug is specified on the command line
        if (save_graph != null) {
            save_graph.destroy();
        }

        add_accel_group(manager.get_accel_group());

        on_undo_changed(false);

        delete_event += on_delete_event;

        if (project_filename == null) {
            default_track_set();
            on_load_complete();
        }

        update_menu();
        show_all();
    }

    void default_track_set() {
        project.add_track(new Model.VideoTrack(project));
        project.add_track(new Model.AudioTrack(project, "Audio Track"));
    }

    bool on_delete_event() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_delete_event");
        on_quit();
        return true;
    }

    void on_quit() {
        if (project.undo_manager.is_dirty) {
            switch (DialogUtils.save_close_cancel(this, null, "Save changes before closing?")) {
                case Gtk.ResponseType.ACCEPT:
                    if (!do_save()) {
                        return;
                    }
                    break;
                case Gtk.ResponseType.CLOSE:
                    break;
                case Gtk.ResponseType.DELETE_EVENT: // when user presses escape.
                case Gtk.ResponseType.CANCEL:
                    return;
                default:
                    assert(false);
                    break;
            }
        }

        Gtk.main_quit();
    }

    void toggle_library(bool showing) {
        if (vbox == null) {
            vbox = new Gtk.VBox(false, 0);
            vbox.pack_start(menubar, false, false, 0);

            Gtk.VPaned v_pane = new Gtk.VPaned();
            v_pane.set_position(290);

            h_pane = new Gtk.HPaned();
            h_pane.set_position(300);
            h_pane.child2_resize = 1;
            h_pane.child1_resize = 0;

            if (showing) {
                h_pane.add1(library_scrolled);
                h_pane.add2(drawing_area);
            } else {
                h_pane.add2(drawing_area);
            }
            h_pane.child2.size_allocate += on_library_size_allocate;
            v_pane.add1(h_pane);

            timeline_scrolled = new Gtk.ScrolledWindow(null, null);
            timeline_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            timeline_scrolled.add_with_viewport(timeline);

            Gtk.VBox timeline_vbox = new Gtk.VBox(false, 0);
            timeline_vbox.pack_start(status_bar, false, false, 0);
            timeline_vbox.pack_start(timeline_scrolled, true, true, 0);
            v_pane.add2(timeline_vbox);

            v_pane.child1_resize = 1;
            v_pane.child2_resize = 0;

            h_adjustment = timeline_scrolled.get_hadjustment();
            h_adjustment.changed += on_adjustment_changed;
            prev_adjustment_lower = h_adjustment.get_lower();
            prev_adjustment_upper = h_adjustment.get_upper();

            vbox.pack_start(v_pane, true, true, 0);

            add(vbox);
        } else {
            project.library_visible = showing;
            if (showing) {
                h_pane.add1(library_scrolled);
            } else {
                h_pane.remove(library_scrolled);
            }
        }
        show_all();
    }

    void on_drawing_realize() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_drawing_realize");
        loading = true;
        project.load(project_filename);
        try {
            video_output = new View.VideoOutput(drawing_area);
            project.media_engine.connect_output(video_output);
        } catch (Error e) {
            do_error_dialog("Could not create video output", e.message);
        }
    }

    void on_adjustment_changed(Gtk.Adjustment a) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_adjustment_changed");
        if (prev_adjustment_upper != a.get_upper() ||
            prev_adjustment_lower != a.get_lower()) {

            prev_adjustment_lower = a.get_lower();
            prev_adjustment_upper = a.get_upper();
        }
    }

    void on_drag_data_received(Gtk.Widget w, Gdk.DragContext context, int x, int y,
                                Gtk.SelectionData selection_data, uint drag_info, uint time) {
        present();
    }

    public void set_project_name(string? filename) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "set_project_name");
        set_title(project.get_file_display_name());
    }

    public static void do_error_dialog(string message, string? minor_message) {
        DialogUtils.error(message, minor_message);
    }

    public void on_load_error(string message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_error");
        load_errors.add(message);
    }

    public void on_load_complete() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_complete");
        queue_draw();
        if (project.find_video_track() == null) {
            project.add_track(new Model.VideoTrack(project));
        }

        project.media_engine.pipeline.set_state(Gst.State.PAUSED);
        h_pane.set_position(h_pane.allocation.width - project.library_width);
        Gtk.ToggleAction action = main_group.get_action(LibraryToggle) as Gtk.ToggleAction;
        if (action.get_active() != project.library_visible) {
            action.set_active(project.library_visible);
        }

        action = main_group.get_action("Snap") as Gtk.ToggleAction;
        if (action.get_active() != project.snap_to_clip) {
            action.set_active(project.snap_to_clip);
        }

        if (project.library_visible) {
            if (h_pane.child1 != library_scrolled) {
                h_pane.add1(library_scrolled);
            }
        } else {
            if (h_pane.child1 == library_scrolled) {
                h_pane.remove(library_scrolled);
            }
        }

        if (load_errors.size > 0) {
            string message = "";
            foreach (string s in load_errors) {
                message = message + s + "\n";
            }
            do_error_dialog("An error occurred loading the project.", message);
        }
        loading = false;
    }

    void on_library_size_allocate(Gdk.Rectangle rectangle) {
        if (!loading && h_pane.child1 == library_scrolled) {
            project.library_width = rectangle.width;
        }
    }

    // Loader code

    public void load_file(string name, Model.LibraryImporter im) {
        if (get_file_extension(name) == Model.Project.LOMBARD_FILE_EXTENSION ||
            get_file_extension(name) == Model.Project.FILLMORE_FILE_EXTENSION)
            load_project(name);
        else {
            try {
                im.add_file(name);
            } catch (Error e) {
                do_error_dialog("Error loading file", e.message);
            }
        }
    }

    void on_open() {
        load_errors.clear();
        GLib.SList<string> filenames;
        if (DialogUtils.open(this, filters, true, true, out filenames)) {
            project.create_clip_importer(null, false, 0, false);
            project.importer.started += on_importer_started;
            try {
                foreach (string s in filenames) {
                    string str;
                    try {
                        str = GLib.Filename.from_uri(s);
                    } catch (GLib.ConvertError e) { str = s; }
                    load_file(str, project.importer);
                }
                project.importer.start();
            } catch (Error e) {
                do_error_dialog("Could not open file", e.message);
            }
        }
    }

    void on_importer_started(Model.ClipImporter i, int num) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_importer_started");
        new MultiFileProgress(this, num, "Import", i);
    }

    bool do_save_dialog() {
        string? filename = project.get_project_file();
        bool create_directory = filename == null;
        if (DialogUtils.save(this, "Save Project", create_directory, filters, ref filename)) {
            project.save(filename);
            return true;
        }
        return false;
    }

    void on_save_as() {
        do_save_dialog();
    }

    void on_save() {
        do_save();
    }

    bool do_save() {
        if (project.get_project_file() != null) {
            project.save(null);
            return true;
        }
        return do_save_dialog();
    }

    public void load_project(string filename) {
        loading = true;

        try {
            project.media_engine.disconnect_output(video_output);
            video_output = new View.VideoOutput(drawing_area);
            project.media_engine.connect_output(video_output);
        } catch (Error e) {
            do_error_dialog("Could not create video output", e.message);
        }

        project.load(filename);

    }

    const float SCROLL_MARGIN = 0.05f;

    void scroll_toward_center(int xpos) {
        int cursor_pos = xpos - (int) h_adjustment.value;

        // Move the cursor position toward the center of the window.  We compute
        // the remaining distance and move by its square root; this results in
        // a smooth decelerating motion.
        int page_size = (int) h_adjustment.page_size;
        int diff = page_size / 2 - cursor_pos;
        int d = sign(diff) * (int) Math.sqrt(diff.abs());
        cursor_pos += d;

        int x = int.max(0, xpos - cursor_pos);
        int max_value = (int)(h_adjustment.upper - timeline_scrolled.allocation.width);
        if (x > max_value) {
            x = max_value;
        }
        h_adjustment.set_value(x);

        h_adjustment.set_value(x);
    }

    public void on_split_at_playhead() {
        project.split_at_playhead();
    }

    public void on_trim_to_playhead() {
        project.trim_to_playhead();
    }

    public void on_clip_properties() {
        Fraction? frames_per_second = null;
        project.get_framerate_fraction(out frames_per_second);
        if (library.has_selection()) {
            Gee.ArrayList<string> files = library.get_selected_files();
            if (files.size == 1) {
                string file_name = files.get(0);
                Model.ClipFile? clip_file = project.find_clipfile(file_name);
                DialogUtils.show_clip_properties(this, null, clip_file, frames_per_second);
            }
        } else {
            Gee.ArrayList<ClipView> clips = timeline.selected_clips;
            if (clips.size == 1) {
                ClipView clip_view = clips.get(0);
                DialogUtils.show_clip_properties(this, clip_view, null, frames_per_second);
            }
        }
    }

    public void on_position_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_position_changed");
        update_menu();
    }

    void on_callback_pulse() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_callback_pulse");
        if (project.transport_is_playing()) {
            scroll_toward_center(project.time_provider.time_to_xpos(project.media_engine.position));
        }
        timeline.queue_draw();
    }

    public void on_track_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_changed");
        update_menu();
    }

    void update_menu() {
        bool library_selected = library.has_selection();
        bool clip_selected = timeline.is_clip_selected();
        bool stopped = is_stopped();
        bool clip_is_trimmed = false;
        bool playhead_on_clip = project.playhead_on_clip();
        bool dir;
        bool can_trim = project.can_trim(out dir);
        bool one_selected = false;
        if (library_selected) {
            one_selected = library.get_selected_files().size == 1;
        } else if (clip_selected) {
            one_selected = timeline.selected_clips.size == 1;
        }

        if (clip_selected) {
            foreach (ClipView clip_view in timeline.selected_clips) {
                clip_is_trimmed = clip_view.clip.is_trimmed();
                if (clip_is_trimmed) {
                    break;
                }
            }
        }
        // File menu
        set_sensitive_group(main_group, "Open", stopped);
        set_sensitive_group(main_group, "Save", stopped);
        set_sensitive_group(main_group, "SaveAs", stopped);
        set_sensitive_group(main_group, "Export", project.can_export());

        // Edit Menu
        set_sensitive_group(main_group, "Undo", stopped && project.undo_manager.can_undo);
        set_sensitive_group(main_group, "Delete", stopped && (clip_selected || library_selected));
        set_sensitive_group(main_group, "Cut", stopped && clip_selected);
        set_sensitive_group(main_group, "Copy", stopped && clip_selected);
        set_sensitive_group(main_group, "Paste", stopped && timeline.clipboard.clips.size > 0);
        set_sensitive_group(main_group, "ClipProperties", one_selected);

        set_sensitive_group(main_group, "SplitAtPlayhead", stopped && playhead_on_clip);
        set_sensitive_group(main_group, "TrimToPlayhead", stopped && can_trim);
        
        // View Menu
        set_sensitive_group(main_group, "ZoomProject", project.get_length() != 0);

    }

    public void on_timeline_selection_changed(bool selected) { 
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_timeline_selection_changed");
        if (selected)
            library.unselect_all();
        update_menu();
    }

    public void on_library_selection_changed(bool selected) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_library_selection_changed");
        if (selected) {
            timeline.deselect_all_clips();
            timeline.queue_draw();
        }
        update_menu();
    }

    // We must use a key press event to handle the up arrow and down arrow keys,
    // since GTK does not allow them to be used as accelerators.
    public override bool key_press_event(Gdk.EventKey event) {
        switch (event.keyval) {
            case KeySyms.KP_Enter:
            case KeySyms.Return:
                if ((event.state & GDK_SHIFT_ALT_CONTROL_MASK) != 0)
                    return base.key_press_event(event);
                on_go_start();
                break;
            case KeySyms.Left:
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    project.go_previous();
                } else {
                    project.go_previous_frame();
                }
                break;
            case KeySyms.Right:
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    project.go_next();
                } else {
                    project.go_next_frame();
                }
                break;
            case KeySyms.KP_Add:
            case KeySyms.equal:
            case KeySyms.plus:
                on_zoom_in();
                break;
            case KeySyms.KP_Subtract:
            case KeySyms.minus:
            case KeySyms.underscore:
                on_zoom_out();
                break;
            default:
                return base.key_press_event(event);
        }
        return true;
    }

    void on_snap() {
        project.snap_to_clip = !project.snap_to_clip;
    }

    void on_view_library() {
        Gtk.ToggleAction action = main_group.get_action(LibraryToggle) as Gtk.ToggleAction;
        toggle_library(action.get_active());
    }

    int64 get_zoom_center_time() {
        return project.transport_get_position();
    }

    void do_zoom(float increment) {
        center_time = get_zoom_center_time();
        timeline.zoom(increment);
    }

    void on_zoom_in() {
        do_zoom(0.1f);
    }

    void on_zoom_out() {
        do_zoom(-0.1f);
    }

    void on_zoom_to_project() {
        timeline.zoom_to_project(h_adjustment.page_size);
    }

    void on_timeline_size_allocate(Gdk.Rectangle rectangle) {
        if (center_time != -1) {
            int new_center_pixel = project.time_provider.time_to_xpos(center_time);
            int page_size = (int)(h_adjustment.get_page_size() / 2);
            h_adjustment.clamp_page(new_center_pixel - page_size, new_center_pixel + page_size);
            center_time = -1;
        }
    }

    void set_sensitive_group(Gtk.ActionGroup group, string group_path, bool sensitive) {
        Gtk.Action action = group.get_action(group_path);
        action.set_sensitive(sensitive);
    }

    // File commands

    void on_play_pause() {
        if (project.transport_is_playing())
            project.media_engine.pause();
        else {
        // TODO: we should be calling play() here, which in turn would call 
        // do_play(Model.PlayState).  This is not currently how the code is organized.
        // This is part of a checkin that is already large, so putting this off for another
        // checkin for ease of testing.
            project.media_engine.do_play(PlayState.PLAYING);
        }
    }

    void on_export() {
        string filename = null;
        if (DialogUtils.save(this, "Export", false, export_filters, ref filename)) {
            new MultiFileProgress(this, 1, "Export", project.media_engine);
            project.media_engine.disconnect_output(audio_output);
            project.media_engine.disconnect_output(video_output);
            try {
                export_connector = new View.OggVorbisExport(
                    View.MediaConnector.MediaTypes.Audio | View.MediaConnector.MediaTypes.Video,
                    filename, project.media_engine.get_project_audio_export_caps());
                project.media_engine.connect_output(export_connector);
                project.media_engine.start_export(filename);
            } catch (Error e) {
                do_error_dialog("Could not export file", e.message);
            }
        }
    }

    void on_post_export(bool canceled) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_post_export");
        project.media_engine.disconnect_output(export_connector);
        project.media_engine.connect_output(audio_output);
        project.media_engine.connect_output(video_output);
        if (canceled) {
            GLib.FileUtils.remove(export_connector.get_filename());
        }
        export_connector = null;
    }

    // Edit commands

    void on_undo() {
        project.undo();
    }

    void on_delete() {
        if (library.has_selection())
            library.delete_selection();
        else
            timeline.delete_selection();
    }

    void on_cut() {
        timeline.do_cut();
    }

    void on_copy() {
        timeline.do_copy();
    }

    void on_paste() {
        timeline.paste();
    }

    void on_playstate_changed(PlayState playstate) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_playstate_changed");
        if (playstate == PlayState.STOPPED) {
            update_menu();
        }
    }

    void on_undo_changed(bool can_undo) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_undo_changed");
        Gtk.MenuItem? undo = (Gtk.MenuItem?) get_widget(manager, "/MenuBar/EditMenu/EditUndo");
        assert(undo != null);
        undo.set_label("_Undo " + project.undo_manager.get_undo_title());
        set_sensitive_group(main_group, "Undo", is_stopped() && project.undo_manager.can_undo);
    }

    void on_select_all() {
        if (library.has_selection()) {
            library.select_all();
        } else {
            timeline.select_all();
        }
    }

    // Go commands

    void on_go_start() { project.go_start(); }

    void on_go_end() { project.go_end(); }

    // Help commands

    void on_help_contents() {
        try {
            Gtk.show_uri(null, "http://trac.yorba.org/wiki/UsingLombard0.1", 0);
        } catch (GLib.Error e) {
        }
    }

    void on_about() {
        Gtk.show_about_dialog(this,
            "version", "%1.1lf".printf(project.get_version()),
            "comments", "A video editor",
            "copyright", "Copyright 2009-2010 Yorba Foundation",
            "website", "http://www.yorba.org",
            "license", project.get_license(),
            "website-label", "Visit the Yorba web site",
            "authors", project.authors
        );
    }

    void on_save_graph() {
        project.print_graph(project.media_engine.pipeline, "save_graph");
    }

    // Transport Delegate methods
    bool is_recording() {
        return project.transport_is_recording();
    }

    bool is_playing() {
        return project.transport_is_playing();
    }

    bool is_stopped() {
        return !(is_playing() || is_recording());
    }
}

extern const string _PROGRAM_NAME;

void main(string[] args) {
    debug_level = -1;
    OptionContext context = new OptionContext(
        " [project file] - Create and edit movies");
    context.add_main_entries(options, null);
    context.add_group(Gst.init_get_option_group());

    try {
        context.parse(ref args);
    } catch (GLib.Error arg_error) {
        stderr.printf("%s\nRun 'lombard --help' for a full list of available command line options.", 
            arg_error.message);
        return;
    }
    Gtk.init(ref args);

    try {
        GLib.Environment.set_application_name("Lombard");

        AppDirs.init(args[0], _PROGRAM_NAME);
        Gst.init(ref args);

        if (args.length > 2) {
            stderr.printf("usage: %s [project-file]\n", args[0]);
            return;
        }

        string? project_file = null;
        if (args.length > 1) {
            project_file = args[1];
            try {
                project_file = GLib.Filename.from_uri(project_file);
            } catch (GLib.Error e) { }
        }

        string str = GLib.Environment.get_variable("LOMBARD_DEBUG");
        debug_enabled = (str != null && (str[0] >= '1'));
        ClassFactory.set_class_factory(new ClassFactory());
        View.MediaEngine.can_run();

        new App(project_file);
        Gtk.main();
    } catch (Error e) {
        App.do_error_dialog("Could not launch application", "%s.".printf(e.message));
    }
}

