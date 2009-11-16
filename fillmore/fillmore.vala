/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

class Recorder : Gtk.Window {
    public Model.AudioProject project;
    
    HeaderArea header_area;
    TimeLine timeline;
    Model.TimeSystem provider;
    Gtk.Adjustment h_adjustment;
    int cursor_pos = -1;
    
    Gtk.Action delete_action;
    Gtk.Action record_action;
    
    Gtk.ToggleToolButton play_button;
    Gtk.ToggleToolButton record_button;
    Gtk.UIManager manager;
    // TODO: Have a MediaExportConnector that extends MediaConnector rather than concrete type.
    View.OggVorbisExport audio_export;
    View.AudioOutput audio_output;

    public const string NAME = "fillmore";
    const Gtk.ActionEntry[] entries = {
        { "File", null, "_File", null, null, null },
        { "Open", Gtk.STOCK_OPEN, "_Open...", null, "Open a project", on_project_open },
        { "NewProject", Gtk.STOCK_NEW, "_New...", null, "Create new project", on_project_new },
        { "Save", Gtk.STOCK_SAVE, "_Save", "<Control>S", "Save project", on_project_save },
        { "SaveAs", Gtk.STOCK_SAVE_AS, "Save _As...", "<Control><Shift>S", 
            "Save project with new name", on_project_save_as },
        { "Export", Gtk.STOCK_JUMP_TO, "_Export...", "<Control>E", null, on_export },
        { "Quit", Gtk.STOCK_QUIT, null, null, null, on_quit },
        
        { "Edit", null, "_Edit", null, null, null },
        { "Undo", Gtk.STOCK_UNDO, null, "<Control>Z", null, on_undo },
        { "Delete", Gtk.STOCK_DELETE, null, "Delete", null, on_delete },
        { "SplitAtPlayhead", null, "_Split at Playhead", "<Control>P", null, on_split_at_playhead },
        { "TrimToPlayhead", null, "_Trim to Playhead", "<Control>T", null, on_trim_to_playhead },
        { "JoinAtPlayhead", null, "_Join at Playhead", "<Control>J", null, on_join_at_playhead },
        { "RevertToOriginal", Gtk.STOCK_REVERT_TO_SAVED, "_Revert to Original",
          "<Control>R", null, on_revert_to_original },
        { "ClipProperties", Gtk.STOCK_PROPERTIES, "Properti_es", "<Alt>Return", 
            null, on_clip_properties },
        { "View", null, "_View", null, null, null },
        { "ZoomIn", Gtk.STOCK_ZOOM_IN, "Zoom _in", "equal", null, on_zoom_in },
        { "ZoomOut", Gtk.STOCK_ZOOM_OUT, "Zoom _out", "minus", null, on_zoom_out },

        { "Track", null, "_Track", null, null, null },
        { "NewTrack", Gtk.STOCK_ADD, "_New", "<Control><Shift>N", 
            "Create new track", on_track_new },
        { "Rename", null, "_Rename...", null, "Rename track", on_track_rename },
        { "DeleteTrack", null, "_Delete Track", "<Control><Shift>Delete", 
            "Delete track", on_track_remove },
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, null, null, null, on_about },
        { "SaveGraph", null, "Save _Graph", null, "Save graph", on_save_graph },
        
