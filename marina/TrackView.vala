/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

class TrackViewConcrete : TrackView, Gtk.Fixed {
    Model.Track track;
    TimeLine timeline;
    
    const int clip_height = 50;
    const int TrackHeight = clip_height + TimeLine.BORDER * 2;

    public TrackViewConcrete(Model.Track track, TimeLine timeline) {
        this.track = track;
        this.timeline = timeline;
        
        track.clip_added += on_clip_added;
        track.clip_removed += on_clip_removed;
    }
    
    override void size_request(out Gtk.Requisition requisition) {
        base.size_request(out requisition);
        requisition.height = TrackHeight;
        requisition.width += TimeLine.BORDER;    // right margin
    }
    
    void on_clip_moved(ClipView clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_moved");
        set_clip_pos(clip);
    }
    
    void on_clip_deleted(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_deleted");
        track.delete_clip(clip);
        clear_drag();
    }

    void on_clip_added(Model.Track t, Model.Clip clip, bool select) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_added");
        ClipView view = new ClipView(clip, timeline.provider, clip_height);
        view.clip_moved += on_clip_moved;
        view.clip_deleted += on_clip_deleted;
        view.move_begin += on_move_begin;
        view.trim_begin += on_trim_begin;

        put(view, timeline.provider.time_to_xpos(clip.start), TimeLine.BORDER);
        view.show();

        timeline.track_changed();
        clip_view_added(view);
        if (select) {
            view.selection_request(view, false);
        }
    }

    // TODO: This method should not be public.  When linking/grouping is done, this method
    // should become private.  See Timeline.on_clip_view_move_begin for more information.
    public void move_to_top(ClipView clip_view) {
        /*
        * We remove the ClipView from the Fixed object and add it again to make
        * sure that when we draw it, it is displayed above every other clip while
        * dragging.
        */
        remove(clip_view);
        put(clip_view, 
            timeline.provider.time_to_xpos(clip_view.clip.start),
            TimeLine.BORDER);
        clip_view.show();
    }

    void on_trim_begin(ClipView clip_view) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_trim_begin");
        move_to_top(clip_view);
    }

    void on_move_begin(ClipView clip_view, bool do_copy) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_move_begin");
        move_to_top(clip_view);
    }

    void set_clip_pos(ClipView view) {
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

    void on_clip_removed(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_removed");
        foreach (Gtk.Widget w in get_children()) {
            ClipView view = w as ClipView;
            if (view.clip == clip) {
                view.clip_moved -= on_clip_moved;
                remove(view);
                timeline.track_changed();
                return;
            }
        }
    }

    void unselect_gap() {
/*        if (timeline.gap_view != null) {
            TrackView parent = timeline.gap_view.parent as TrackView;
            parent.remove(timeline.gap_view);
            timeline.gap_view = null;
        }
*/
    }  

    override bool button_press_event(Gdk.EventButton e) {
        if (e.type != Gdk.EventType.BUTTON_PRESS &&
            e.type != Gdk.EventType.2BUTTON_PRESS &&
            e.type != Gdk.EventType.3BUTTON_PRESS)
            return false;

        if (e.button == 1 ||
            e.button == 3) {
/*
            int x = (int) e.x;
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
*/
            timeline.deselect_all_clips();
        }
        return false;
    }
/*
    void on_gap_view_removed(GapView gap_view) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_gap_view_removed");
        track.delete_gap(gap_view.gap);
    }

    void on_gap_view_unselected(GapView gap_view) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_gap_view_unselected");
        unselect_gap();
    }
*/
    void clear_drag() {
        window.set_cursor(null);
        queue_draw();
    }

    public Model.Track get_track() {
        return track;
    }
    
    public int get_track_height() {
        return TrackHeight;
    }
}
