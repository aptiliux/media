/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class TrackHeader : Gtk.EventBox {
    Track track;
    HeaderArea header_area;
    Gtk.Label track_label;
    
    public const int width = 100;
    
    public TrackHeader(Track track, HeaderArea area) {
        this.track = track;
        this.header_area = area;
        this.track.header = this;
        
        track.track_renamed +=  on_track_renamed;
        
        set_size_request(width, TrackView.height + TimeLine.track_margin * 2);
        modify_bg(Gtk.StateType.NORMAL, header_area.background_color);
        modify_bg(Gtk.StateType.SELECTED, parse_color("#68a"));
        
        track_label = new Gtk.Label(track.name);
        track_label.modify_fg(Gtk.StateType.NORMAL, parse_color("#fff"));
        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(track_label, true, true, 0);
        add(vbox);
    }
    
    void on_track_renamed() {
        track_label.set_text(track.name);
    }
    
    public override bool button_press_event(Gdk.EventButton event) {
        header_area.select(track);
        return true;
    }
}

class HeaderArea : Gtk.EventBox {
    Project project;
    public Recorder recorder;
    
    Gtk.VBox vbox;
    public Gdk.Color background_color = parse_color("#666");
    
    public HeaderArea(Recorder recorder) {
        this.project = recorder.project;
        this.recorder = recorder;
        project.track_added += add_track;
        
        set_size_request(TrackHeader.width, 0);
        modify_bg(Gtk.StateType.NORMAL, background_color);
        
        vbox = new Gtk.VBox(false, 0);
        add(vbox);
        
        Gtk.DrawingArea dummy = new Gtk.DrawingArea();
        dummy.set_size_request(0, Ruler.height);
        dummy.modify_bg(Gtk.StateType.NORMAL, background_color);
        vbox.pack_start(dummy, false, false, 0);

        vbox.pack_start(separator(), false, false, 0);
        
        foreach (Track track in project.tracks)
            add_track(project, track);
    }
    
    Gtk.HSeparator separator() {
        Gtk.HSeparator separator = new Gtk.HSeparator();
        separator.modify_bg(Gtk.StateType.NORMAL, background_color);
        return separator;
    }
    
    public void add_track(Project project, Track track) {
        TrackHeader header = new TrackHeader(track, this);
        vbox.pack_start(header, false, false, 0);
        vbox.pack_start(separator(), false, false, 0);
        vbox.show_all();
    }
    
    public void select(Track track) {
        foreach (Track t in project.tracks)
            t.header.set_state(t == track ? Gtk.StateType.SELECTED : Gtk.StateType.NORMAL);
    }
}

