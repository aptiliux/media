/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

extern const string _PROGRAM_NAME;
bool do_print_graph = false;
int debug_level;

const OptionEntry[] options = {
    { "print-graph", 0, 0, OptionArg.NONE, &do_print_graph,
        "Show Print Graph in help menu", null },
    { "debug-level", 0, 0, OptionArg.INT, &debug_level,
        "Control amount of diagnostic information",
        "[0 (minimal),5 (maximum)]" },
    { null }
};

class Recorder : Gtk.Window, TransportDelegate {
    public Model.AudioProject project;
    public TimeLine timeline;
    View.ClickTrack click_track;
    HeaderArea header_area;
    ClipLibraryView library;
    Model.TimeSystem provider;
    Gtk.Adjustment h_adjustment;
    Gtk.HPaned timeline_library_pane;
    Gtk.ScrolledWindow library_scrolled;
    Gtk.ScrolledWindow timeline_scrolled;
    int cursor_pos = -1;
    int64 center_time = -1;
    bool loading;
    const int scroll_speed = 8;

    Gtk.ActionGroup main_group;

    Gtk.ToggleToolButton play_button;
    Gtk.ToggleToolButton record_button;
    Gtk.UIManager manager;
    // TODO: Have a MediaExportConnector that extends MediaConnector rather than concrete type.
    View.OggVorbisExport audio_export;
    View.AudioOutput audio_output;
    Gee.ArrayList<string> load_errors;

    public const string NAME = "Fillmore";
    const string LibraryToggle = "Library";
    const Gtk.ActionEntry[] entries = {
        { "File", null, "_File", null, null, null },
        { "Open", Gtk.STOCK_OPEN, "_Open...", null, "Open a project", on_project_open },
        { "NewProject", Gtk.STOCK_NEW, "_New...", null, "Create new project", on_project_new },
        { "Save", Gtk.STOCK_SAVE, "_Save", "<Control>S", "Save project", on_project_save },
        { "SaveAs", Gtk.STOCK_SAVE_AS, "Save _As...", "<Control><Shift>S", 
            "Save project with new name", on_project_save_as },
        { "Export", Gtk.STOCK_JUMP_TO, "_Export...", "<Control>E", null, on_export },
        { "Settings", Gtk.STOCK_PROPERTIES, "Se_ttings", "<Control><Alt>Return", null, on_properties },
        { "Quit", Gtk.STOCK_QUIT, null, null, null, on_quit },

        { "Edit", null, "_Edit", null, null, null },
        { "Undo", Gtk.STOCK_UNDO, null, "<Control>Z", null, on_undo },
        { "Cut", Gtk.STOCK_CUT, null, null, null, on_cut },
        { "Copy", Gtk.STOCK_COPY, null, null, null, on_copy },
        { "Paste", Gtk.STOCK_PASTE, null, null, null, on_paste },
        { "Delete", Gtk.STOCK_DELETE, null, "Delete", null, on_delete },
        { "SplitAtPlayhead", null, "_Split at Playhead", "<Control>P", null, on_split_at_playhead },
        { "TrimToPlayhead", null, "Trim to Play_head", "<Control>H", null, on_trim_to_playhead },
        { "JoinAtPlayhead", null, "_Join at Playhead", "<Control>J", null, on_join_at_playhead },
        { "ClipProperties", Gtk.STOCK_PROPERTIES, "Properti_es", "<Alt>Return", 
            null, on_clip_properties },
            
        { "View", null, "_View", null, null, null },
        { "ZoomIn", Gtk.STOCK_ZOOM_IN, "Zoom _In", "<Control>plus", null, on_zoom_in },
        { "ZoomOut", Gtk.STOCK_ZOOM_OUT, "Zoom _Out", "<Control>minus", null, on_zoom_out },
        { "ZoomProject", null, "Fit to _Window", "<Shift>Z", null, on_zoom_to_project },

        { "Track", null, "_Track", null, null, null },
        { "NewTrack", Gtk.STOCK_ADD, "_New...", "<Control><Shift>N", 
            "Create new track", on_track_new },
        { "Rename", null, "_Rename...", null, "Rename Track", on_track_rename },
        { "DeleteTrack", null, "_Delete", "<Control><Shift>Delete", 
            "Delete track", on_track_remove },
            
        { "Help", null, "_Help", null, null, null },
        { "Contents", Gtk.STOCK_HELP, "_Contents", "F1", 
            "More information on Fillmore", on_help_contents},
        { "About", Gtk.STOCK_ABOUT, null, null, null, on_about },
        { "SaveGraph", null, "Save _Graph", null, "Save graph", on_save_graph },

        { "Rewind", Gtk.STOCK_MEDIA_PREVIOUS, "Rewind", "Home", "Go to beginning", on_rewind },
        { "End", Gtk.STOCK_MEDIA_NEXT, "End", "End", "Go to end", on_end }
    };