        { "Rewind", Gtk.STOCK_MEDIA_PREVIOUS, "Rewind", "Home", "Go to beginning", on_rewind },
        { "End", Gtk.STOCK_MEDIA_NEXT, "End", "End", "Go to end", on_end }
    };
    
    const Gtk.ToggleActionEntry[] toggle_entries = {
        { "Play", Gtk.STOCK_MEDIA_PLAY, null, "space", "Play", on_play },
        { "Record", Gtk.STOCK_MEDIA_RECORD, null, "r", "Record", on_record }
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
      <menuitem name="FileExport" action="Export"/>
      <menuitem name="FileQuit" action="Quit"/>
    </menu>
    <menu name="EditMenu" action="Edit">
      <menuitem name="EditUndo" action="Undo" />
      <menuitem name="EditDelete" action="Delete"/>
      <separator/>
      <menuitem name="ClipSplitAtPlayhead" action="SplitAtPlayhead"/>
      <menuitem name="ClipTrimToPlayhead" action="TrimToPlayhead"/>
      <menuitem name="ClipJoinAtPlayhead" action="JoinAtPlayhead" />
      <menuitem name="ClipRevertToOriginal" action="RevertToOriginal"/>
      <menuitem name="ClipViewProperties" action="ClipProperties"/>
    </menu>
    <menu name="ViewMenu" action="View">
        <menuitem name="ViewZoomIn" action="ZoomIn"/>
        <menuitem name="ViewZoomOut" action="ZoomOut"/>
    </menu>
    <menu name="TrackMenu" action="Track">
      <menuitem name="TrackNew" action="NewTrack"/>
      <menuitem name="TrackRename" action="Rename" />
      <menuitem name="TrackDelete" action="DeleteTrack" />
    </menu>
    <menu name="HelpMenu" action="Help">
      <menuitem name="HelpAbout" action="About"/>
      <menuitem name="SaveGraph" action="SaveGraph" />
    </menu>
  </menubar>
  <popup name="ClipContextMenu">
    <menuitem name="ClipContextRevert" action="RevertToOriginal"/>
    <menuitem name="ClipContextProperties" action="ClipProperties"/>
  </popup>
  <toolbar name="Toolbar">
    <toolitem name="New" action="NewTrack"/>
    <separator/>
    <toolitem name="Rewind" action="Rewind"/>
    <toolitem name="End" action="End" />
    <toolitem name="Play" action="Play"/>
    <toolitem name="Record" action="Record"/>
  </toolbar>
  <accelerator name="Rewind" action="Rewind"/>
  <accelerator name="End" action="End" />
  <accelerator name="Play" action="Play"/>
  <accelerator name="Record" action="Record"/>
</ui>
""";

    const DialogUtils.filter_description_struct[] filters = {
        { "Fillmore Project Files", Model.Project.FILLMORE_FILE_EXTENSION },
        { "Lombard Project Files", Model.Project.LOMBARD_FILE_EXTENSION }
    };
    
    const DialogUtils.filter_description_struct[] export_filters = {
        { "Ogg Files", "ogg" }
    };
    
    public Recorder(string? project_file) {
        provider = new Model.TimecodeTimeSystem();
        project = new Model.AudioProject();
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
        project.load_complete += on_load_complete;

        audio_output = new View.AudioOutput(project.media_engine.get_project_audio_caps());
        project.media_engine.connect_output(audio_output);
        
        set_position(Gtk.WindowPosition.CENTER);
        title = "fillmore";
        set_default_size(600, 400);
        
        Gtk.ActionGroup group = new Gtk.ActionGroup("main");
        group.add_actions(entries, this);
        group.add_toggle_actions(toggle_entries, this);

        delete_action = group.get_action("Delete");    
        record_action = group.get_action("Record");
        
        manager = new Gtk.UIManager();
        manager.insert_action_group(group, 0);
        try {
            manager.add_ui_from_string(ui, -1);
        } catch (Error e) { error("%s", e.message); }
        
        Gtk.MenuBar menubar = (Gtk.MenuBar) get_widget(manager, "/MenuBar");
        Gtk.Toolbar toolbar = (Gtk.Toolbar) get_widget(manager, "/Toolbar");
        play_button = (Gtk.ToggleToolButton) get_widget(manager, "/Toolbar/Play");
        record_button = (Gtk.ToggleToolButton) get_widget(manager, "/Toolbar/Record");
        on_undo_changed(false);

        timeline = new TimeLine(project, provider);
        timeline.selection_changed += on_selection_changed;
        timeline.context_menu = (Gtk.Menu) manager.get_widget("/ClipContextMenu");

        update_menu();
        
        Gtk.HBox hbox = new Gtk.HBox(false, 0);
        header_area = new HeaderArea(this, provider, TimeLine.RULER_HEIGHT);
        hbox.pack_start(header_area, false, false, 0);

        Gtk.ScrolledWindow scrolled = new Gtk.ScrolledWindow(null, null);
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
        scrolled.add_with_viewport(timeline);
        hbox.pack_start(scrolled, true, true, 0);
        h_adjustment = scrolled.get_hadjustment();
        
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(menubar, false, false, 0);
        vbox.pack_start(toolbar, false, false, 0);
        vbox.pack_start(hbox, true, true, 0);
        add(vbox);
        
        Gtk.MenuItem? save_graph = (Gtk.MenuItem?) 
            get_widget(manager, "/MenuBar/HelpMenu/SaveGraph");

        // TODO: only destroy it if --debug is not specified on the command line
        // or conversely, only add it if --debug is specified on the command line
        if (save_graph != null) {
            save_graph.destroy();
        }

        add_accel_group(manager.get_accel_group());
        timeline.grab_focus();
        delete_event += on_delete_event;
        project.load(project_file);
        if (project_file == null) {
            default_track_set();
        }
        project.media_engine.pipeline.set_state(Gst.State.PAUSED);
    }

    void default_track_set() {
        project.add_track(new Model.AudioTrack(project, get_default_track_name()));
        project.tracks[0].set_selected(true);
    }

    public string get_default_track_name() {
        List<string> default_track_names = new List<string>();
        foreach(Model.Track track in project.tracks) {
            if (track.display_name.has_prefix("track ")) {
                default_track_names.append(track.display_name);
            }
        }
        default_track_names.sort(strcmp);
        
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

    void set_sensitive_menu(string menu_path, bool sensitive) {
        Gtk.MenuItem? the_menuitem = (Gtk.MenuItem?) get_widget(manager, menu_path);
        if (the_menuitem == null) {
            error("invalid menu path %s".printf(menu_path));
        }
        the_menuitem.set_sensitive(sensitive);
    }
    
    void on_selection_changed(bool selected) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_selection_changed");
        update_menu();
    }
    
    void on_position_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_position_changed");
        update_menu();
    }
    
    void on_track_added(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_added");
        track.clip_added += on_clip_added;
        track.clip_removed += on_clip_removed;
        track.track_selection_changed += on_track_selection_changed;
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
    
    void update_menu() {
        bool selected = timeline.is_clip_selected();
        bool playhead_on_clip = project.playhead_on_clip();

        bool clip_is_trimmed = false;
        if (selected) {
            foreach (ClipView clip_view in timeline.selected_clips) {
                clip_is_trimmed = clip_view.clip.is_trimmed();
                if (clip_is_trimmed) {
                    break;
                }
            }
        }

        delete_action.set_sensitive(selected);
        set_sensitive_menu("/MenuBar/EditMenu/ClipSplitAtPlayhead", selected && playhead_on_clip);
        set_sensitive_menu("/MenuBar/EditMenu/ClipTrimToPlayhead", selected && playhead_on_clip);
        set_sensitive_menu("/MenuBar/EditMenu/ClipRevertToOriginal", selected && clip_is_trimmed);
        set_sensitive_menu("/MenuBar/EditMenu/ClipViewProperties", selected);
        set_sensitive_menu("/MenuBar/EditMenu/ClipJoinAtPlayhead",
            selected && project.playhead_on_contiguous_clip());
        set_sensitive_menu("/ClipContextMenu/ClipContextRevert", selected && clip_is_trimmed);
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
        h_adjustment.set_value(new_adjustment);
    }
    
    const int scroll_speed = 8;
    
    static int sgn(int x) {
        if (x == 0)
            return 0;
        return x < 0 ? -1 : 1;
    }
    
    public void scroll_toward_center(int xpos) {
        int current = (int) h_adjustment.value;
        if (cursor_pos == -1)
            cursor_pos = xpos - current;
        
        // Move the cursor position toward the center of the window.  We compute
        // the remaining distance and move by its square root; this results in
        // a smooth decelerating motion.
        int page_size = (int) h_adjustment.page_size;
        int diff = page_size / 2 - cursor_pos;
        int d = sgn(diff) * (int) Math.sqrt(diff.abs());
        cursor_pos += d;
        
        int x = int.max(0, xpos - cursor_pos);
        h_adjustment.set_value(x);
    }

    public override bool key_press_event(Gdk.EventKey event) {
        switch(event.keyval) {
            case KeySyms.LEFT:
                project.media_engine.go(project.transport_get_position() - Gst.SECOND);
                return true;
            case KeySyms.RIGHT:
                project.media_engine.go(project.transport_get_position() + Gst.SECOND);
                return true;
        }
        return base.key_press_event(event);
    }
    
    // File menu
    void on_export() {
        string filename;
        if (DialogUtils.save(this, "Export", export_filters, out filename)) {
            new MultiFileProgress(this, 1, "Export", project.media_engine);
            project.media_engine.disconnect_output(audio_output);
            audio_export = new View.OggVorbisExport(View.MediaConnector.MediaTypes.Audio, 
                filename, project.media_engine.get_project_audio_export_caps());
            project.media_engine.connect_output(audio_export);
            project.media_engine.start_export(filename);
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
    
    void on_project_new() {
    }
    
    void on_project_open() {
        GLib.SList<string> filenames;
        if (DialogUtils.open(this, filters, false, false, out filenames)) {
            project.load(filenames.data);
        }
    }
    
    void on_project_save_as() {
        save_dialog();
    }
    
    void on_project_save() {
        do_save();
    }
    
    bool do_save() {
        if (project.project_file != null) {
            project.save(null);
            return true;
        }
        else {
            return save_dialog();
        }
    }
    
    bool save_dialog() {
        string filename;
        if (DialogUtils.save(this, "Save Project", filters, out filename)) {
            project.save(filename);
            return true;
        }
        return false;
    }
    
    void on_quit() {
        project.closed += on_project_close;
        project.close();
    }
    
    bool on_delete_event() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_delete_event");
        on_quit();
        return true;
    }

    void on_project_close() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_project_close");
        project.closed -= on_project_close;
        if (project.undo_manager.is_dirty) {
            switch(DialogUtils.save_close_cancel(this, null, "Save changes before closing?")) {
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
    
    // Edit menu

    void on_undo() {
        project.undo();
    }
    
    void on_delete() {
        timeline.delete_selection();
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
    
    public void on_revert_to_original() {
        foreach (ClipView clip_view in timeline.selected_clips) {
            Model.Track? track = project.track_from_clip(clip_view.clip);
            if (track != null) {
                track.revert_to_original(clip_view.clip);
            }
        }
    }
  
    public void on_clip_properties() {
        foreach (ClipView clip_view in timeline.selected_clips) {
            DialogUtils.show_clip_properties(this, clip_view, null);
        }
    }

    // Track menu

    void on_track_new() {
        UI.TrackInformation dialog = new UI.TrackInformation();
        dialog.set_track_name(get_default_track_name());
        if (dialog.run() == Gtk.ResponseType.OK) {
            string track_name = dialog.get_track_name();
            if (track_name != "") {
                project.add_track(new Model.AudioTrack(project, track_name));
            }
        }
        dialog.destroy();
    }
    
    void on_track_rename() {
        UI.TrackInformation dialog = new UI.TrackInformation();
        Model.Track track = selected_track();
        dialog.set_title("Rename track");
        dialog.set_track_name(selected_track().display_name);
        if (dialog.run() == Gtk.ResponseType.OK) {
            string track_name = dialog.get_track_name();
            if (track_name != "") {
                track.set_display_name(dialog.get_track_name());
            }
        }
        dialog.destroy();
    }

    void on_track_remove() {
        project.remove_track(selected_track());
    }
    
    // View menu
    void on_zoom_in() {
        timeline.zoom(0.1f);
    }
    
    void on_zoom_out() {
        timeline.zoom(-0.1f);
    }
    
    // Help menu
    
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
            project.record(selected_track() as Model.AudioTrack);
        } else {
            project.media_engine.pause();
        }
    }
        
    void on_callback_pulse() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_callback_pulse");
        if (project.transport_is_playing()) {
            scroll_toward_center(provider.time_to_xpos(project.media_engine.position));
        }
        timeline.queue_draw();
    }
    // main
    
    static void main(string[] args) {
        Gtk.init(ref args);
        GLib.Environment.set_application_name("fillmore");
        
        Gst.init(ref args);

        string? project_file = null;        
        if (args.length > 1) {
            project_file = args[1];
        }
        
        Recorder recorder = new Recorder(project_file);
        recorder.show_all();
    
        Gtk.main();
    }

    public void do_error_dialog(string message) {
        DialogUtils.error("Error", message);
    }
    
    public void on_load_error(string message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_error");
        do_error_dialog(message);
    }

    public void on_load_complete() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_complete");
        project.media_engine.pipeline.set_state(Gst.State.PAUSED);
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
        }
    }
    
    void on_error_occurred(string major_message, string? minor_message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_error_occurred");
        DialogUtils.error(major_message, minor_message);
    }
}

