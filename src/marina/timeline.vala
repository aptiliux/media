/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

public class TrackClipPair {
    public TrackClipPair(Model.Track track, Model.Clip clip) {
        this.track = track;
        this.clip = clip;
    }
    public Model.Track track;
    public Model.Clip clip;
}

public class Clipboard {
    public Gee.ArrayList<TrackClipPair> clips = new Gee.ArrayList<TrackClipPair>();
    int64 minimum_time = -1;

    public void select(Gee.ArrayList<ClipView> selected_clips) {
        clips.clear();
        minimum_time = -1;
        foreach(ClipView clip_view in selected_clips) {
            TrackView track_view = clip_view.parent as TrackView;
            if (minimum_time < 0 || clip_view.clip.start < minimum_time) {
                minimum_time = clip_view.clip.start;
            }
            TrackClipPair track_clip_pair = new TrackClipPair(track_view.get_track(), clip_view.clip);
            clips.add(track_clip_pair);
        }
    }

    public void paste(Model.Track selected_track, int64 time) {
        if (clips.size != 1) {
            foreach (TrackClipPair pair in clips) {
                pair.track.do_clip_paste(pair.clip.copy(), time + pair.clip.start - minimum_time);
            }
        } else {
            selected_track.do_clip_paste(clips[0].clip.copy(), time);
        }
    }
}

public class TimeLine : Gtk.EventBox {
    public Model.Project project;
    public weak Model.TimeSystem provider;
    public View.Ruler ruler;
    Gtk.Widget drag_widget = null;
    bool copying;
    public Gee.ArrayList<TrackView> tracks = new Gee.ArrayList<TrackView>();
    Gtk.VBox vbox;

    public Gee.ArrayList<ClipView> selected_clips = new Gee.ArrayList<ClipView>();
    public Clipboard clipboard = new Clipboard();

    public const int BAR_HEIGHT = 20;
    public const int BORDER = 4;

    public signal void selection_changed(bool selected);
    public signal void track_changed();
    public signal void trackview_added(TrackView trackview);
    public signal void trackview_removed(TrackView trackview);

    float pixel_div;
    float pixel_min = 0.1f;
    float pixel_max = 4505.0f;
    Gtk.Label high_water;

    public const int RULER_HEIGHT = 20;
    // GapView will re-emerge after 0.1 release
    // public GapView gap_view;

