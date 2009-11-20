/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Gee;
using Logging;

public class TimeLine : Gtk.EventBox {
    public Model.Project project;
    public weak Model.TimeSystem provider;
    public View.Ruler ruler;
    ArrayList<TrackView> tracks = new ArrayList<TrackView>();
    Gtk.VBox vbox;
    
    public ArrayList<ClipView> selected_clips = new ArrayList<ClipView>();
    public Model.Clip clipboard_clip = null;
    
    public const int BAR_HEIGHT = 20;
    public const int BORDER = 4;

    public signal void selection_changed(bool selected);
    public signal void track_changed();

    float pixel_div;
    float pixel_min = 0.1f;
    float pixel_max = 4505.0f;
    
    public const int RULER_HEIGHT = 20;
    public GapView gap_view;
    Gdk.Cursor hand_cursor = new Gdk.Cursor(Gdk.CursorType.HAND1);
    Gdk.Cursor plus_cursor = new Gdk.Cursor(Gdk.CursorType.PLUS); // This will be used for ctrl-drag

    public TimeLine(Model.Project p, Model.TimeSystem provider) {
        project = p;
        this.provider = provider;
        
        vbox = new Gtk.VBox(false, 0);
        ruler = new View.Ruler(provider, RULER_HEIGHT);
        ruler.position_changed += on_ruler_position_changed;
        vbox.pack_start(ruler, false, false, 0);
        
        project.track_added += on_track_added;
        project.track_removed += on_track_removed;
        project.media_engine.position_changed += on_position_changed;
        add(vbox);
        
        modify_bg(Gtk.StateType.NORMAL, parse_color("#444"));
        modify_fg(Gtk.StateType.NORMAL, parse_color("#f00"));
        
        pixel_div = pixel_max / pixel_min;
        provider.calculate_pixel_step (0.5f, pixel_min, pixel_div);
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, drag_target_entries, Gdk.DragAction.COPY);
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
    
    void on_track_added(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_added");
        TrackView track_view = new TrackView(track, this);
        track_view.clip_view_added += on_clip_view_added;
        tracks.add(track_view);
        vbox.pack_start(track_view, false, false, 0);
        if (track.media_type() == Model.MediaType.VIDEO) {
            vbox.reorder_child(track_view, 1);
        }
        vbox.show_all();
    }
    
    void on_track_removed(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_removed");
        foreach (TrackView track_view in tracks) {
            if (track_view.track == track) {
                vbox.remove(track_view);
                tracks.remove(track_view);
                break;
            }
        }
    }
    
