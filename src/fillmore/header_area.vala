/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

class TrackSeparator : Gtk.HSeparator {
//this class is referenced in the resource file
}

public class MuteToggleButton : Gtk.ToggleButton {
//this class is referenced in the resource file
}

public class SoloToggleButton : Gtk.ToggleButton {
//this class is referenced in the resource file
}

public class TrackHeader : Gtk.EventBox {
    protected weak Model.Track track;
    protected weak HeaderArea header_area;
    protected Gtk.Label track_label;

    public const int width = 250;

    public virtual void setup(Gtk.Builder builder, Model.Track track, HeaderArea area, int height) {
        this.track = track;
        this.header_area = area;

        track.track_renamed.connect(on_track_renamed);
        track.track_selection_changed.connect(on_track_selection_changed);
        set_size_request(width, height);

        track_label = (Gtk.Label) builder.get_object("track_label");
        track_label.set_text(track.display_name);
        track_label.modify_fg(Gtk.StateType.NORMAL, parse_color("#fff"));
    }

    void on_track_renamed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_renamed");
        track_label.set_text(track.display_name);
    }

    void on_track_selection_changed(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_selection_changed");
        if (track.get_is_selected()) {
            modify_bg(Gtk.StateType.NORMAL, parse_color("#68A"));
            track_label.modify_fg(Gtk.StateType.NORMAL, parse_color("#FFF"));
        } else {
            modify_bg(Gtk.StateType.NORMAL, parse_color("#666"));
            track_label.modify_fg(Gtk.StateType.NORMAL, parse_color("#222"));
        }
    }

    public override bool button_press_event(Gdk.EventButton event) {
        header_area.select(track);
        return true;
    }

    public Model.Track get_track() {
        return track;
    }
}

public class SliderBase : Gtk.HScrollbar {
    Gdk.Pixbuf slider_image;
    construct {
        can_focus = true;
        try {
            slider_image = new Gdk.Pixbuf.from_file(
                AppDirs.get_resources_dir().get_child("dot.png").get_path());
        } catch (GLib.Error e) {
            warning("Could not load resource for slider: %s", e.message);
        }
    }

    public override bool expose_event (Gdk.EventExpose event) {
        Gdk.GC gc = style.fg_gc[(int) Gtk.StateType.NORMAL];
        int radius = (slider_end - slider_start) / 2;
        int center = allocation.x + slider_start + radius;
        int height = allocation.y + allocation.height / 2;

        event.window.draw_rectangle(gc, false,
            allocation.x + radius, height - 2, allocation.width - 2 * radius, 1);

        event.window.draw_pixbuf(gc, slider_image, 0, 0, center - radius, allocation.y + 2, 
            slider_image.get_width(), slider_image.get_height(), Gdk.RgbDither.NORMAL, 0, 0);
        return true;
    }
}

public class PanSlider : SliderBase {
    construct {
    }
}

public class VolumeSlider : SliderBase {
    construct {
    }
}

public class AudioTrackHeader : TrackHeader {
    public VolumeSlider pan;
    public VolumeSlider volume;
    MuteToggleButton mute;
    SoloToggleButton solo;

    public override void setup(Gtk.Builder builder, Model.Track track, 
            HeaderArea header, int height) {
        base.setup(builder, track, header, height);
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        View.AudioMeter audio_meter = (View.AudioMeter) builder.get_object("audiometer1");

        mute = (MuteToggleButton) builder.get_object("mute");
        solo = (SoloToggleButton) builder.get_object("solo");

        pan = (VolumeSlider) builder.get_object("track_pan");
        volume = (VolumeSlider) builder.get_object("track_volume");
        volume.get_adjustment().set_value(audio_track.get_volume());
        pan.get_adjustment().set_value(audio_track.get_pan());
        audio_meter.setup(audio_track);
        audio_track.parameter_changed.connect(on_parameter_changed);
        audio_track.indirect_mute_changed.connect(on_indirect_mute_changed);
        audio_track.mute_changed.connect(on_mute_changed);
        audio_track.solo_changed.connect(on_solo_changed);
    }

    public void on_mute_toggled(MuteToggleButton button) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_mute_toggled");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        audio_track.mute = button.active;
        if (audio_track.mute) {
            audio_track.solo = false;
        }
    }

    public void on_solo_toggled(SoloToggleButton button) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_solo_toggled");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        audio_track.solo = button.active;
    }

    void on_indirect_mute_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_indirect_mute_changed");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        if (audio_track != null) {
            mute.set_sensitive(!audio_track.indirect_mute);
        }
    }

    void on_mute_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_indirect_mute_changed");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        if (audio_track != null) {
            if (audio_track.mute != mute.active) {
                mute.set_active(audio_track.mute);
            }
        }
    }

    void on_solo_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_indirect_mute_changed");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        if (audio_track != null) {
            if (audio_track.solo != solo.active) {
                solo.set_active(audio_track.solo);
            }
        }
    }

    public void on_pan_value_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_pan_value_changed");
        Model.AudioTrack audio_track = track as Model.AudioTrack;
        if (audio_track != null) {
            Gtk.Adjustment adjustment = pan.get_adjustment();
            audio_track.set_pan(adjustment.get_value());
        }
    }

    public void on_volume_value_changed() {
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

public class HeaderArea : Gtk.EventBox {
    weak Model.Project project;
    
    Gtk.VBox vbox;
    public Gdk.Color background_color = parse_color("#666");
    
    public HeaderArea(Recorder recorder, Model.TimeSystem provider, int height) {
        this.project = recorder.project;
        recorder.timeline.trackview_removed.connect(on_trackview_removed);
        recorder.timeline.trackview_added.connect(on_trackview_added);
        
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

        Gtk.Builder builder = new Gtk.Builder();
        try {
            builder.add_from_file(AppDirs.get_resources_dir().get_child("fillmore.glade").get_path());
        } catch(GLib.Error e) {
            warning("%s\n", e.message);
            return;
        }
        builder.connect_signals(null);
        AudioTrackHeader header = (AudioTrackHeader) builder.get_object("HeaderArea");
        header.setup(builder, audio_track, this, trackview.get_track_height() - 2);
            // - 2 allows room for TrackSeparator

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
                if (track_header != null && track_header.get_track() == track) {
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