    public TimeLine(Model.Project p, Model.TimeSystem provider, Gdk.DragAction actions) {
        add_events(Gdk.EventMask.POINTER_MOTION_MASK);
        drag_widget = null;
        can_focus = true;
        project = p;
        this.provider = provider;
        provider.geometry_changed.connect(on_geometry_changed);

        vbox = new Gtk.VBox(false, 0);
        ruler = new View.Ruler(provider, RULER_HEIGHT);
        ruler.position_changed.connect(on_ruler_position_changed);
        vbox.pack_start(ruler, false, false, 0);

        project.track_added.connect(on_track_added);
        project.track_removed.connect(on_track_removed);
        project.media_engine.position_changed.connect(on_position_changed);
        add(vbox);

        modify_bg(Gtk.StateType.NORMAL, parse_color("#444"));
        modify_fg(Gtk.StateType.NORMAL, parse_color("#f00"));

        pixel_div = pixel_max / pixel_min;
        provider.calculate_pixel_step (0.5f, pixel_min, pixel_div);
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, drag_target_entries, actions);
    }

    public void zoom_to_project(double width) {
        if (project.get_length() == 0)
            return;
            
        // The 12.0 is just a magic number to completely get rid of the scrollbar on this operation
        width -= 12.0;
            
        double numerator = GLib.Math.log(
                    (width * Gst.SECOND) / ((double) project.get_length() * (double) pixel_min));
        double denominator = GLib.Math.log((double) pixel_div);

        zoom((float) (numerator / denominator) - provider.get_pixel_percentage());
    }

    public void zoom(float inc) {
        provider.calculate_pixel_step(inc, pixel_min, pixel_div);
        foreach (TrackView track in tracks) {
            track.resize();
        }
        project.media_engine.position_changed(project.transport_get_position());
        queue_draw();
    }

    void on_geometry_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_geometry_changed");
        provider.calculate_pixel_step(0, pixel_min, pixel_div);
        ruler.queue_draw();
    }

    void on_position_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_position_changed");
        queue_draw();
    }

    void on_track_added(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_added");
        TrackView track_view = ClassFactory.get_class_factory().get_track_view(track, this);
        track_view.clip_view_added.connect(on_clip_view_added);
        tracks.add(track_view);
        vbox.pack_start(track_view, false, false, 0);
        trackview_added(track_view);
        if (track.media_type() == Model.MediaType.VIDEO) {
            vbox.reorder_child(track_view, 1);
        } else if (track.media_type() == Model.MediaType.AUDIO) {
            Model.AudioTrack audio_track = track as Model.AudioTrack;
            audio_track.solo_changed.connect(on_solo_changed);
            audio_track.indirect_mute = any_track_solo();
        }
        vbox.show_all();
    }

    bool any_track_solo() {
        foreach (TrackView track_view in tracks) {
            Model.AudioTrack audio_track = track_view.get_track() as Model.AudioTrack;
            if (audio_track.solo) {
                return true;
            }
        }
        return false;
    }

    void on_solo_changed(Model.AudioTrack track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_solo_changed");

        bool any_solo = track.solo || any_track_solo();
        foreach (TrackView track_view in tracks) {
            Model.AudioTrack audio_track = track_view.get_track() as Model.AudioTrack;
            if (audio_track != null && !audio_track.solo) {
                audio_track.indirect_mute = any_solo;
            }
        }
    }

    void on_track_removed(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_removed");
        foreach (TrackView track_view in tracks) {
            if (track_view.get_track() == track) {
                trackview_removed(track_view);
                vbox.remove(track_view);
                tracks.remove(track_view);
                break;
            }
        }
    }

    public void on_clip_view_added(ClipView clip_view) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_clip_view_added");
        clip_view.selection_request.connect(on_clip_view_selection_request);
        clip_view.move_request.connect(on_clip_view_move_request);
        clip_view.move_commit.connect(on_clip_view_move_commit);
        clip_view.move_begin.connect(on_clip_view_move_begin);
        clip_view.trim_begin.connect(on_clip_view_trim_begin);
        clip_view.trim_commit.connect(on_clip_view_trim_commit);
    }

    public void deselect_all_clips() {
        foreach(ClipView selected_clip_view in selected_clips) {
            selected_clip_view.is_selected = false;
        }
        selected_clips.clear();
    }

    void on_clip_view_move_begin(ClipView clip_view, bool copy) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_move_begin");
        copying = copy;
        if (copy) {
            project.undo_manager.start_transaction("Copy Clip");
        }
        ClipView max_clip = null;
        //The first pass removes the clips from the track model and makes any copies
        foreach (ClipView selected_clip in selected_clips) {
            if (max_clip == null) {
                max_clip = selected_clip;
            } else if (max_clip.clip.end < selected_clip.clip.end) {
                max_clip = selected_clip;
            }
            selected_clip.initial_time = selected_clip.clip.start;
            selected_clip.clip.gnonlin_disconnect();
            TrackView track_view = selected_clip.get_parent() as TrackView;
            if (track_view != null) {
                track_view.get_track().remove_clip_from_array(selected_clip.clip);
            }
            if (copy) {
                // TODO: When adding in linking/groups, this should be moved into track_view
                // We'll want to call move_begin for each clip that is linked, or in a group 
                // or selected and not iterate over them in this fashion in the timeline.
                Model.Clip clip = selected_clip.clip.copy();
                track_view.get_track().append_at_time(clip, selected_clip.clip.start, false);
            }
        }

        high_water = new Gtk.Label(null);
        Gtk.Fixed the_parent = clip_view.get_parent() as Gtk.Fixed;
        the_parent.put(high_water,
            max_clip.allocation.x + max_clip.allocation.width, max_clip.allocation.y);

        //The second pass moves the selected clips to the top.  We can't do this in one pass
        //because creating a copy inserts the new copy in the z-order at the top.
        foreach (ClipView selected_clip in selected_clips) {
            TrackView track_view = selected_clip.get_parent() as TrackView;
            track_view.move_to_top(selected_clip);
        }
    }

    void on_clip_view_trim_begin(ClipView clip, Gdk.WindowEdge edge) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_trim_begin");
        switch (edge) {
            case Gdk.WindowEdge.WEST:
                clip.initial_time = clip.clip.start;
                break;
            case Gdk.WindowEdge.EAST:
                clip.initial_time = clip.clip.duration;
                break;
            default:
                assert(false); // We only support trimming east and west;
                break;
        }
    }

    void on_clip_view_selection_request(ClipView clip_view, bool extend) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_selection_request");
