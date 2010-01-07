/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;
class App : Gtk.Window {
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
    
    Gtk.Action export_action;
    Gtk.Action delete_action;
    Gtk.Action cut_action;
    Gtk.Action copy_action;
    Gtk.Action paste_action;
    Gtk.Action split_at_playhead_action;
    Gtk.Action trim_to_playhead_action;
    Gtk.Action revert_to_original_action;
    Gtk.Action clip_properties_action;
    Gtk.Action zoom_to_project_action;
    Gtk.Action join_at_playhead_action;
    
    Gtk.ToggleAction library_view_action;
    
    bool done_zoom = false;
    
    Gtk.VBox vbox = null;
    Gtk.MenuBar menubar;
    Gtk.UIManager manager;
    
    string project_filename;

    public const string NAME = "lombard";
   
    const Gtk.ActionEntry[] entries = {
        { "File", null, "_File", null, null, null },
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
        { "ZoomProject", null, "Fit to _Window", "<Shift>Z", null, on_zoom_to_project },

        { "Go", null, "_Go", null, null, null },
        { "Start", Gtk.STOCK_GOTO_FIRST, "_Start", "Home", null, on_go_start },
        { "End", Gtk.STOCK_GOTO_LAST, "_End", "End", null, on_go_end },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, null, null, null, on_about },
        { "SaveGraph", null, "Save _Graph", null, "Save graph", on_save_graph }
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
      <menuitem name="EditUndo" action="Undo" />
      <menuitem name="EditDelete" action="Delete"/>
      <menuitem name="EditCut" action="Cut"/>
      <menuitem name="EditCopy" action="Copy"/>
      <menuitem name="EditPaste" action="Paste"/>
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
        <separator />
        <menuitem name="ViewZoomProject" action="ZoomProject"/>
    </menu>
    <menu name="GoMenu" action="Go">
      <menuitem name="GoStart" action="Start"/>
      <menuitem name="GoEnd" action="End"/>
    </menu>
    <menu name="HelpMenu" action="Help">
      <menuitem name="HelpAbout" action="About"/>
      <menuitem name="SaveGraph" action="SaveGraph" />
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
        cut_action = group.get_action("Cut");
        copy_action = group.get_action("Copy");
        paste_action = group.get_action("Paste");
        split_at_playhead_action = group.get_action("SplitAtPlayhead");
        trim_to_playhead_action = group.get_action("TrimToPlayhead");
        join_at_playhead_action = group.get_action("JoinAtPlayhead");
        revert_to_original_action = group.get_action("RevertToOriginal");
        clip_properties_action = group.get_action("ClipProperties");
        zoom_to_project_action = group.get_action("ZoomProject");
        library_view_action = (Gtk.ToggleAction) view_library_action_group.get_action("Library");

        manager = new Gtk.UIManager();
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
        project.load_complete += on_load_complete;
        project.error_occurred += do_error_dialog;
        project.undo_manager.undo_changed += on_undo_changed;
        project.media_engine.post_export += on_post_export;

        audio_output = new View.AudioOutput(project.media_engine.get_project_audio_caps());
        project.media_engine.connect_output(audio_output);

        timeline = new TimeLine(project, project.time_provider);
        timeline.selection_changed += on_timeline_selection_changed;
        timeline.track_changed += on_track_changed;
        timeline.drag_data_received += on_drag_data_received;
        project.media_engine.position_changed += on_position_changed;
        ClipView.context_menu = (Gtk.Menu) manager.get_widget("/ClipContextMenu");

        library = new ClipLibraryView(project, "Drag clips here.");
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

            h_pane = new Gtk.HPaned();        
            h_pane.set_position(300);
            
            if (showing) {
                h_pane.add1(library_scrolled);
                h_pane.add2(drawing_area);            
            } else {
                h_pane.add2(drawing_area);
            }

            Gtk.VPaned v_pane = new Gtk.VPaned();
            v_pane.set_position(300);

            timeline_scrolled = new Gtk.ScrolledWindow(null, null);
            timeline_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            timeline_scrolled.add_with_viewport(timeline);

            h_adjustment = timeline_scrolled.get_hadjustment();
            h_adjustment.changed += on_adjustment_changed;
            prev_adjustment_lower = h_adjustment.get_lower();
            prev_adjustment_upper = h_adjustment.get_upper();
            
            v_pane.add1(h_pane);
            Gtk.VBox timeline_vbox = new Gtk.VBox(false, 0);
            timeline_vbox.pack_start(status_bar, false, false, 0);
            timeline_vbox.pack_start(timeline_scrolled, true, true, 0);
            v_pane.add2(timeline_vbox);
            vbox.pack_start(v_pane, true, true, 0);
            
