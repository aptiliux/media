/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Gee;
using Logging;

class TimeLine : Gtk.EventBox {
    public Model.Project project;
    public weak Model.TimeSystem provider;
    View.Ruler ruler;
    ArrayList<TrackView> tracks = new ArrayList<TrackView>();
    Gtk.VBox vbox;
    
    public ArrayList<ClipView> selected_clips = new ArrayList<ClipView>();
    public int selected_clip_index = 0;
    public Model.Clip clipboard_clip = null;
    
    public Gtk.Menu context_menu;
    
    public const int BAR_HEIGHT = 20;
    public const int BORDER = 4;

    public signal void selection_changed(bool selected);
    public signal void track_changed();

    float pixel_div;
    float pixel_min = 0.1f;
    float pixel_max = 4505.0f;
    
    public const int RULER_HEIGHT = 20;
    public GapView gap_view;

    public TimeLine(Model.Project p, Model.TimeSystem provider) {
        project = p;
        this.provider = provider;
        
        vbox = new Gtk.VBox(false, 0);
        ruler = new View.Ruler(provider, RULER_HEIGHT);
        ruler.position_changed += on_ruler_position_changed;
        vbox.pack_start(ruler, false, false, 0);
        
        foreach (Model.Track track in project.tracks) {
            tracks.add(new TrackView(track, this));
        }
        project.media_engine.position_changed += on_position_changed;
        vbox.pack_start(find_video_track_view(), false, false, 0);
        vbox.pack_start(find_audio_track_view(), false, false, 0);
        add(vbox);
        
        modify_bg(Gtk.StateType.NORMAL, parse_color("#444"));
        modify_fg(Gtk.StateType.NORMAL, parse_color("#f00"));
        
        pixel_div = pixel_max / pixel_min;
        provider.calculate_pixel_step (0.5f, pixel_min, pixel_div);
    }

    public void zoom_to_project(double width) {
        if (project.get_length() == 0)
            return;
        double numerator = GLib.Math.log(
                    (width * Gst.SECOND) / ((double) project.get_length() * (double) pixel_min));
        double denominator = GLib.Math.log((double) pixel_div);
        
        zoom((float) (numerator / denominator) - provider.get_pixel_percentage());
    }
    
    public void zoom (float inc) {
        provider.calculate_pixel_step(inc, pixel_min, pixel_div);
        foreach (TrackView track in tracks) {
            track.resize();
        }
        project.media_engine.position_changed(project.transport_get_position());
        queue_draw();
    }
    
    void on_position_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_position_changed");        
        queue_draw();
    }
    
    public void on_ruler_position_changed(int x) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_ruler_position_changed");
        update_pos(x);
    }

    public void select_clip(ClipView? clip_view) {
        if (clip_view != null) {
            if (!clip_view.is_selected) {
                selected_clips.add(clip_view);
                clip_view.is_selected = true;
            }
        } else {
            foreach (ClipView clip in selected_clips) {
                clip.is_selected = false;
            }
            selected_clips.clear();
        }
        queue_draw();
        selection_changed(true);
    }
    
    public void unselect_clip(ClipView clip_view) {
        clip_view.is_selected = false;
        if (selected_clips.contains(clip_view)) {
            selected_clips.remove(clip_view);
            queue_draw();
            selection_changed(false);
        }
    }
    
    public bool is_clip_selected() {
        return selected_clips.size > 0;
    }
    
    public bool gap_selected() {
        return gap_view != null;
    }
    
    public void delete_selection() {
        if (is_clip_selected()) {
            while (selected_clips.size > 0) {
                selected_clips[0].delete_clip();
            }
            select_clip(null);
        } else {
            if (gap_view != null) {
                if (!project.can_delete_gap(gap_view.gap)) {
                    if (DialogUtils.delete_cancel("Really delete single-track gap?") ==
                           Gtk.ResponseType.YES) {
                        gap_view.remove();
                    }
                } else {
                    project.delete_gap(gap_view.gap);
                }
                
                gap_view.unselect();
            }
        }
    }
    
    public void do_cut() {
        assert(selected_clips.size == 1);
        clipboard_clip = selected_clips[0].clip;
        delete_selection();
    }
    
    public void do_copy() {
        assert(selected_clips.size == 1);
        clipboard_clip = selected_clips[0].clip;
        selection_changed(true);
    }
    
    public void paste() {
        do_paste(clipboard_clip.copy(), project.transport_get_position(), true);
    }
    
    public void do_paste(Model.Clip c, int64 pos, bool new_clip) {
        TrackView view = c.type == Model.MediaType.VIDEO ? 
            find_video_track_view() : find_audio_track_view();
        view.track.do_clip_paste(c, pos, new_clip);
        queue_draw();
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        base.expose_event(event);

        int xpos = provider.time_to_xpos(project.transport_get_position());
        Gdk.draw_line(window, style.fg_gc[(int) Gtk.StateType.NORMAL],
                      xpos, 0,
                      xpos, allocation.height);
        
        foreach (TrackView track in tracks) {
            if (track.dragging && track.drag_intersect) {
                Gdk.draw_line(window, style.white_gc, 
                            track.drag_x_coord, 0, 
                            track.drag_x_coord, allocation.height);
            }
        }
        return true;
    }

    public void update_pos(int event_x) {
        int64 time = provider.xpos_to_time(event_x);
        
        project.snap_coord(out time, provider.get_pixel_snap_time());
        project.media_engine.go(time);
    }

    public Gtk.Widget? find_child(double x, double y) {
        foreach (Gtk.Widget w in vbox.get_children())
            if (w.allocation.y <= y && y < w.allocation.y + w.allocation.height)
                return w;
        return null;
    }

    public override bool button_press_event(Gdk.EventButton event) {
        if (gap_view != null)
            gap_view.unselect();
      
        Gtk.Widget? drag = find_child(event.x, event.y);
        if (drag != null)
            drag.button_press_event(event);
        queue_draw();
        
        return false;
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        Gtk.Widget? drag = find_child(event.x, event.y);
        if (drag != null) {
            drag.motion_notify_event(event);
            queue_draw();
        }
        return false;
    }

    public override bool button_release_event(Gdk.EventButton event) {
        Gtk.Widget? drag = find_child(event.x, event.y);
        if (drag != null) {
            drag.button_release_event(event);
            drag = null;
            queue_draw();
        }
        
        if (is_clip_selected() && event.button == 3) {
            context_menu.select_first(true);
            context_menu.popup(null, null, null, 0, 0);
        } else {
            context_menu.popdown();
        }

        return false;
    }

    TrackView? find_video_track_view() {
        foreach (TrackView track in tracks) {
            if (track.track is Model.VideoTrack) {
                return track;
            }
        }
        
        return null;
    }
    
    TrackView? find_audio_track_view() {
        foreach (TrackView track in tracks) {
            if (track.track is Model.AudioTrack) {
                return track;
            }
        }
        
        return null;
    }
}