/*
        if (gap_view != null) {
            gap_view.unselect();
        }
*/
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
                    // just deselected with multiple clips, so moving is not allowed
                    drag_widget = null;
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

    void on_clip_view_move_commit(ClipView clip_view, int64 delta) {
        window.set_cursor(null);
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_move_request");
        Gtk.Fixed fixed = high_water.get_parent() as Gtk.Fixed;
        fixed.remove(high_water);
        high_water = null;

        project.undo_manager.start_transaction("Move Clip");
        foreach (ClipView selected_clip_view in selected_clips) {
            TrackView track_view = selected_clip_view.get_parent() as TrackView;
            selected_clip_view.clip.gnonlin_connect();
            track_view.get_track().move(selected_clip_view.clip, 
                 selected_clip_view.clip.start, selected_clip_view.initial_time);
        }
        project.undo_manager.end_transaction("Move Clip");
        if (copying) {
            copying = false;
            project.undo_manager.end_transaction("Copy Clip");
        }
    }

    void on_clip_view_trim_commit(ClipView clip_view, Gdk.WindowEdge edge) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_move_commit");
        window.set_cursor(null);
        TrackView track_view = clip_view.get_parent() as TrackView;
        int64 delta = 0;
        switch (edge) {
            case Gdk.WindowEdge.WEST:
                delta = clip_view.clip.start - clip_view.initial_time;
                break;
            case Gdk.WindowEdge.EAST:
                delta = clip_view.clip.duration - clip_view.initial_time;
                break;
            default:
                assert(false);  // We only handle WEST and EAST
                break;
        }
        //restore back to pre-trim state
        project.undo_manager.start_transaction("Trim Clip");
        clip_view.clip.trim(-delta, edge);
        clip_view.clip.gnonlin_connect();
        track_view.get_track().trim(clip_view.clip, delta, edge);
        project.undo_manager.end_transaction("Trim Clip");
    }

    bool constrain_move(ClipView clip_view, ref int64 delta) {
        int min_delta = clip_view.SNAP_DELTA;
        int delta_xsize = provider.time_to_xsize(delta);
        TrackView track_view = (TrackView) clip_view.parent as TrackView;
        Model.Track track = track_view.get_track();
        if (delta_xsize.abs() < min_delta) {
            int64 range = provider.xsize_to_time(min_delta);
            int64 adjustment;
            if (track.clip_is_near(clip_view.clip, range, out adjustment)) {
                delta = adjustment;
                clip_view.snap(provider.time_to_xsize(adjustment));
                return true;
            }
        }
        return false;
    }

    void on_clip_view_move_request(ClipView clip_view, int64 delta) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_view_move_request");
        bool snapped = false;
        if (project.snap_to_clip) {
            snapped = constrain_move(clip_view, ref delta);
        }

        if (!snapped && project.snap_to_grid) {
            int64 range = provider.xsize_to_time(clip_view.SNAP_DELTA);
            int64 snap_time = provider.next_tick(clip_view.clip.start);
            int64 difference = clip_view.clip.start - snap_time;
            if (difference.abs() < range) {
                delta = -difference;
                clip_view.snap(provider.time_to_xsize(difference));
            } else {
                snap_time = provider.previous_tick(clip_view.clip.start);
                difference = clip_view.clip.start - snap_time;
                if (difference.abs() < range) {
                    delta = -difference;
                    clip_view.snap(provider.time_to_xsize(difference));
                }
            }
        }
        if (move_allowed(ref delta)) {
            move_the_clips(delta);
        }
    }

    bool move_allowed(ref int64 move_distance) {
        if (drag_widget == null) {
            return false;
        }

        ClipView max_clip = null;

        foreach(ClipView clip_view in selected_clips) {
            if (max_clip == null) {
                max_clip = clip_view;
            } else if (clip_view.clip.end  > max_clip.clip.end){
                max_clip = clip_view;
            }
            int position = provider.time_to_xpos(clip_view.clip.start + move_distance);
            if (position < BORDER) {
                return false;
            }
        }
        return true;
    }

    void move_the_clips(int64 move_distance) {
        foreach (ClipView clip_view in selected_clips) {
            do_clip_move(clip_view, move_distance);
        }
    }

    public void do_clip_move(ClipView clip_view, int64 delta) {
        clip_view.clip.start += delta;
    }

    public void on_ruler_position_changed(int x) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_ruler_position_changed");
        if (!project.transport_is_recording()) {
            update_pos(x);
        }
    }

    public bool is_clip_selected() {
        return selected_clips.size > 0;
    }
    
    public bool gap_selected() {
        return false;
//        return gap_view != null;
    }

    public void delete_selection() {
        project.undo_manager.start_transaction("Delete Clips From Timeline");
        drag_widget = null;
        if (is_clip_selected()) {
            while (selected_clips.size > 0) {
                selected_clips[0].delete_clip();
                selected_clips.remove_at(0);
            }
            track_changed();
        } else {
/*
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
*/
        }
        project.undo_manager.end_transaction("Delete Clips From Timeline");
    }

    public void do_cut() {
        clipboard.select(selected_clips);
        delete_selection();
    }

    public void do_copy() {
        clipboard.select(selected_clips);
        selection_changed(true);
    }

    public void paste() {
        do_paste(project.transport_get_position());
    }

    public void do_paste(int64 pos) {
        TrackView? view = null;
        foreach (TrackView track_view in tracks) {
            if (track_view.get_track().get_is_selected()) {
                view = track_view;
            }
        }
        // TODO: Lombard doesn't use selected state.  The following check should be removed
        // when it does
        if (view == null) {
            view = clipboard.clips[0].clip.type == Model.MediaType.VIDEO ?
                            find_video_track_view() : find_audio_track_view();
        }
        project.undo_manager.start_transaction("Paste");
        clipboard.paste(view.get_track(), pos);
        project.undo_manager.end_transaction("Paste");
        queue_draw();
    }

    public void select_all() {
        foreach (TrackView track in tracks) {
            track.select_all();
        }
    }

    public override bool expose_event(Gdk.EventExpose event) {
        base.expose_event(event);

        int xpos = provider.time_to_xpos(project.transport_get_position());
        Gdk.draw_line(window, style.fg_gc[(int) Gtk.StateType.NORMAL],
                      xpos, 0,
                      xpos, allocation.height);

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

        bool timeline_add = true;

        if (a.length > 1) {
            if (Gtk.drag_get_source_widget(context) != null) {
                DialogUtils.warning("Cannot add files",
                    "Files must be dropped onto the timeline individually.");
                return;
            }

            if (DialogUtils.add_cancel(
                "Files must be dropped onto the timeline individually.\n" +
                    "Do you wish to add these files to the library?") != Gtk.ResponseType.YES) {
                        return;
                    }
            timeline_add = false;
        } else {
            track = track_view.get_track();
        }

        project.create_clip_importer(track, timeline_add, provider.xpos_to_time(x),
            context.action == Gdk.DragAction.COPY, (Gtk.Window) get_toplevel(), a.length);
        try {
            foreach (string s in a) {
                string filename;
                try {
                    filename = GLib.Filename.from_uri(s);
                } catch (GLib.ConvertError e) { continue; }
                project.importer.add_file(filename);
            }
            project.importer.start();
        } catch (Error e) {
            project.error_occurred("Error importing", e.message);
        }
    }

    public void update_pos(int event_x) {
        int64 time = provider.xpos_to_time(event_x);
        if (project.snap_to_clip) {
            project.snap_coord(out time, provider.get_pixel_snap_time());
        }
        project.media_engine.go(time);
    }

    public Gtk.Widget? find_child(double x, double y) {
        foreach (Gtk.Widget w in vbox.get_children()) {
            if (w.allocation.y <= y && y < w.allocation.y + w.allocation.height)
                return w;
        }
        return null;
    }

    void deselect_all() {
        foreach (ClipView clip_view in selected_clips) {
            clip_view.is_selected = false;
        }
        selected_clips.clear();
        selection_changed(false);
    }

    public override bool button_press_event(Gdk.EventButton event) {
/*
        if (gap_view != null)
            gap_view.unselect();
*/      
        drag_widget = null;
        Gtk.Widget? child = find_child(event.x, event.y);

        if (child is View.Ruler) {
            View.Ruler ruler = child as View.Ruler;
            ruler.button_press_event(event);
            drag_widget = child;
        } else if (child is TrackView) {
            TrackView track_view = child as TrackView;

            drag_widget = track_view.find_child(event.x, event.y);
            if (drag_widget != null) {
                drag_widget.button_press_event(event);
            } else {
                deselect_all();
            }
        } else {
            deselect_all();
        }
        queue_draw();

        return false;
    }

    public override bool button_release_event(Gdk.EventButton event) {
        if (drag_widget != null) {
            drag_widget.button_release_event(event);
            drag_widget = null;
        }
        return false;
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        if (drag_widget != null) {
            drag_widget.motion_notify_event(event);
        } else {
            Gtk.Widget widget = find_child(event.x, event.y);
            if (widget is TrackView) {
                TrackView? track_view = widget as TrackView;
                if (track_view != null) {
                    ClipView? clip_view = track_view.find_child(event.x, event.y) as ClipView;
                    if (clip_view != null) {
                        clip_view.motion_notify_event(event);
                    } else {
                        window.set_cursor(null);
                    }
                }
            } else if (widget is View.Ruler) {
                widget.motion_notify_event(event);
            } else {
                window.set_cursor(null);
            }
        }
        return false;
    }

    TrackView? find_video_track_view() {
        foreach (TrackView track in tracks) {
            if (track.get_track().media_type() == Model.MediaType.VIDEO) {
                return track;
            }
        }

        return null;
    }

    TrackView? find_audio_track_view() {
        foreach (TrackView track in tracks) {
            if (track.get_track().media_type() == Model.MediaType.AUDIO) {
                return track;
            }
        }

        return null;
    }
}
