/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class Recorder : Gtk.Window {
    public Project project;
    
    HeaderArea header_area;
    TimeLine timeline;
    Gtk.Adjustment h_adjustment;
    int cursor_pos = -1;
    
    Gtk.Action delete_action;
    Gtk.Action record_action;
    
    Gtk.ToggleToolButton play_button;
    Gtk.ToggleToolButton record_button;
    
    const Gtk.ActionEntry[] entries = {
        { "File", null, "_File", null, null, null },
        { "NewProject", Gtk.STOCK_NEW, "_New...", null, "Create new project", on_project_new },
        { "Export", Gtk.STOCK_JUMP_TO, "_Export...", null, null, on_export },
        { "Save", Gtk.STOCK_SAVE, "_Save", null, "Save project", on_project_save },
        { "Quit", Gtk.STOCK_QUIT, null, null, null, on_quit },
        
        { "Edit", null, "_Edit", null, null, null },
        { "Delete", Gtk.STOCK_DELETE, "_Delete", "Delete", null, on_delete },

        { "Track", null, "_Track", null, null, null },
        { "NewTrack", Gtk.STOCK_ADD, "_New", null, "Create new track", on_track_new },
        { "Rename", null, "_Rename...", null, "Rename track", on_track_rename },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, null, null, null, on_about },
        
        { "Rewind", Gtk.STOCK_MEDIA_PREVIOUS, null, "Return", "Go to beginning", on_rewind }
    };
    
    const Gtk.ToggleActionEntry[] toggle_entries = {
        { "Play", Gtk.STOCK_MEDIA_PLAY, null, "space", "Play", on_play },
        { "Record", Gtk.STOCK_MEDIA_RECORD, null, "r", "Record", on_record }
    };
    
    const string ui = """
<ui>
  <menubar name="MenuBar">
    <menu name="FileMenu" action="File">
      <menuitem name="FileExport" action="Export"/>
      <menuitem name="FileNew" action="NewProject" />
      <menuitem name="FileSave" action="Save" />
      <menuitem name="FileQuit" action="Quit"/>
    </menu>
    <menu name="EditMenu" action="Edit">
      <menuitem name="EditDelete" action="Delete"/>
    </menu>
    <menu name="TrackMenu" action="Track">
      <menuitem name="TrackNew" action="NewTrack"/>
      <menuitem name="TrackRename" action="Rename" />
    </menu>
    <menu name="HelpMenu" action="Help">
      <menuitem name="HelpAbout" action="About"/>
    </menu>
  </menubar>
  <toolbar name="Toolbar">
    <toolitem name="New" action="NewTrack"/>
    <separator/>
    <toolitem name="Rewind" action="Rewind"/>
    <toolitem name="Play" action="Play"/>
    <toolitem name="Record" action="Record"/>
  </toolbar>
  <accelerator name="Rewind" action="Rewind"/>
  <accelerator name="Play" action="Play"/>
  <accelerator name="Record" action="Record"/>
</ui>
""";
    
    public Recorder() {
        project = new Project();
        project.audio_engine.fire_state_changed += on_state_changed;
        project.audio_engine.fire_callback_pulse += on_callback_pulse;
        
        set_position(Gtk.WindowPosition.CENTER);
        title = "fillmore";
        set_size_request(600, 400);
        
        Gtk.ActionGroup group = new Gtk.ActionGroup("main");
        group.add_actions(entries, this);
        group.add_toggle_actions(toggle_entries, this);

        delete_action = group.get_action("Delete");    
        delete_action.set_sensitive(false);
        record_action = group.get_action("Record");
        
        Gtk.UIManager manager = new Gtk.UIManager();
        manager.insert_action_group(group, 0);
        manager.add_ui_from_string(ui, -1);
        
        Gtk.MenuBar menubar = (Gtk.MenuBar) get_widget(manager, "/MenuBar");
        Gtk.Toolbar toolbar = (Gtk.Toolbar) get_widget(manager, "/Toolbar");
        play_button = (Gtk.ToggleToolButton) get_widget(manager, "/Toolbar/Play");
        record_button = (Gtk.ToggleToolButton) get_widget(manager, "/Toolbar/Record");
        
        timeline = new TimeLine(this);
        timeline.selection_changed += on_selection_changed;
        
        Gtk.HBox hbox = new Gtk.HBox(false, 0);
        header_area = new HeaderArea(this);
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
        
        add_accel_group(manager.get_accel_group());
        timeline.grab_focus();
        destroy += on_quit;
        
        select(project.tracks[0]);
    }
    
    Gtk.Widget get_widget(Gtk.UIManager manager, string name) {
        Gtk.Widget widget = manager.get_widget(name);
        if (widget == null)
            error("can't find widget");
        return widget;
    }
    
    void on_state_changed(PlayState state) {
        record_action.set_sensitive(state != PlayState.PLAYING);
        
        // While recording, we disable the play button but keep its action enabled
        // so that its shortcut (Space) can be used to stop recording.
        play_button.set_sensitive(state != PlayState.RECORDING);
        
        if (state == PlayState.STOPPED) {
            play_button.set_active(false);
            record_button.set_active(false);
            cursor_pos = -1;
        }
    }
    
    void on_selection_changed(TimeLine timeline, RegionView? new_selection) {
        delete_action.set_sensitive(new_selection != null);
    }
    
    public void select(Track track) {
        header_area.select(track);
    }
    
    public Track? selected_track() {
        foreach (Track t in project.tracks)
            if (t.header.state == Gtk.StateType.SELECTED)
                return t;
        error("can't find selected track");
        return null;
    }
    
    public void scroll_to_beginning() {
        h_adjustment.set_value(0.0);
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
    
    // File menu
    
    void on_export() {
        Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(
            "Export", this, Gtk.FileChooserAction.SAVE,
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, "_Export", Gtk.ResponseType.ACCEPT);
        dialog.set_current_name("Untitled.wav");
        if (dialog.run() == Gtk.ResponseType.ACCEPT)
            project.export(dialog.get_filename());
        dialog.destroy();
    }
    
    void on_project_new() {
        Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(
            "Project location", this, Gtk.FileChooserAction.CREATE_FOLDER,
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            "_Save", Gtk.ResponseType.ACCEPT);
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            project.set_project_path(dialog.get_filename());
        }
        dialog.destroy();
    }
    
    void on_project_save() {
    }
    
    void on_quit() {
        project.close();
        Gtk.main_quit();
    }
    
    // Edit menu

    void on_delete() {
        Region r = timeline.selected.region;
        r.track.remove(r);
    }
    
    // Track menu

    void on_track_new() {
        UI.TrackInformation dialog = new UI.TrackInformation();
        dialog.set_track_name(project.get_default_track_name());
        if (dialog.run() == Gtk.ResponseType.OK) {
            string track_name = dialog.get_track_name();
            if (track_name != "") {
                project.add_named_track(track_name);
            }
        }
        dialog.destroy();
    }
    
    void on_track_rename() {
        UI.TrackInformation dialog = new UI.TrackInformation();
        dialog.set_title("Rename track");
        dialog.set_track_name(selected_track().name);
        if (dialog.run() == Gtk.ResponseType.OK) {
            string track_name = dialog.get_track_name();
            if (track_name != "") {
                project.rename_track(dialog.get_track_name(), selected_track());
            }
        }
        dialog.destroy();
    }

    // Help menu
    
    void on_about() {
        Gtk.show_about_dialog(this,
          "version", "0.1",
          "comments", "a multitrack recorder",
          "copyright", "(c) 2009 yorba"
        );
    }
    
    // toolbar
    
    void on_rewind() {
        project.rewind();
        scroll_to_beginning();
    }
    
    void on_play() {
        if (project.recording())
            project.stop();     // will reset both buttons
        else if (play_button.get_active())
            project.play();
        else
            project.stop();
    }
    
    void on_record() {
        if (record_button.get_active())
            project.record(selected_track());
        else
            project.stop();
    }

    void on_callback_pulse() {
        if (timeline != null) {
            timeline.update();
        }
    }
        
    // main
    
    static void main(string[] args) {
        Gtk.init(ref args);
        GLib.Environment.set_application_name("fillmore");
        
        Gst.init(ref args);
        
        Recorder recorder = new Recorder();
        recorder.show_all();
    
        Gtk.main();
    }

}