    const Gtk.ToggleActionEntry[] toggle_entries = {
        { "Play", Gtk.STOCK_MEDIA_PLAY, null, "space", "Play", on_play },
        { "Record", Gtk.STOCK_MEDIA_RECORD, null, "r", "Record", on_record },
        { LibraryToggle, null, "_Library", "F9", null, on_view_library, true }
    };

    const string ui = """
<ui>
  <menubar name="MenuBar">
    <menu name="FileMenu" action="File">
      <menuitem name="FileNew" action="NewProject" />
      <menuitem name="FileOpen" action="Open" />
      <menuitem name="FileSave" action="Save" />
      <menuitem name="FileSaveAs" action="SaveAs" />
      <separator />
      <menuitem name="FileExport" action="Export" />
      <separator />
      <menuitem name="FileProperty" action="Settings" />
      <separator />
      <menuitem name="FileQuit" action="Quit"/>
    </menu>
    <menu name="EditMenu" action="Edit">
      <menuitem name="EditUndo" action="Undo" />
      <separator />
      <menuitem name="EditCut" action="Cut" />
      <menuitem name="EditCopy" action="Copy" />
      <menuitem name="EditPaste" action="Paste" />
      <menuitem name="EditDelete" action="Delete" />
      <separator/>
      <menuitem name="ClipSplitAtPlayhead" action="SplitAtPlayhead" />
      <menuitem name="ClipTrimToPlayhead" action="TrimToPlayhead" />
      <menuitem name="ClipJoinAtPlayhead" action="JoinAtPlayhead" />
      <separator />
      <menuitem name="ClipViewProperties" action="ClipProperties" />
    </menu>
    <menu name="ViewMenu" action="View">
        <separator name="AfterZoom" />
        <menuitem name="ViewZoomIn" action="ZoomIn" />
        <menuitem name="ViewZoomOut" action="ZoomOut" />
        <menuitem name="ViewZoomProject" action="ZoomProject"/>
    </menu>
    <menu name="TrackMenu" action="Track">
      <menuitem name="TrackNew" action="NewTrack" />
      <menuitem name="TrackRename" action="Rename" />
      <menuitem name="TrackDelete" action="DeleteTrack" />
    </menu>
    <menu name="HelpMenu" action="Help">
      <menuitem name="HelpContents" action="Contents" />
      <separator />
      <menuitem name="HelpAbout" action="About" />
      <menuitem name="SaveGraph" action="SaveGraph" />
    </menu>
  </menubar>
  <popup name="ClipContextMenu">
    <menuitem name="Cut" action="Cut" />
    <menuitem name="Copy" action="Copy" />
    <separator />
    <menuitem name="ClipContextProperties" action="ClipProperties" />
  </popup>
  <popup name="LibraryContextMenu">
    <menuitem name="ClipContextProperties" action="ClipProperties" />
  </popup>
  <toolbar name="Toolbar">
    <toolitem name="New" action="NewTrack" />
    <separator/>
    <toolitem name="Rewind" action="Rewind" />
    <toolitem name="End" action="End" />
    <toolitem name="Play" action="Play" />
    <toolitem name="Record" action="Record"/>
  </toolbar>
  <accelerator name="Rewind" action="Rewind" />
  <accelerator name="End" action="End" />
  <accelerator name="Play" action="Play" />
  <accelerator name="Record" action="Record" />
</ui>
""";

    const DialogUtils.filter_description_struct[] filters = {
        { "Fillmore Project Files", Model.Project.FILLMORE_FILE_EXTENSION },
        { "Lombard Project Files", Model.Project.LOMBARD_FILE_EXTENSION }
    };

    const DialogUtils.filter_description_struct[] export_filters = {
        { "Ogg Files", "ogg" }
    };

    public signal void finished_closing(bool project_did_close);

