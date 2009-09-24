/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class TrackView : Gtk.Fixed {
    public Model.Track track;
    public TimeLine timeline;
    
    const int MIN_DRAG = 5;
    int init_drag_x = -1;
    int64 init_drag_time;
    int drag_offset = 0;
    public int drag_x_coord = 0;
    
    public const int clip_height = 50;
    
    int drag_clip_origin;
    int drag_clip_destination;
    bool drag_after_destination;
    
    public int curr_drag_x;
    
    public bool dragging = false;
    public bool drag_intersect = false;
    Gdk.Cursor hand_cursor = new Gdk.Cursor(Gdk.CursorType.HAND1);
    Gdk.Cursor plus_cursor = new Gdk.Cursor(Gdk.CursorType.PLUS);
    
    public TrackView(Model.Track track, TimeLine t) {
        this.track = track;
        timeline = t;
        
        track.clip_added += on_clip_added;
        track.clip_removed += on_clip_removed;
    }
    
    public override void size_request(out Gtk.Requisition requisition) {
        base.size_request(out requisition);
        requisition.height = clip_height + TimeLine.BORDER * 2;
        requisition.width += TimeLine.BORDER;    // right margin
    }
    
    public void on_clip_moved(ClipView clip) {
        set_clip_pos(clip);
    }
    
    public void on_drag_updated(ClipView clip) {
        if (dragging) {
            update_drag_clip();
        }
    }
    
    public void on_clip_deleted(Model.Clip clip, bool ripple) {
        track.delete_clip(clip, ripple);
        if (ripple) {
            track.project.ripple_delete(track, clip.length, clip.start, clip.length);
        }
        clear_drag();
    }

    public void on_clip_added(Model.Track t, Model.Clip clip) {
        ClipView view = new ClipView(clip, timeline.provider, TrackView.clip_height);
        view.clip_moved += on_clip_moved;
        view.drag_updated += on_drag_updated;
        view.clip_deleted += on_clip_deleted;
        
        put(view, timeline.provider.time_to_xpos(clip.start), TimeLine.BORDER);
        view.show();
        
        if (timeline.control_pressed) {
            timeline.select_clip(view);
        }
        timeline.track_changed();
    }
    
    public void set_clip_pos(ClipView view) {
        move(view, timeline.provider.time_to_xpos(view.clip.start), TimeLine.BORDER);
        queue_draw();
    }
    
    public void resize() {
        foreach (Gtk.Widget w in get_children()) {
            ClipView view = w as ClipView;
            if (view != null) {
                view.on_clip_moved(view.clip);
            }
        }            
    }

    public void on_clip_removed(Model.Clip clip) {
    // TODO: revisit the dragging mechanism.  It would be good to have the clip
    // responsible for moving itself and removing itself rather than delegating
    // to the timeline and to the TrackView
        foreach (Gtk.Widget w in get_children()) {
            ClipView view = w as ClipView;
            if (view.clip == clip) {
                if (timeline.selected_clip == view) {
                    timeline.select_clip(null);
                }
                
                remove(view);
                timeline.track_changed();
                return;
            }
        }
    }

    public void update_drag_clip() {  
        if (timeline.control_pressed) {
            window.set_cursor(plus_cursor);
            
            track.add_new_clip(timeline.drag_source_clip.clip.copy(), 
                                timeline.drag_source_clip.clip.start, false);

            if (track.get_clip_index(timeline.drag_source_clip.clip) == -1) {
                track.add_clip_at(timeline.drag_source_clip.clip, 
                                        init_drag_time, false, init_drag_time);
                timeline.drag_source_clip.ghost = false;
            }
        } else {
            window.set_cursor(hand_cursor);

            if (timeline.selected_clip != timeline.drag_source_clip) {
                remove(timeline.selected_clip);
                timeline.drag_source_clip.clip.set_start(timeline.selected_clip.clip.start);
            }
            timeline.selected_clip = timeline.drag_source_clip;       
            /*
                * We remove the ClipView from the Fixed object and add it again to make
                * sure that when we draw it, it is displayed above every other clip while
                * dragging.
            */

            remove(timeline.selected_clip);
            put(timeline.selected_clip, 
                timeline.provider.time_to_xpos(timeline.selected_clip.clip.start),
                TimeLine.BORDER);
            timeline.selected_clip.show();
        }
        
        drag_clip_origin = track.get_clip_index(timeline.selected_clip.clip); 
        timeline.selected_clip.clip.gnonlin_disconnect();
        track.remove_clip_from_array(drag_clip_origin);     
        
        update_intersect_state();   
    }

    public void unselect_gap() {
        if (timeline.gap_view != null) {
            remove(timeline.gap_view);
            timeline.gap_view = null;
        }
    }  

    Gtk.Widget? find_child(double x, double y) {
        foreach (Gtk.Widget w in get_children())
            if (w.allocation.x <= x && x < w.allocation.x + w.allocation.width)
                return w;
        return null;
    }
    
    public override bool button_press_event(Gdk.EventButton e) {
        if (e.type != Gdk.EventType.BUTTON_PRESS &&
            e.type != Gdk.EventType.2BUTTON_PRESS &&
            e.type != Gdk.EventType.3BUTTON_PRESS)
            return false;
        
        if (e.button == 1 ||
            e.button == 3) {
            int x = (int) e.x;
            ClipView? clip_view = find_child(e.x, e.y) as ClipView;
            if (clip_view != null) {
                timeline.select_clip(clip_view);
                init_drag_x = x;
                drag_offset = x - clip_view.allocation.x;
                init_drag_time = clip_view.clip.start;
                dragging = false;  // not dragging until we've moved MIN_DRAG pixels
            } else {
                int64 time = timeline.provider.xpos_to_time(x);
                Model.Gap g;
                track.find_containing_gap(time, out g);
                if (g.end > g.start) {
                    int64 length = g.end - g.start;
                    int width = timeline.provider.time_to_xpos(g.start + length) -
                        timeline.provider.time_to_xpos(g.start);            
                    
                    timeline.gap_view = new GapView(g.start, length, 
                        width, clip_height);
                    timeline.gap_view.removed += on_gap_view_removed;
                    timeline.gap_view.unselected += on_gap_view_unselected;
                    put(timeline.gap_view, timeline.provider.time_to_xpos(g.start), TimeLine.BORDER);
                    timeline.gap_view.show();
                }

                init_drag_x = -1;
                timeline.select_clip(null);
            }
        }
        return false;
    }
    
    void on_gap_view_removed(GapView gap_view) {
        track.delete_gap(gap_view.gap);
    }
    
    void on_gap_view_unselected(GapView gap_view) {
        unselect_gap();
    }
    
    public void cancel_drag() {
        track.add_clip_at(timeline.selected_clip.clip, init_drag_time, false, init_drag_time);
        timeline.selected_clip.ghost = false;
        clear_drag();
    }
    
    public void clear_drag() {
        init_drag_x = -1;
        dragging = false;
        window.set_cursor(null);
        queue_draw();
    }
    
    public override bool button_release_event(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.BUTTON_RELEASE) {  
            if (dragging) {
                timeline.selected_clip.clip.gnonlin_connect();
                if (timeline.control_pressed) {
                    if (timeline.do_paste(timeline.selected_clip.clip, 
                            drag_clip_destination == -1 ? 
                                (drag_x_coord < TimeLine.BORDER ?
                                    0 : timeline.selected_clip.clip.start) : 
                                track.get_time_from_pos(drag_clip_destination,
                                    drag_after_destination),
                            timeline.shift_pressed, false) == -1) {
                        remove(timeline.selected_clip);               
                    }
                } else {
                    if (drag_intersect &&
                        !timeline.shift_pressed) {
                        track.rotate_clip(timeline.selected_clip.clip,
                                   drag_clip_origin, drag_clip_destination, drag_after_destination);
                    } else {
                        track.add_clip_at(timeline.selected_clip.clip, 
                             drag_x_coord < TimeLine.BORDER ? 0: timeline.selected_clip.clip.start,
                             timeline.shift_pressed, init_drag_time);
                    }
                }
                timeline.selected_clip.ghost = false;
                clear_drag();
            }
        }
        return false;
    }
    
    int get_x_from_pos(int pos, bool after) {                
        if (after)
            return timeline.BORDER + timeline.provider.time_to_xsize(track.get_clip(pos).end);
        else
            return timeline.BORDER + timeline.provider.time_to_xsize(track.get_clip(pos).start);
    }

    void calc_drag_intersect() {
        drag_intersect = track.find_overlapping_clip(timeline.selected_clip.clip.start, 
                                                     timeline.selected_clip.clip.length) >= 0;
        if (!drag_intersect) {
            if (curr_drag_x < timeline.BORDER) {
                drag_intersect = 
                           track.find_overlapping_clip(0, timeline.selected_clip.clip.length) >= 0;
            }       
        }
        timeline.selected_clip.ghost = drag_intersect;
    }
    
    public void update_intersect_state() {
        calc_drag_intersect();
        if (timeline.shift_pressed ||
            !drag_intersect) {
            timeline.project.snap_clip(timeline.selected_clip.clip, 
                        timeline.provider.get_pixel_snap_time());
            drag_x_coord = timeline.provider.time_to_xpos(timeline.selected_clip.clip.start);
            drag_clip_destination = -1;
            calc_drag_intersect();
        } else {
            if (drag_intersect) {
                drag_clip_destination = track.find_nearest_clip_edge(
                        timeline.selected_clip.clip.start + timeline.selected_clip.clip.length / 2, 
                        out drag_after_destination);
                drag_x_coord = get_x_from_pos(drag_clip_destination, drag_after_destination);
            }
        }
    }
    
    public void do_clip_move(Model.Clip clip, int x) {
        curr_drag_x = x - drag_offset + timeline.BORDER;
        timeline.selected_clip.clip.set_start(timeline.provider.xpos_to_time(curr_drag_x));
        
        update_intersect_state();
    }
    
    public override bool motion_notify_event(Gdk.EventMotion event) {
        if (init_drag_x != -1) {
            int x = (int) event.x;
            if (!dragging && (x - init_drag_x).abs() > MIN_DRAG) {
                dragging = true;                
                update_drag_clip();
            }
            if (dragging) {
                do_clip_move(timeline.selected_clip.clip, x);
            }
        }
        return false;
    }
}
