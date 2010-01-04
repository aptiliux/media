/* Copyright 2009-2010 Yorba Foundation
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
    
    public TrackHeader(Model.Track track, HeaderArea area, int height) {
        this.track = track;
        this.header_area = area;
        
        track.track_renamed += on_track_renamed;
        track.track_selection_changed += on_track_selection_changed;
        set_size_request(width, height);
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

public class SliderBase : Gtk.HScrollbar {
    protected string label;
    construct {
        can_focus = true;
    }
    
    public override bool expose_event (Gdk.EventExpose event) {
        Gdk.GC gc = style.fg_gc[(int) Gtk.StateType.NORMAL];

        int radius = (slider_end - slider_start) / 2;
        int center = allocation.x + slider_start + radius;
        int height = allocation.y + allocation.height / 2;

        event.window.draw_rectangle(gc, false,
            allocation.x + radius, height, allocation.width - 2 * radius, 1);

        gc = style.fg_gc[(int) Gtk.StateType.SELECTED];
        event.window.draw_arc(gc, true, 
            center - radius, allocation.y + 2,
            radius * 2, radius * 2, 0, 360 * 64);
        
        gc = style.fg_gc[(int) Gtk.StateType.NORMAL];
        Pango.Layout layout = create_pango_layout(label);
        Pango.FontDescription f = Pango.FontDescription.from_string("Sans 8");
        layout.set_font_description(f);
        int text_width, text_height;
        layout.get_pixel_size(out text_width, out text_height);
        Gdk.draw_layout(event.window, style.black_gc, 
            center - text_width / 2, allocation.y + 3, layout);
        return true;
    }
}

class PanSlider : SliderBase {
    construct {
        label = "P";
    }
}

public class VolumeSlider : SliderBase {
    construct {
        label = "V";
    }
}

class AudioTrackHeader : TrackHeader {
    public PanSlider pan;
    public VolumeSlider volume;
    
    public AudioTrackHeader(Model.AudioTrack track, HeaderArea header, int height) {
        base(track, header, height);
        pan = new PanSlider();
        pan.set_adjustment(new Gtk.Adjustment(track.get_pan(), -1, 1, 0.1, 0.1, 0.0));
        pan.value_changed += on_pan_value_changed;
        
        volume = new VolumeSlider();
        volume.set_adjustment(new Gtk.Adjustment(track.get_volume(), 0, 1.5, 0.01, 1, 0));
        volume.value_changed += on_volume_value_changed;

        track.parameter_changed += on_parameter_changed;

        Gtk.VBox vbox = new Gtk.VBox(false, 0);
        vbox.pack_start(track_label, true, true, 0);
        View.AudioMeter meter = new View.AudioMeter(track);
        vbox.add(meter);
        
        vbox.add(pan);
        vbox.add(volume);
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
    
    Gtk.VBox vbox;
    public Gdk.Color background_color = parse_color("#666");
    
    public HeaderArea(Recorder recorder, Model.TimeSystem provider, int height) {
        this.project = recorder.project;
        recorder.timeline.trackview_removed += on_trackview_removed;
        recorder.timeline.trackview_added += on_trackview_added;
        
        set_size_request(TrackHeader.width, 0);
        modify_bg(Gtk.StateType.NORMAL, background_color);
        
        vbox = new Gtk.VBox(false, 0);
        add(vbox);
        Gtk.DrawingArea status_bar = new View.StatusBar(project, provider, height);
        
        vbox.pack_start(status_bar, false, false, 0);

        vbox.pack_start(new TrackSeparator(), false, false, 0);
        
        foreach (TrackView track in recorder.timeline.tracks) {
            on_trackview_added(track);
        }
    }
    
    public void on_trackview_added(TrackView trackview) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_trackview_added");
        Model.AudioTrack audio_track = trackview.get_track() as Model.AudioTrack;
        assert(audio_track != null);
        //we are currently only supporting audio tracks.  We'll probably have
        //a separate method for adding video track, midi track, aux input, etc

        TrackHeader header = new AudioTrackHeader(audio_track, this, trackview.get_track_height());
        vbox.pack_start(header, false, false, 0);
        vbox.pack_start(new TrackSeparator(), false, false, 0);
        vbox.show_all();
        select(audio_track);
    }
    
    public void on_trackview_removed(TrackView trackview) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_trackview_removed");
        Model.Track track = trackview.get_track();
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