    public Recorder(string? project_file) throws Error {
        ClassFactory.set_transport_delegate(this);
        GLib.DirUtils.create(get_fillmore_directory(), 0777);
        load_errors = new Gee.ArrayList<string>();
        try {
            set_icon_from_file(
                AppDirs.get_resources_dir().get_child("fillmore_icon.png").get_path());
        } catch (GLib.Error e) {
            warning("Could not load application icon: %s", e.message);
        }
        project = new Model.AudioProject(project_file);
        provider = new Model.BarBeatTimeSystem(project);
        
        project.media_engine.callback_pulse += on_callback_pulse;
        project.media_engine.post_export += on_post_export;
        project.media_engine.position_changed += on_position_changed;

        project.load_error += on_load_error;
        project.name_changed += on_name_changed;
        project.undo_manager.dirty_changed += on_dirty_changed;
        project.undo_manager.undo_changed += on_undo_changed;
        project.error_occurred += on_error_occurred;
        project.playstate_changed += on_playstate_changed;
        project.track_added += on_track_added;
        project.track_removed += on_track_removed;
        project.load_complete += on_load_complete;
        project.closed += on_project_close;

        audio_output = new View.AudioOutput(project.media_engine.get_project_audio_caps());
        project.media_engine.connect_output(audio_output);
        click_track = new View.ClickTrack(project.media_engine, project);
        set_position(Gtk.WindowPosition.CENTER);
        title = "Fillmore";
        set_default_size(800, 400);

        main_group = new Gtk.ActionGroup("main");
        main_group.add_actions(entries, this);
        main_group.add_toggle_actions(toggle_entries, this);

        manager = new Gtk.UIManager();
        manager.insert_action_group(main_group, 0);
        try {
            manager.add_ui_from_string(ui, -1);
        } catch (Error e) { error("%s", e.message); }

        uint view_merge_id = manager.new_merge_id();
        manager.add_ui(view_merge_id, "/MenuBar/ViewMenu/AfterZoom",
                    LibraryToggle, LibraryToggle, Gtk.UIManagerItemType.MENUITEM, true);

        Gtk.MenuBar menubar = (Gtk.MenuBar) get_widget(manager, "/MenuBar");
        Gtk.Toolbar toolbar = (Gtk.Toolbar) get_widget(manager, "/Toolbar");
        play_button = (Gtk.ToggleToolButton) get_widget(manager, "/Toolbar/Play");
        record_button = (Gtk.ToggleToolButton) get_widget(manager, "/Toolbar/Record");
        on_undo_changed(false);

        library = new ClipLibraryView(project, provider, null);
        library.selection_changed += on_library_selection_changed;
        library.drag_data_received += on_drag_data_received;

        timeline = new TimeLine(project, provider);
        timeline.track_changed += on_track_changed;
        timeline.drag_data_received += on_drag_data_received;
        timeline.size_allocate += on_timeline_size_allocate;
        timeline.selection_changed += on_timeline_selection_changed;
        
        ClipView.context_menu = (Gtk.Menu) manager.get_widget("/ClipContextMenu");
        ClipLibraryView.context_menu = (Gtk.Menu) manager.get_widget("/LibraryContextMenu");
        update_menu();

        library_scrolled = new Gtk.ScrolledWindow(null, null);
        library_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        library_scrolled.add_with_viewport(library);

        Gtk.HBox hbox = new Gtk.HBox(false, 0);
        header_area = new HeaderArea(this, provider, TimeLine.RULER_HEIGHT);
        hbox.pack_start(header_area, false, false, 0);

        timeline_scrolled = new Gtk.ScrolledWindow(null, null);
        timeline_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
        timeline_scrolled.add_with_viewport(timeline);
        hbox.pack_start(timeline_scrolled, true, true, 0);
        h_adjustment = timeline_scrolled.get_hadjustment();

        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(menubar, false, false, 0);
        vbox.pack_start(toolbar, false, false, 0);
        timeline_library_pane = new Gtk.HPaned();
        timeline_library_pane.set_position(project.library_width);
        timeline_library_pane.add1(hbox);
        timeline_library_pane.child1_resize = 1;
        timeline_library_pane.add2(library_scrolled);
        timeline_library_pane.child2_resize = 0;
        timeline_library_pane.child1.size_allocate += on_library_size_allocate;

        vbox.pack_start(timeline_library_pane, true, true, 0);
        add(vbox);

        Gtk.MenuItem? save_graph = (Gtk.MenuItem?) 
            get_widget(manager, "/MenuBar/HelpMenu/SaveGraph");

        if (!do_print_graph && save_graph != null) {
            save_graph.destroy();
        }

        add_accel_group(manager.get_accel_group());
        timeline.grab_focus();
        delete_event += on_delete_event;
        loading = true;
        project.load(project_file);
        if (project_file == null) {
            default_track_set();
            loading = false;
        }
        project.media_engine.pipeline.set_state(Gst.State.PAUSED);
    }