    public void on_clip_view_added(ClipView clip_view) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_clip_view_added");
        clip_view.selection_request += on_clip_view_selection_request;
        clip_view.move_request += on_clip_view_move_request;
        clip_view.move_commit += on_clip_view_move_commit;
        clip_view.move_begin += on_clip_view_move_begin;
    }
    
    public void deselect_all_clips() {
        foreach(ClipView selected_clip_view in selected_clips) {
            selected_clip_view.is_selected = false;
        }
        selected_clips.clear();
    }
    
    void on_clip_view_move_begin(ClipView unused) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_move_begin");
        window.set_cursor(hand_cursor);
        foreach (ClipView selected_clip in selected_clips) {
            selected_clip.initial_time = selected_clip.clip.start;
            selected_clip.clip.gnonlin_disconnect();
            TrackView track_view = selected_clip.get_parent() as TrackView;
            track_view.track.remove_clip_from_array(selected_clip.clip);
        }    
    }

    void on_clip_view_selection_request(ClipView clip_view, bool extend) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_selection_request");
        if (gap_view != null) {
            gap_view.unselect();
        }
        
        bool in_selected_clips = selected_clips.contains(clip_view);
        if (!extend) {
            if (!in_selected_clips) {
                deselect_all_clips();
                clip_view.is_selected = true;
                selected_clips.add(clip_view);
            }
        } else {
            if (selected_clips.size > 1) {
                if (in_selected_clips && clip_view.is_selected) {
                    clip_view.is_selected = false;
                    selected_clips.remove(clip_view);
                }
            }
            if (!in_selected_clips) {
                clip_view.is_selected = true;
                selected_clips.add(clip_view);
            }
        }
        track_changed();
        selection_changed(is_clip_selected());
        queue_draw();
    }

    void on_clip_view_move_commit(ClipView clip_view, int delta) {
        window.set_cursor(null);
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_move_request");
        foreach (ClipView selected_clip_view in selected_clips) {
            TrackView track_view = selected_clip_view.get_parent() as TrackView;
            selected_clip_view.clip.gnonlin_connect();
            track_view.track.move(selected_clip_view.clip, 
                 selected_clip_view.clip.start, selected_clip_view.initial_time);
        }
    }
        
    void on_clip_view_move_request(ClipView clip_view, int delta) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_move_request");
        if (move_allowed(ref delta)) {
            move_the_clips(delta);
        }    
    }
    
    bool move_allowed(ref int move_distance) {
        foreach(ClipView clip_view in selected_clips) {
            int position = provider.time_to_xpos(clip_view.clip.start);
            if ((position + move_distance) < BORDER) {
                return false;
            }
        }
        return true;
    }

    void move_the_clips(int move_distance) {
        foreach (ClipView clip_view in selected_clips) {
            do_clip_move(clip_view, move_distance);
        }
    }
    
    public void do_clip_move(ClipView clip_view, int delta) {
        clip_view.clip.start += provider.xsize_to_time(delta);
    }

    public void on_ruler_position_changed(int x) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_ruler_position_changed");
        update_pos(x);
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
                selected_clips.remove_at(0);
            }
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
        TrackView? view = c.type == Model.MediaType.VIDEO ? 
            find_video_track_view() : null;
        if (view == null) {
            foreach (TrackView track_view in tracks) {
                if (track_view.track.get_is_selected()) {
                    view = track_view;
                }
            }
            // TODO: Lombard doesn't use selected state.  The following check should be removed
            // when it does
            if (view == null) {
                view = find_audio_track_view();
            }
        }
        if (view != null) {
            view.track.do_clip_paste(c, pos, new_clip);
        }
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

    public override void drag_data_received(Gdk.DragContext context, int x, int y,
                                            Gtk.SelectionData selection_data, uint drag_info,
                                            uint time) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_drag_data_received");
        string[] a = selection_data.get_uris();
        Gtk.drag_finish(context, true, false, time);
        
        Model.Track? track = null;
        TrackView? track_view = find_child(x, y) as TrackView;
        
        if (track_view == null) {
            return;
        }
        
        track = track_view.track;
        
        project.create_clip_importer(track, true);

        foreach (string s in a) {
            string filename;
            try {
                filename = GLib.Filename.from_uri(s);
            } catch (GLib.ConvertError e) { continue; }
            project.importer.add_file(filename);
        }
        project.importer.start();
    }

    public void update_pos(int event_x) {
        int64 time = provider.xpos_to_time(event_x);
        
        project.snap_coord(out time, provider.get_pixel_snap_time());
        project.media_engine.go(time);
    }

    public Gtk.Widget? find_child(double x, double y) {
        foreach (Gtk.Widget w in vbox.get_children()) {
            if (w.allocation.y <= y && y < w.allocation.y + w.allocation.height)
                return w;
        }
        return null;
    }

    public override bool button_press_event(Gdk.EventButton event) {
        if (gap_view != null)
            gap_view.unselect();
      
        Gtk.Widget? drag = find_child(event.x, event.y);
        if (drag != null) {
            drag.button_press_event(event);
        }
        queue_draw();

        return true;
    }

    TrackView? find_video_track_view() {
        foreach (TrackView track in tracks) {
            if (track.track.media_type() == Model.MediaType.VIDEO) {
                return track;
            }
        }
        
        return null;
    }
    
    TrackView? find_audio_track_view() {
        foreach (TrackView track in tracks) {
            if (track.track.media_type() == Model.MediaType.AUDIO) {
                return track;
            }
        }
        
        return null;
    }
}
