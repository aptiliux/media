/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class TrackView : Gtk.Fixed {
    public Track track;
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
    
    public TrackView(Track track, TimeLine t) {
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
    
    public void on_clip_added(Track t, Clip clip) {
        ClipView view = new ClipView(clip, this);      
        put(view, timeline.time_to_xpos(clip.start), TimeLine.BORDER);       
        view.show();
        
        if (timeline.control_pressed) {
            timeline.selected_clip = view;
        }
    }
    
    public void set_clip_pos(ClipView view) {
        move(view, timeline.time_to_xpos(view.clip.start), TimeLine.BORDER);
        queue_draw();
    }
    
    public void resize() {
        int limit = track.get_num_clips();
        
        for(int i = 0; i < limit; i++) {
            Clip c = track.get_clip(i);
            c.view.on_clip_moved();
        }
    }
    
    public void on_clip_removed(Track t, Clip clip) {
        remove(clip.view);
    }

    public void update_drag_clip() {  
        if (timeline.control_pressed) {
            window.set_cursor(plus_cursor);
            
            if (track.get_clip_index(timeline.drag_source_clip.clip) == -1) {
                track.add_clip_at(timeline.drag_source_clip.clip, 
                                        timeline.drag_source_clip.clip.start, false);
                timeline.selected_clip.ghost = false;
            }
            
            track.add_new_clip(timeline.drag_source_clip.clip.copy(), 
                                timeline.drag_source_clip.clip.start, false);
            timeline.drag_source_clip.clip.set_start(init_drag_time); 
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
                timeline.time_to_xpos(timeline.selected_clip.clip.start),
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
    
    public override bool button_press_event(Gdk.EventButton e) {
        if (e.type != Gdk.EventType.BUTTON_PRESS &&
            e.type != Gdk.EventType.2BUTTON_PRESS &&
            e.type != Gdk.EventType.3BUTTON_PRESS)
            return false;
        
        if (e.button == 1 ||
            e.button == 3) {
            int x = (int) e.x;        
            
            int64 time = timeline.xpos_to_time(x);
            int clip_index = track.find_overlapping_clip(time, 0);        

            if (clip_index >= 0) {
                ClipView w = track.get_clip(clip_index).view;
                timeline.select_clip(w);
                init_drag_x = x;
                drag_offset = x - w.allocation.x;
                init_drag_time = w.clip.start;
                dragging = false;  // not dragging until we've moved MIN_DRAG pixels
            } else {
                Gap g;
                track.find_containing_gap(time, out g);
                if (g.end > g.start) {
                    timeline.gap_view = new GapView(g.start, g.end - g.start, this);
                    put(timeline.gap_view, timeline.time_to_xpos(g.start), TimeLine.BORDER);
                    timeline.gap_view.show();
                }
                
                init_drag_x = -1;
                timeline.select_clip(null);
            }
        }
        return false;
    }
    
    public void cancel_drag() {
        track.add_clip_at(timeline.selected_clip.clip, init_drag_time, false);
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
                           (drag_x_coord < TimeLine.BORDER ? 0: timeline.selected_clip.clip.start) : 
                            track.get_time_from_pos(drag_clip_destination, drag_after_destination),
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
                             timeline.shift_pressed);
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
            return timeline.BORDER + timeline.time_to_xsize(track.get_clip(pos).end);
        else
            return timeline.BORDER + timeline.time_to_xsize(track.get_clip(pos).start);
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
                        timeline.pixel_snap_time);
            drag_x_coord = timeline.time_to_xpos(timeline.selected_clip.clip.start);
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
    
    public void do_clip_move(Clip clip, int x) {
        curr_drag_x = x - drag_offset + timeline.BORDER;
        timeline.selected_clip.clip.set_start(timeline.xpos_to_time(curr_drag_x));
        
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