    void default_track_set() {
        project.add_track(new Model.AudioTrack(project, get_default_track_name()));
        project.tracks[0].set_selected(true);
    }

    static int default_track_number_compare(void *a, void *b) {
        string* s1 = (string *) a;
        string* s2 = (string *) b;
        int i = -1;
        int j = -1;
        s1->scanf("track %d", &i);
        s2->scanf("track %d", &j);
        assert(i > 0);
        assert(j > 0);
        if (i == j) {
            return 0;
        } else if (i < j) {
            return -1;
        } else {
            return 1;
        }
    }

    public string get_default_track_name() {
        List<string> default_track_names = new List<string>();
        foreach(Model.Track track in project.tracks) {
            if (track.display_name.has_prefix("track ")) {
                default_track_names.append(track.display_name);
            }
        }
        default_track_names.sort(default_track_number_compare);

        int i = 1;
        foreach(string s in default_track_names) {
            string track_name = "track %d".printf(i);
            if (s != track_name) {
                return track_name;
            }
            ++i;
        }
        return "track %d".printf(i);
    }

    Gtk.Widget get_widget(Gtk.UIManager manager, string name) {
        Gtk.Widget widget = manager.get_widget(name);
        if (widget == null)
            error("can't find widget");
        return widget;
    }

    void set_sensitive_group(Gtk.ActionGroup group, string group_path, bool sensitive) {
        Gtk.Action action = group.get_action(group_path);
        action.set_sensitive(sensitive);
    }