            add(vbox);
        } else {
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
        project.load(project_filename);
        video_output = new View.VideoOutput(drawing_area);
        project.media_engine.connect_output(video_output);
    }
    
    void on_adjustment_changed(Gtk.Adjustment a) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_adjustment_changed");
        if (prev_adjustment_upper != a.get_upper() ||
            prev_adjustment_lower != a.get_lower()) {

            prev_adjustment_lower = a.get_lower();
            prev_adjustment_upper = a.get_upper();
            
            if (done_zoom)
                on_position_changed();
        }
        done_zoom = false;
    }

    void on_drag_data_received(Gtk.Widget w, Gdk.DragContext context, int x, int y,
                                Gtk.SelectionData selection_data, uint drag_info, uint time) {
        present();
    }
    
    public void set_project_name(string? filename) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "set_project_name");
        set_title(project.get_file_display_name());
    }

    public void do_error_dialog(string message, string? minor_message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "do_error_dialog");
        DialogUtils.error(message, minor_message);
    }
    
    public void on_load_error(string message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_error");
        DialogUtils.error("Load error", message);
    }
    
    public void on_load_complete() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_complete");
        on_zoom_to_project();
        queue_draw();
    }
    
    // Loader code
    
    public void load_file(string name, Model.LibraryImporter im) {
        if (get_file_extension(name) == Model.Project.LOMBARD_FILE_EXTENSION ||
            get_file_extension(name) == Model.Project.FILLMORE_FILE_EXTENSION)
            load_project(name);
        else {
            im.add_file(name);
        }
    }
    
    void on_open() {
        GLib.SList<string> filenames;
        if (DialogUtils.open(this, filters, true, true, out filenames)) {
            project.create_clip_importer(null, false, 0);
            project.importer.started += on_importer_started;
            foreach (string s in filenames) {
                string str;
                try {
                    str = GLib.Filename.from_uri(s);
                } catch (GLib.ConvertError e) { str = s; }
                load_file(str, project.importer);
            }
            project.importer.start();
        }
    }

    void on_importer_started(Model.ClipImporter i, int num) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_importer_started");
        new MultiFileProgress(this, num, "Import", i);
    }

    bool do_save_dialog() {
        string filename = project.project_file;
        bool create_directory = project.project_file == null;
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
        if (project.project_file != null) {
            project.save(null);
            return true;
        }
        return do_save_dialog();
    }
    
    public void load_project(string filename) {
        project.load(filename);
    }
    
    const float SCROLL_MARGIN = 0.05f;
    
    // Scroll if necessary so that horizontal position xpos is visible in the window.
    void scroll_to(int xpos) {
        float margin = project.transport_is_playing() ? 0.0f : SCROLL_MARGIN;
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
        Fraction? frames_per_second = null;
        project.get_framerate_fraction(out frames_per_second);
        foreach (ClipView clip_view in timeline.selected_clips) {
            DialogUtils.show_clip_properties(this, clip_view, frames_per_second);
        }
    }
    
    public void on_position_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_position_changed");
        int xpos = timeline.provider.time_to_xpos(project.transport_get_position());
        scroll_to(xpos);
        if (project.transport_is_playing())
            scroll_toward_center(xpos);  
        update_menu();
    }
    
    public void on_track_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_changed");
        update_menu();
    }
    
    void update_menu() {
        bool clip_selected = timeline.is_clip_selected();
        
        delete_action.set_sensitive(clip_selected || timeline.gap_selected() || 
            library.has_selection());
        cut_action.set_sensitive(clip_selected);
        copy_action.set_sensitive(clip_selected);
        paste_action.set_sensitive(timeline.clipboard.clips.size > 0);

        bool clip_is_trimmed = false;
        if (clip_selected) {
            foreach (ClipView clip_view in timeline.selected_clips) {
                clip_is_trimmed = clip_view.clip.is_trimmed();
                if (clip_is_trimmed) {
                    break;
                }
            }
        }
        revert_to_original_action.set_sensitive(clip_is_trimmed);
        clip_properties_action.set_sensitive(clip_selected);
        
        
        bool playhead_on_clip = project.playhead_on_clip();
        split_at_playhead_action.set_sensitive(playhead_on_clip);
        join_at_playhead_action.set_sensitive(project.playhead_on_contiguous_clip());
        
        bool dir;
        trim_to_playhead_action.set_sensitive(project.can_trim(out dir));
        
        zoom_to_project_action.set_sensitive(project.get_length() != 0);
    
        export_action.set_sensitive(project.can_export());
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
            case KeySyms.UP:
                project.go_previous();
                return true;
            case KeySyms.DOWN:
                project.go_next();
                return true;
            case KeySyms.LEFT:
                project.go_previous_frame();
                return true;
            case KeySyms.RIGHT:
                project.go_next_frame();
                return true;
        }
        return base.key_press_event(event);
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
            export_connector = new View.OggVorbisExport(
                View.MediaConnector.MediaTypes.Audio | View.MediaConnector.MediaTypes.Video,
                filename, project.media_engine.get_project_audio_export_caps());
            project.media_engine.connect_output(export_connector);
            project.media_engine.start_export(filename);
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
    
    void on_undo_changed(bool can_undo) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_undo_changed");
        Gtk.MenuItem? undo = (Gtk.MenuItem?) get_widget(manager, "/MenuBar/EditMenu/EditUndo");
        assert(undo != null);
        undo.set_label("_Undo " + project.undo_manager.get_undo_title());
        undo.set_sensitive(can_undo);
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
    
    void on_save_graph() {
        project.print_graph(project.media_engine.pipeline, "save_graph");
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

    ClassFactory.set_class_factory(new ClassFactory());
    new App(project_file);
    Gtk.main();
}

