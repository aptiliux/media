/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
// TODO This class will go away when XML loading is cleaned up
class VideoTrack : Track {

    public VideoTrack(Model.Project project) {
        base(project, "Video Track");
    }

    protected override string name() { return "video"; }

    protected override Gst.Element empty_element() {
        return (Gst.Element) null;
    }
    
    protected override void check(Clip clip) {
    }
    
    int64 frame_to_time(int frame) {
        return 0;
    }
    
    int time_to_frame(int64 time) {
        return 0;
    }
    
    public int get_current_frame(int64 time) {
        return 0;
    }
    
    public int64 previous_frame(int64 position) {
        return 0;
    }
    
    public int64 next_frame(int64 position) {
        return 0;
    }

    public bool get_framerate(out Fraction rate) {
        return false;
    }
}
}

class Recorder : Gtk.Window {
    public Model.AudioProject project;
    
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
        { "Save", Gtk.STOCK_SAVE, "_Save", null, "Save project", on_project_save },
        { "Export", Gtk.STOCK_JUMP_TO, "_Export...", "<Control>E", null, on_export },
        { "Quit", Gtk.STOCK_QUIT, null, null, null, on_quit },
        
        { "Edit", null, "_Edit", null, null, null },
        { "Delete", Gtk.STOCK_DELETE, "_Delete", "Delete", null, on_delete },

        { "Track", null, "_Track", null, null, null },
        { "NewTrack", Gtk.STOCK_ADD, "_New", null, "Create new track", on_track_new },
        { "Rename", null, "_Rename...", null, "Rename track", on_track_rename },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, null, null, null, on_about },
        { "SaveGraph", null, "Save _Graph", null, "Save graph", on_save_graph },
        
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
      <menuitem name="FileNew" action="NewProject" />
      <menuitem name="FileSave" action="Save" />
      <separator />
      <menuitem name="FileExport" action="Export"/>
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
      <menuitem name="SaveGraph" action="SaveGraph" />
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
        project = new Model.AudioProject();
        
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
        
        Gtk.MenuItem? save_graph = (Gtk.MenuItem?) 
            get_widget(manager, "/MenuBar/HelpMenu/SaveGraph");

        // TODO: only destroy it if --debug is not specified on the command line
        // or conversely, only add it if --debug is specified on the command line
        if (save_graph != null) {
            save_graph.destroy();
        }
        
        add_accel_group(manager.get_accel_group());
        timeline.grab_focus();
        destroy += on_quit;
        project.load(null);
        project.add_track(new Model.AudioTrack(project, get_default_track_name()));
        select(project.tracks[0]);
    }
    
    public string get_default_track_name() {
        int i = project.tracks.size + 1;
        return "track %d".printf(i);
    }
   
    Gtk.Widget get_widget(Gtk.UIManager manager, string name) {
        Gtk.Widget widget = manager.get_widget(name);
        if (widget == null)
            error("can't find widget");
        return widget;
    }
    
    void on_state_changed(Model.PlayState state) {
        record_action.set_sensitive(state != Model.PlayState.PLAYING);
        
        // While recording, we disable the play button but keep its action enabled
        // so that its shortcut (Space) can be used to stop recording.
        play_button.set_sensitive(state != Model.PlayState.RECORDING);
        
        if (state == Model.PlayState.STOPPED) {
            play_button.set_active(false);
            record_button.set_active(false);
            cursor_pos = -1;
        }
    }
    
    void on_selection_changed(TimeLine timeline, RegionView? new_selection) {
        delete_action.set_sensitive(new_selection != null);
    }
    
    public void select(Model.Track track) {
        header_area.select(track);
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
        Gtk.FileChooserDialog d = new Gtk.FileChooserDialog("Export", this, 
                                                                Gtk.FileChooserAction.SAVE,
                                                                Gtk.STOCK_CANCEL, 
                                                                Gtk.ResponseType.CANCEL,
                                                                Gtk.STOCK_SAVE, 
                                                                Gtk.ResponseType.ACCEPT, null);
            
        Gtk.FileFilter filter = new Gtk.FileFilter();
        filter.set_name("Ogg Files");
        filter.add_pattern("*.ogg");
        
        d.add_filter(filter);
        
        if (d.run() == Gtk.ResponseType.ACCEPT) {
            string filename = append_extension(d.get_filename(), "ogg");

            if (!FileUtils.test(filename, FileTest.EXISTS) || confirm_replace(this, filename)) {
                MultiFileProgress export_dialog = new MultiFileProgress(this, 1, "Export", project);
                project.start_export(filename);
            }
        }
        d.destroy();
    }
    
    void on_project_new() {
        Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(
            "Project location", this, Gtk.FileChooserAction.CREATE_FOLDER,
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            "_Save", Gtk.ResponseType.ACCEPT);
//        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
//            project.set_project_path(dialog.get_filename());
//        }
        dialog.destroy();
    }
    
    void on_project_save() {
    }
    
    void on_quit() {
        //project.close();
        Gtk.main_quit();
    }
    
    // Edit menu

    void on_delete() {
        Model.Clip clip = timeline.selected.region;
        selected_track().delete_clip(clip, false);
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

    // Help menu
    
    void on_about() {
        Gtk.show_about_dialog(this,
          "version", "%1.2lf".printf(project.get_version()),
          "comments", "a multitrack recorder",
          "copyright", "(c) 2009 yorba"
        );
    }
    
    void on_save_graph() {
        project.print_graph(project.pipeline, "save_graph");
    }

    // toolbar
    
    void on_rewind() {
        project.go(0);
        scroll_to_beginning();
    }
    
    void on_play() {
        /*if (project.recording())
            project.stop();     // will reset both buttons
        else */
        if (play_button.get_active())
            project.play();
        else
            project.pause();
    }
    
    void on_record() {
        if (record_button.get_active())
            project.record(selected_track());
        else
            project.pause();
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