    void on_track_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_changed");
        update_menu();
    }

    void on_position_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_position_changed");
        update_menu();
    }

    void on_track_added(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_added");
        update_menu();
        track.clip_added += on_clip_added;
        track.clip_removed += on_clip_removed;
        track.track_selection_changed += on_track_selection_changed;
    }

    void on_track_removed(Model.Track unused) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_removed");
        update_menu();
    }

    void on_clip_added(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_added");
        clip.moved += on_clip_moved;
        update_menu();
    }

    void on_clip_removed(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_removed");
        clip.moved -= on_clip_moved;
        update_menu();
    }

    void on_track_selection_changed(Model.Track track) {
        if (track.get_is_selected()) {
            foreach (Model.Track t in project.tracks) {
                if (t != track) {
                    t.set_selected(false);
                }
            }
        }
    }

    void on_clip_moved(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_moved");
        update_menu();
    }

    void on_drag_data_received(Gtk.Widget w, Gdk.DragContext context, int x, int y,
                                Gtk.SelectionData selection_data, uint drag_info, uint time) {
        present();
    }

    void update_menu() {
        bool library_selected = library.has_selection();
        bool selected = timeline.is_clip_selected();
        bool playhead_on_clip = project.playhead_on_clip();
        int number_of_tracks = project.tracks.size;
        bool is_stopped = is_stopped();
        bool one_selected = false;
        if (library_selected) {
            one_selected = library.get_selected_files().size == 1;
        } else if (selected) {
            one_selected = timeline.selected_clips.size == 1;
        }

        // File menu
        set_sensitive_group(main_group, "NewProject", is_stopped);
        set_sensitive_group(main_group, "Open", is_stopped);
        set_sensitive_group(main_group, "Save", is_stopped);
        set_sensitive_group(main_group, "SaveAs", is_stopped);
        set_sensitive_group(main_group, "Settings", is_stopped);
        set_sensitive_group(main_group, "Export", project.can_export());
        set_sensitive_group(main_group, "Quit", is_stopped);

        // Edit menu
        set_sensitive_group(main_group, "Undo", is_stopped);
        set_sensitive_group(main_group, "Copy", is_stopped && selected);
        set_sensitive_group(main_group, "Cut", is_stopped && selected);
        set_sensitive_group(main_group, "Paste", timeline.clipboard.clips.size != 0 && is_stopped);
        set_sensitive_group(main_group, "Delete", (selected || library_selected) && is_stopped);
        set_sensitive_group(main_group, "SplitAtPlayhead",
            selected && playhead_on_clip && is_stopped);
        set_sensitive_group(main_group, "TrimToPlayhead",
            selected && playhead_on_clip && is_stopped);
        set_sensitive_group(main_group, "JoinAtPlayhead", 
                is_stopped && selected && project.playhead_on_contiguous_clip());
        set_sensitive_group(main_group, "ClipProperties", one_selected);

        // View menu
        set_sensitive_group(main_group, "ZoomProject", project.get_length() != 0);

        // Track menu
        set_sensitive_group(main_group, "Rename", number_of_tracks > 0 && is_stopped);
        set_sensitive_group(main_group, "DeleteTrack", number_of_tracks > 0 && is_stopped);
        set_sensitive_group(main_group, "NewTrack", is_stopped);

        // toolbar
        set_sensitive_group(main_group, "Play", true);
        set_sensitive_group(main_group, "Record", number_of_tracks > 0 
                && !project.transport_is_recording());
    }

    public Model.Track? selected_track() {
        foreach (Model.Track track in project.tracks) {
            if (track.get_is_selected()) {
                return track;
            }
        }
        error("can't find selected track");
        return null;
    }

    public void scroll_to_beginning() {
        h_adjustment.set_value(0.0);
    }

    public void scroll_to_end() {
        int new_adjustment = timeline.provider.time_to_xpos(project.get_length());
        int window_width = timeline.parent.allocation.width;
        if (new_adjustment < timeline.parent.allocation.width) {
            new_adjustment = 0;
        } else {
            new_adjustment = new_adjustment - window_width / 2;
        }

        int max_value = (int)(h_adjustment.upper - timeline_scrolled.allocation.width);
        if (new_adjustment > max_value) {
            new_adjustment = max_value;
        }

        h_adjustment.set_value(new_adjustment);
    }

    static int sgn(int x) {
        if (x == 0)
            return 0;
        return x < 0 ? -1 : 1;
    }
    
    public void scroll_toward_center(int xpos) {
        if (cursor_pos == -1) {
            cursor_pos = xpos - (int) h_adjustment.value;
        }
        // Move the cursor position toward the center of the window.  We compute
        // the remaining distance and move by its square root; this results in
        // a smooth decelerating motion.
        int page_size = (int) h_adjustment.page_size;
        int diff = page_size / 2 - cursor_pos;
        int d = sgn(diff) * (int) Math.sqrt(diff.abs());
        cursor_pos += d;
        int x = int.max(0, xpos - cursor_pos);
        int max_value = (int)(h_adjustment.upper - timeline_scrolled.allocation.width);
        if (x > max_value) {
            x = max_value;
        }
        h_adjustment.set_value(x);
    }

    public override bool key_press_event(Gdk.EventKey event) {
        switch (event.keyval) {
            case KeySyms.KP_Enter:
            case KeySyms.Return:
                if ((event.state & GDK_SHIFT_ALT_CONTROL_MASK) != 0)
                    return base.key_press_event(event);
                on_rewind();
                break;
            case KeySyms.Left:
                project.media_engine.go(project.transport_get_position() - Gst.SECOND);
                break;
            case KeySyms.Right:
                project.media_engine.go(project.transport_get_position() + Gst.SECOND);
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

    // File menu
    void on_export() {
        string filename = null;
        if (DialogUtils.save(this, "Export", false, export_filters, ref filename)) {
            try {
                new MultiFileProgress(this, 1, "Export", project.media_engine);
                project.media_engine.disconnect_output(audio_output);
                audio_export = new View.OggVorbisExport(View.MediaConnector.MediaTypes.Audio, 
                    filename, project.media_engine.get_project_audio_export_caps());
                project.media_engine.connect_output(audio_export);
                project.media_engine.start_export(filename);
            } catch (Error e) {
                do_error_dialog("Could not export file", e.message);
            }
        }
    }

    void on_post_export(bool canceled) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_post_export");
        project.media_engine.disconnect_output(audio_export);
        project.media_engine.connect_output(audio_output);
        
        if (canceled) {
            GLib.FileUtils.remove(audio_export.get_filename());
        }

        audio_export = null;
    }

    void on_project_new_finished_closing(bool project_did_close) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_project_new_finished_closing");
        project.closed -= on_project_close;
        finished_closing -= on_project_new_finished_closing;
        if (project_did_close) {
            project.media_engine.set_play_state(PlayState.LOADING);
            project.load(null);
            default_track_set();
            project.media_engine.pipeline.set_state(Gst.State.PAUSED);
            project.undo_manager.reset();
        }
    }

    void on_project_new() {
        load_errors.clear();
        project.closed += on_project_close;
        finished_closing += on_project_new_finished_closing;
        project.close();
    }

    void on_project_open_finished_closing(bool project_did_close) {
        project.closed -= on_project_close;
        finished_closing -= on_project_open_finished_closing;
        if (project_did_close) {
            GLib.SList<string> filenames;
            if (DialogUtils.open(this, filters, false, false, out filenames)) {
                loading = true;
                project.load(filenames.data);
            }
        }
    }

    void on_project_open() {
        load_errors.clear();
        project.closed += on_project_close;
        finished_closing += on_project_open_finished_closing;
        project.close();
    }

    void on_project_save_as() {
        save_dialog();
    }

    void on_project_save() {
        do_save();
    }

    void on_save_new_file_finished_closing(bool did_close) {
        project.closed -= on_project_close;
        finished_closing -= on_save_new_file_finished_closing;
        project.load(project.get_project_file());
    }

    bool do_save() {
        if (project.get_project_file() != null) {
            project.save(null);
            return true;
        }
        else {
            return save_dialog();
        }
    }

    bool save_dialog() {
        bool saving_new_file = project.get_project_file() == null;

        string filename = project.get_project_file();
        bool create_directory = project.get_project_file() == null;
        if (DialogUtils.save(this, "Save Project", create_directory, filters, ref filename)) {
            project.save(filename);
            if (saving_new_file && project.get_project_file() != null) {
                project.closed += on_project_close;
                finished_closing += on_save_new_file_finished_closing;
                project.close();
            }
            return true;
        }
        return false;
    }

    void on_properties() {
        Gtk.Builder builder = new Gtk.Builder();
        try {
            builder.add_from_file(AppDirs.get_resources_dir().get_child("fillmore.glade").get_path());
        } catch(GLib.Error e) {
            return;
        }
        builder.connect_signals(null);
        ProjectProperties properties = (ProjectProperties)builder.get_object("projectproperties1");
        properties.setup(project, builder);

        int response = properties.run();
        if (response == Gtk.ResponseType.APPLY) {
            string description = "Set Project Properties";
            project.undo_manager.start_transaction(description);
            project.set_bpm(properties.get_tempo());
            project.set_time_signature(properties.get_time_signature());
            project.click_during_record = properties.during_record();
            project.click_during_play = properties.during_play();
            project.click_volume = properties.get_click_volume();
            project.undo_manager.end_transaction(description);
        }
        properties.destroy();
    }

    void on_quit_finished_closing(bool project_did_close) {
        project.closed -= on_project_close;
        finished_closing -= on_quit_finished_closing;
        if (project_did_close) {
            Gtk.main_quit();
        }
    }

    void on_quit() {
        if (is_stopped()) {
            project.closed += on_project_close;
            finished_closing += on_quit_finished_closing;
            project.close();
        }
    }

    bool on_delete_event() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_delete_event");
        on_quit();
        return true;
    }

    void on_project_close() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_project_close");
        if (project.undo_manager.is_dirty) {
            switch(DialogUtils.save_close_cancel(this, null, "Save changes before closing?")) {
                case Gtk.ResponseType.ACCEPT:
                    if (!do_save()) {
                        finished_closing(false);
                        return;
                    }
                    break;
                case Gtk.ResponseType.CLOSE:
                    // if the user has never saved the file but quits anyway, save in .fillmore
                    if (project.get_project_file() == null) {
                        project.save(null);
                    }
                    break;
                case Gtk.ResponseType.DELETE_EVENT: // when user presses escape.
                case Gtk.ResponseType.CANCEL:
                    finished_closing(false);
                    return;
                default:
                    assert(false);
                    break;
            }
        }
        finished_closing(true);
    }

    // Edit menu
    void on_cut() {
        timeline.do_cut();
    }

    void on_copy() {
        timeline.do_copy();
    }

    void on_paste() {
        timeline.paste();
    }

    void on_undo() {
        project.undo();
    }

    void on_delete() {
        if (library.has_selection()) {
            library.delete_selection();
        } else {
            timeline.delete_selection();
        }
    }

    public void on_split_at_playhead() {
        project.split_at_playhead();
    }

    public void on_join_at_playhead() {
        project.join_at_playhead();
    }

    public void on_trim_to_playhead() {
        project.trim_to_playhead();
    }

    public void on_clip_properties() {
        if (library.has_selection()) {
            Gee.ArrayList<string> files = library.get_selected_files();
            if (files.size == 1) {
                string file_name = files.get(0);
                Model.ClipFile? clip_file = project.find_clipfile(file_name);
                DialogUtils.show_clip_properties(this, null, clip_file, null);
            }
        } else {
            Gee.ArrayList<ClipView> clips = timeline.selected_clips;
            if (clips.size == 1) {
                ClipView clip_view = clips.get(0);
                DialogUtils.show_clip_properties(this, clip_view, null, null);
            }
        }
    }

    // Track menu

    void on_track_new() {
        UI.TrackInformation dialog = new UI.TrackInformation();
        dialog.set_track_name(get_default_track_name());
        if (track_name_dialog(dialog, null)) {
            project.add_track(new Model.AudioTrack(project, dialog.get_track_name()));
        }
        dialog.destroy();
    }

    void on_track_rename() {
        UI.TrackInformation dialog = new UI.TrackInformation();
        Model.Track track = selected_track();
        dialog.set_title("Rename Track");
        dialog.set_track_name(selected_track().display_name);
        if (track_name_dialog(dialog, track)) {
            track.set_display_name(dialog.get_track_name());
        }
        dialog.destroy();
    }

    bool track_name_dialog(UI.TrackInformation dialog, Model.Track? track) {
        Gtk.ResponseType result = Gtk.ResponseType.OK;
        bool is_ok = true;
        do {
            result = (Gtk.ResponseType) dialog.run();
            string new_name = dialog.get_track_name();

            if (result == Gtk.ResponseType.OK) {
                if (new_name == "") {
                    is_ok = false;
                    DialogUtils.error("Invalid track name", "Name cannot be empty");
                } else {
                    is_ok = !project.is_duplicate_track_name(track, new_name);
                    if (!is_ok) {
                        DialogUtils.error("Duplicate track name", null);
                    }
                }
            }
        } while (result == Gtk.ResponseType.OK && !is_ok);
        return result == Gtk.ResponseType.OK && is_ok;
    }

    void on_track_remove() {
        project.remove_track(selected_track());
    }

    // View menu
    void on_zoom_in() {
        do_zoom(0.1f);
    }

    void on_zoom_out() {
        do_zoom(-0.1f);
    }

    void on_zoom_to_project() {
        timeline.zoom_to_project(h_adjustment.page_size);
    }

    void on_view_library() {
        if (timeline_library_pane.child2 == library_scrolled) {
            timeline_library_pane.remove(library_scrolled);
            project.library_visible = false;
        } else {
            timeline_library_pane.add2(library_scrolled);
            timeline_library_pane.show_all();
            project.library_visible = true;
        }
    }

    void on_library_size_allocate(Gdk.Rectangle rectangle) {
        if (!loading && timeline_library_pane.child2 == library_scrolled) {
            project.library_width = rectangle.width;
        }
    }

    // Help menu

    void on_help_contents() {
        try {
            Gtk.show_uri(null, "http://trac.yorba.org/wiki/UsingFillmore0.1", 0);
        } catch (GLib.Error e) {
        }
    }

    void on_about() {
        Gtk.show_about_dialog(this,
          "version", "%1.2lf".printf(project.get_version()),
          "comments", "a multitrack recorder",
          "copyright", "(c) 2009 yorba"
        );
    }

    void on_save_graph() {
        project.print_graph(project.media_engine.pipeline, "save_graph");
    }

    // toolbar

    void on_rewind() {
        project.media_engine.go(0);
        scroll_to_beginning();
    }

    void on_end() {
        project.go_end();
        scroll_to_end();
    }

    void on_play() {
        if (project.transport_is_recording()) {
            set_sensitive_group(main_group, "Record", true);
            record_button.set_active(false);
            play_button.set_active(false);
            project.media_engine.pause();
        } else if (play_button.get_active())
            project.media_engine.do_play(PlayState.PLAYING);
        else
            project.media_engine.pause();
    }

    void on_record() {
        if (record_button.get_active()) {
            set_sensitive_group(main_group, "Record", false);
            set_sensitive_group(main_group, "Play", false);
            project.record(selected_track() as Model.AudioTrack);
        }
    }

    void on_callback_pulse() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_callback_pulse");
        if (project.transport_is_playing()) {
            scroll_toward_center(provider.time_to_xpos(project.media_engine.position));
        }
        timeline.queue_draw();
    }

    int64 get_zoom_center_time() {
        return project.transport_get_position();
    }

    void do_zoom(float increment) {
        center_time = get_zoom_center_time();
        timeline.zoom(increment);
    }

    void on_timeline_size_allocate(Gdk.Rectangle rectangle) {
        if (center_time != -1) {
            int new_center_pixel = provider.time_to_xpos(center_time);
            int page_size = (int)(h_adjustment.get_page_size() / 2);
            h_adjustment.clamp_page(new_center_pixel - page_size, new_center_pixel + page_size);
            center_time = -1;
        }
    }

    void on_timeline_selection_changed(bool selected) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_timeline_selection_changed");
        if (selected) {
            library.unselect_all();
        }
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

    // main

    static void main(string[] args) {
        debug_level = -1;
        OptionContext context = new OptionContext(
            " [project file] - Record and edit multitrack audio");
        context.add_main_entries(options, null);
        context.add_group(Gst.init_get_option_group());

        try {
            context.parse(ref args);
        } catch (GLib.Error arg_error) {
            stderr.printf("%s\nRun 'fillmore --help' for a full list of available command line options.", 
                arg_error.message);
            return;
        }
        Gtk.init(ref args);
        try {
            GLib.Environment.set_application_name(_PROGRAM_NAME);
            if (debug_level > -1) {
                set_logging_level((Logging.Level)debug_level);
            }

            AppDirs.init(args[0], _PROGRAM_NAME);
            string rc_file = AppDirs.get_resources_dir().get_child("fillmore.rc").get_path();

            Gtk.rc_parse(rc_file);
            Gst.init(ref args);
            string? project_file = null;
            if (args.length > 1) {
                project_file = args[1];
            }
            ClassFactory.set_class_factory(new FillmoreClassFactory());
            View.MediaEngine.can_run();

            try {
                string filename = GLib.Filename.from_uri(project_file);
                project_file = filename;
            } catch (GLib.Error e) {
            }

            Recorder recorder = new Recorder(project_file);
            recorder.show_all();
            Gtk.main();
        } catch (Error e) {
            do_error_dialog("Could not start application.",e.message);
        }
    }

    public static void do_error_dialog(string major_message, string? minor_message) {
        DialogUtils.error(major_message, minor_message);
    }

    public void on_load_error(string message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_error");
        load_errors.add(message);
    }

    public void on_load_complete() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_complete");
        project.media_engine.pipeline.set_state(Gst.State.PAUSED);
        timeline_library_pane.set_position(project.library_width);

        Gtk.ToggleAction action = main_group.get_action(LibraryToggle) as Gtk.ToggleAction;
        if (action.get_active() != project.library_visible) {
            action.set_active(project.library_visible);
        }

        if (project.library_visible) {
            if (timeline_library_pane.child2 != library_scrolled) {
                timeline_library_pane.add2(library_scrolled);
            }
        } else {
            if (timeline_library_pane.child2 == library_scrolled) {
                timeline_library_pane.remove(library_scrolled);
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

    void on_name_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_name_changed");
        set_title(project.get_file_display_name());
    }

    void on_dirty_changed(bool isDirty) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_dirty_changed");
        Gtk.MenuItem? file_save = (Gtk.MenuItem?) get_widget(manager, "/MenuBar/FileMenu/FileSave");
        assert(file_save != null);
        file_save.set_sensitive(isDirty);
    }

    void on_undo_changed(bool can_undo) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_undo_changed");
        Gtk.MenuItem? undo = (Gtk.MenuItem?) get_widget(manager, "/MenuBar/EditMenu/EditUndo");
        assert(undo != null);
        undo.set_label("_Undo " + project.undo_manager.get_undo_title());
        undo.set_sensitive(can_undo);
    }

    void on_playstate_changed(PlayState playstate) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_playstate_changed");
        if (playstate == PlayState.STOPPED) {
            play_button.set_active(false);
            set_sensitive_group(main_group, "Export", project.can_export());
            update_menu();
        }
    }

    void on_error_occurred(string major_message, string? minor_message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_error_occurred");
        DialogUtils.error(major_message, minor_message);
    }

    string get_fillmore_directory() {
        return Path.build_filename(GLib.Environment.get_home_dir(), ".fillmore");
    }

    // TransportDelegate methods
    bool is_playing() {
        return project.transport_is_playing();
    }

    bool is_recording() {
        return project.transport_is_recording();
    }

    bool is_stopped() {
        return !(is_playing() || is_recording());
    }
}

