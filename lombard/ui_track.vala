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
    
    Model.Clip? drag_clip_destination = null;
    bool drag_after_destination;

    public bool adding = false;
    public bool dragging = false;
    public bool drag_intersect = false;
    Gdk.Cursor hand_cursor = new Gdk.Cursor(Gdk.CursorType.HAND1);
    Gdk.Cursor plus_cursor = new Gdk.Cursor(Gdk.CursorType.PLUS);

    public TrackView(Model.Track track, TimeLine timeline) {
        this.track = track;
        this.timeline = timeline;
        
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
    
    public void on_clip_deleted(Model.Clip clip) {
        track.delete_clip(clip);
        clear_drag();
    }

    public void on_clip_added(Model.Track t, Model.Clip clip) {
        ClipView view = new ClipView(clip, timeline.provider, TrackView.clip_height);
        view.clip_moved += on_clip_moved;
        view.clip_deleted += on_clip_deleted;

        put(view, timeline.provider.time_to_xpos(clip.start), TimeLine.BORDER);
        view.show();

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
                timeline.unselect_clip(view);
                view.clip_moved -= on_clip_moved;
                remove(view);
                timeline.track_changed();
                return;
            }
        }
    }

    void update_drag_clip() {
        foreach (ClipView clip_view in timeline.selected_clips) {
            TrackView track_view = clip_view.get_parent() as TrackView;
            if (adding) {
                window.set_cursor(plus_cursor);
                track_view.track.add(clip_view.clip.copy(), clip_view.clip.start);
            } else {
                window.set_cursor(hand_cursor);
                /*
                * We remove the ClipView from the Fixed object and add it again to make
                * sure that when we draw it, it is displayed above every other clip while
                * dragging.
                */
                track_view.remove(clip_view);
                track_view.put(clip_view, 
                    timeline.provider.time_to_xpos(clip_view.clip.start),
                    TimeLine.BORDER);
                clip_view.show();
            }

            clip_view.clip.gnonlin_disconnect();
            track_view.track.remove_clip_from_array(clip_view.clip);
        }
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

    void select_clipview(ClipView clip_view, bool extend_selection) {
        if (!extend_selection) {
            if (!clip_view.is_selected) {
                // deselect everything
                timeline.select_clip(null);
            }
            timeline.select_clip(clip_view);
        } else {
            if (clip_view.is_selected && timeline.selected_clips.size > 1) {
                timeline.unselect_clip(clip_view);
                timeline.selected_clip_index = -1;
            } else {
                timeline.select_clip(clip_view);
            }
        }
        
        for (int i = 0; i < timeline.selected_clips.size; ++i) {
            if (timeline.selected_clips[i] == clip_view) {
                timeline.selected_clip_index = i;
                break;
            }
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
            ClipView? clip_view = find_child(e.x, e.y) as ClipView;
            if (clip_view != null) {
                bool extend_selection = (e.state & Gdk.ModifierType.SHIFT_MASK) != 0;
                select_clipview(clip_view, extend_selection);
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

    public void clear_drag() {
        init_drag_x = -1;
        adding = false;
        dragging = false;
        window.set_cursor(null);
        queue_draw();
    }

    public override bool button_release_event(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.BUTTON_RELEASE) {
            if (dragging) {
                foreach (ClipView clip_view in timeline.selected_clips) {
                    TrackView track_view = clip_view.get_parent() as TrackView;
                    clip_view.clip.gnonlin_connect();
                    if (adding) {
                        timeline.do_paste(clip_view.clip, 
                                drag_clip_destination == null ? 
                                    (drag_x_coord < TimeLine.BORDER ?
                                        0 : clip_view.clip.start) : 
                                    track_view.track.get_time_from_pos(drag_clip_destination,
                                        drag_after_destination),
                                false);
                    } else {
                        track_view.track.move(clip_view.clip, 
                             drag_x_coord < TimeLine.BORDER ? 0 : clip_view.clip.start,
                             init_drag_time);
                    }
                }
                clear_drag();
            }
        }
        return false;
    }
    
    int get_x_from_pos(Model.Clip pos, bool after) {                
        if (after)
            return timeline.BORDER + timeline.provider.time_to_xsize(pos.end);
        else
            return timeline.BORDER + timeline.provider.time_to_xsize(pos.start);
    }

    void calc_drag_intersect(ClipView clip_view) {
        int64 start = clip_view.clip.start;
        if (start < 0) {
            start = 0;
        }
        drag_intersect = track.find_overlapping_clip(start, 
                                clip_view.clip.duration) != null;
    }
    

    public void update_intersect_state(ClipView clip_view) {
        calc_drag_intersect(clip_view);
        if (!drag_intersect) {
            drag_x_coord = timeline.provider.time_to_xpos(clip_view.clip.start);
            drag_clip_destination = null;
            calc_drag_intersect(clip_view);
        } else {
            if (drag_intersect) {
                drag_clip_destination = track.find_nearest_clip_edge(
                        clip_view.clip.start + clip_view.clip.duration / 2, 
                        out drag_after_destination);
                drag_x_coord = get_x_from_pos(drag_clip_destination, drag_after_destination);
            }
        }
    }
    
    public void do_clip_move(ClipView clip_view, int delta) {
        clip_view.clip.start += timeline.provider.xpos_to_time(delta);
    }
    
    int calculate_move_distance(int x, ClipView clip_view) {
        return x - timeline.provider.time_to_xpos(clip_view.clip.start);
    }
    
    bool move_allowed(ref int move_distance) {
        foreach(ClipView clip_view in timeline.selected_clips) {
            int position = timeline.provider.time_to_xpos(clip_view.clip.start);
            if (position < timeline.BORDER && move_distance < timeline.BORDER) {
                return false;
            }
        }
        return true;
    }

    void move_the_clips(int move_distance) {
        foreach (ClipView clip_view in timeline.selected_clips) {
            do_clip_move(clip_view, move_distance);
        }
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        if (init_drag_x != -1) {
            int x = (int) event.x;
                
            if (timeline.selected_clip_index != -1 && 
                !dragging && (x - init_drag_x).abs() > MIN_DRAG) {
                adding = false;
                dragging = true;                
                update_drag_clip();
            }
            
            if (dragging) {
                int move_distance = calculate_move_distance(x - drag_offset,
                    timeline.selected_clips[timeline.selected_clip_index]);
                if (move_allowed(ref move_distance)) {
                    move_the_clips(move_distance);
                }
                update_intersect_state(timeline.selected_clips[timeline.selected_clip_index]);
            }
        }
        return false;
    }
}
