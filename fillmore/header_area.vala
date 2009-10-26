/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

class TrackHeader : Gtk.EventBox {
    protected weak Model.Track track;
    protected weak HeaderArea header_area;
    protected Gtk.Label track_label;
    
    public const int width = 100;
    
    public TrackHeader(Model.Track track, HeaderArea area) {
        this.track = track;
        this.header_area = area;
        
        track.track_renamed += on_track_renamed;
        track.track_selection_changed += on_track_selection_changed;
        
        set_size_request(width, TrackView.height + TimeLine.track_margin * 2);
        modify_bg(Gtk.StateType.NORMAL, header_area.background_color);
        modify_bg(Gtk.StateType.SELECTED, parse_color("#68a"));
        
        track_label = new Gtk.Label(track.display_name);
        track_label.modify_fg(Gtk.StateType.NORMAL, parse_color("#fff"));
    }
    
    void on_track_renamed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_renamed");
        track_label.set_text(track.display_name);
    }
    
    void on_track_selection_changed(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_selection_changed");
        set_state(track.get_is_selected() ? Gtk.StateType.SELECTED : Gtk.StateType.NORMAL);
    }
    
    public override bool button_press_event(Gdk.EventButton event) {
        header_area.select(track);
        return true;
    }
}

class AudioTrackHeader : TrackHeader {
    public Gtk.Scrollbar pan;
    public Gtk.Scrollbar volume;
    
    public AudioTrackHeader(Model.AudioTrack track, HeaderArea header) {
        base(track, header);
        pan = new Gtk.HScrollbar(new Gtk.Adjustment(track.get_pan(), -1, 1, 0.1, 0.1, 0.0));
        pan.value_changed += on_pan_value_changed;
        
        volume = new Gtk.HScrollbar(new Gtk.Adjustment(track.get_volume(), 0, 10, 0.1, 1, 0));
        volume.value_changed += on_volume_value_changed;

        track.parameter_changed += on_parameter_changed;

        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(track_label, true, true, 0);
        View.AudioMeter meter = new View.AudioMeter(track);
        vbox.add(meter);
        
        Gtk.HBox pan_hbox = new Gtk.HBox(false, 0);
        Gtk.Label pan_label = new Gtk.Label("P");
        pan_hbox.pack_start(pan_label, true, true, 0);
        pan_hbox.add(pan);
        vbox.add(pan_hbox);
        
        Gtk.HBox volume_hbox = new Gtk.HBox(false, 0);
        Gtk.Label volume_label = new Gtk.Label("V");
        volume_hbox.pack_start(volume_label, true, true, 0);
        volume_hbox.add(volume);
        
        vbox.add(volume_hbox);
        add(vbox);
    }

    void on_pan_value_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_pan_value_changed");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        if (audio_track != null) {
            Gtk.Adjustment adjustment = pan.get_adjustment();
            audio_track.set_pan(adjustment.get_value());
        }
    }
    
    void on_volume_value_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_volume_value_changed");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        if (audio_track != null) {
            Gtk.Adjustment adjustment = volume.get_adjustment();
            audio_track.set_volume(adjustment.get_value());
        }
    }

    void on_parameter_changed(Model.Parameter parameter, double new_value) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_parameter_changed");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        assert(audio_track != null);
        switch(parameter) {
            case Model.Parameter.VOLUME:
                volume.set_value(new_value);
            break;
            case Model.Parameter.PAN:
                pan.set_value(new_value);
            break;
        }
    }
}

class HeaderArea : Gtk.EventBox {
    weak Model.Project project;
    public weak Recorder recorder;
    
    Gtk.VBox vbox;
    public Gdk.Color background_color = parse_color("#666");
    
    public HeaderArea(Recorder recorder, Model.TimeSystem provider, int height) {
        this.project = recorder.project;
        this.recorder = recorder;
        project.track_added += add_track;
        project.track_removed += on_track_removed;
        
        set_size_request(TrackHeader.width, 0);
        modify_bg(Gtk.StateType.NORMAL, background_color);
        
        vbox = new Gtk.VBox(false, 0);
        add(vbox);
        Gtk.DrawingArea status_bar = new View.StatusBar(project, provider, height);
        
        vbox.pack_start(status_bar, false, false, 0);

        vbox.pack_start(separator(), false, false, 0);
        
        foreach (Model.Track track in project.tracks) {
            add_track(track);
        }
    }
    
    Gtk.HSeparator separator() {
        Gtk.HSeparator separator = new Gtk.HSeparator();
        separator.modify_bg(Gtk.StateType.NORMAL, background_color);
        return separator;
    }
    
    public void add_track(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "add_track");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        assert(audio_track != null);
        //we are currently only supporting audio tracks.  We'll probably have
        //a separate method for adding video track, midi track, aux input, etc

        TrackHeader header = new AudioTrackHeader(audio_track, this);
        vbox.pack_start(header, false, false, 0);
        vbox.pack_start(separator(), false, false, 0);
        vbox.show_all();
        select(track);
    }
    
    public void on_track_removed(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_removed");
        TrackHeader? my_track_header = null;
        Gtk.HSeparator? my_separator = null;
        foreach(Gtk.Widget widget in vbox.get_children()) {
            if (my_track_header == null) {
                TrackHeader? track_header = widget as TrackHeader;
                if (track_header != null && track_header.track == track) {
                    my_track_header = track_header;
                }
            } else {
                my_separator = widget as Gtk.HSeparator;
                break;
            }
        }
        
        if (my_track_header != null) {
            vbox.remove(my_track_header);
        }
        
        if (my_separator != null) {
            vbox.remove(my_separator);
        }

        if (project.tracks.size != 0) {
            select(project.tracks[0]);
        }
    }
    
    public void select(Model.Track track) {
        foreach (Model.Track t in project.tracks)
            t.set_selected(t == track);
    }
}

