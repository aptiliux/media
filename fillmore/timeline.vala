/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class Ruler : Gtk.DrawingArea {
    public const int height = 20;
    
    construct {
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        modify_bg(Gtk.StateType.NORMAL, parse_color("#777"));
        set_size_request(500, height);
    }
    
    public override bool expose_event (Gdk.EventExpose event) {
        window.draw_rectangle(style.bg_gc[Gtk.StateType.NORMAL],
                              true, allocation.x, allocation.y, allocation.width, allocation.height);
        return true;
    }
}

class RegionView : Gtk.DrawingArea {
    public Region region;
    public TrackView track_view;
    
    public RegionView(Region r) {
        region = r;
        region.view = this;
    }
    
    construct {
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        modify_bg(Gtk.StateType.NORMAL, parse_color("#da5"));
        modify_bg(Gtk.StateType.SELECTED, parse_color("#d82"));
    }
    
    public void update() {
        track_view.update(this);
    }
    
    public override bool expose_event (Gdk.EventExpose event) {
        bool selected = track_view.timeline.selected == this;
        window.draw_rectangle(style.bg_gc[selected ? Gtk.StateType.SELECTED : Gtk.StateType.NORMAL],
                              true, allocation.x, allocation.y, allocation.width, allocation.height);
        Pango.Layout layout = create_pango_layout(region.name);
        Gdk.draw_layout(window, style.black_gc, allocation.x + 10, allocation.y + 14, layout);
        return true;
    }
}

class TrackView : Gtk.Fixed {
    Track track;
    public TimeLine timeline;
    
    Region drag;
    int drag_region_x;
    int drag_mouse_x;
    
    public const int width = 500;
    public const int height = 50;
    
    public TrackView(Track t) {
        track = t;
        track.region_added += on_region_added;
        track.region_removed += on_region_removed;
    }
    
    static const Gtk.TargetEntry[] entries = {
        { "text/uri-list", 0, 0 }
    };

    construct {
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, entries, Gdk.DragAction.COPY);
    }
    
    public override void size_request(out Gtk.Requisition requisition) {
        requisition.width = width;
        requisition.height = height;
    }
    
    void update_size(RegionView rv) {
        rv.set_size_request(TimeLine.time_to_xpos(rv.region.length), height);
    }
    
    public void on_region_added(Track t, Region r) {
        RegionView rv = new RegionView(r);
        rv.track_view = this;
        update_size(rv);
        put(rv, TimeLine.time_to_xpos(rv.region.start), 0);
        rv.show();
    }
    
    public void on_region_removed(Track t, Region r) {
        remove(r.view);
        timeline.region_view_removed(r.view);
        r.view = null;
    }
    
    public void update(RegionView rv) {
        update_size(rv);
        move(rv, TimeLine.time_to_xpos(rv.region.start), 0);
    }
    
    public override void drag_data_received (Gdk.DragContext context, int x, int y,
                                      Gtk.SelectionData selection_data, uint info, uint time) {
        string[] a = selection_data.get_uris();
        Gtk.drag_finish(context, true, false, time);
        foreach (string s in a) {
            string filename;
            try {
                filename = GLib.Filename.from_uri(s);
            } catch (GLib.ConvertError e) { continue; }
            track.add(new Region(filename, TimeLine.xpos_to_time(x), false));
        }
    }
    
    public void on_button_press(Gdk.EventButton event) {
        timeline.recorder.select(track);
        
        foreach (Gtk.Widget w in get_children()) {
            RegionView rv = (RegionView) w;
            if (rv.allocation.x <= event.x && event.x < rv.allocation.x + rv.allocation.width) {
                timeline.select(rv);
                drag = rv.region;
                drag_mouse_x = (int) event.x; 
                drag_region_x = rv.allocation.x;
                return;
            }
        }
        timeline.select(null);
    }
    
    public void on_motion_notify(Gdk.EventMotion event) {
        if (drag != null) {
            int new_x = drag_region_x + (int) event.x - drag_mouse_x;
            drag.move(TimeLine.xpos_to_time(new_x));
        }
    }
    
    public void on_button_release(Gdk.EventButton event) {
        drag = null;
    }
}

class TimeLine : Gtk.EventBox {
    Project project;
    public Recorder recorder;
    
    Gtk.VBox vbox;
    Ruler ruler;
    Gdk.Color background_color = parse_color("#444");

    public RegionView selected;
    
    public const int pixels_per_second = 60;
    
    public const int track_margin = 2;
    
    public signal void selection_changed(RegionView? new_selection);
    
    public TimeLine(Recorder recorder) {
        this.project = recorder.project;
        this.recorder = recorder;
        
        project.track_added += add_track;
        
        vbox = new Gtk.VBox(false, 0);
        ruler = new Ruler();
        vbox.pack_start(ruler, false, false, 0);
        vbox.pack_start(separator(), false, false, 0);
        add(vbox);
        
        foreach (Track track in project.tracks)
            add_track(project, track);
        
        set_flags(Gtk.WidgetFlags.CAN_FOCUS);
        modify_bg(Gtk.StateType.NORMAL, background_color);
        modify_fg(Gtk.StateType.NORMAL, parse_color("#f00"));
        
        set_size_request(5000, 0);
    }
    
    Gtk.HSeparator separator() {
        Gtk.HSeparator separator = new Gtk.HSeparator();
        separator.modify_bg(Gtk.StateType.NORMAL, background_color);
        return separator;
    }
    
    public void add_track(Project project, Track track) {
        TrackView track_view = new TrackView(track);
        track_view.timeline = this;
        vbox.pack_start(track_view, false, false, track_margin);
        vbox.pack_start(separator(), false, false, 0);
        vbox.show_all();
    }
    
    public static int64 xpos_to_time(int x) {
        return x * Gst.SECOND / pixels_per_second;
    }
    
    public static int time_to_xpos(int64 time) {
        return (int) (time * pixels_per_second / Gst.SECOND);
    }
    
    public void update() {
        if (project.playing() || project.recording())
            recorder.scroll_toward_center(time_to_xpos(project.audio_engine.position));
        queue_draw();
    }
    
    public override bool expose_event (Gdk.EventExpose event) {
        base.expose_event(event);
        int xpos = time_to_xpos(project.audio_engine.position);
        Gdk.draw_line(window, style.fg_gc[Gtk.StateType.NORMAL], xpos, 0, xpos, 500);
        return true;
    }
    
    public void select(RegionView? view) {
        RegionView was_selected = selected;
        selected = view;
        if (was_selected != null)
            was_selected.queue_draw();
        if (selected != null)
            selected.queue_draw();
        selection_changed(view);
    }
    
    public void region_view_removed(RegionView view) {
        if (selected == view) {
            selected = null;
            selection_changed(null);
        }
    }
    
    TrackView? findView(double y) {
        foreach (Gtk.Widget w in vbox.get_children()) {
            TrackView view = w as TrackView;
            if (view != null &&
                view.allocation.y <= y && y < view.allocation.y + view.allocation.height)
                return view;
        }
        return null;
    }
    
    public override bool button_press_event (Gdk.EventButton event) {
        if (ruler.allocation.y <= event.y &&
                event.y < ruler.allocation.y + ruler.allocation.height) {
            project.audio_engine.set_position(xpos_to_time((int) event.x));
            return false;
        }
        
        TrackView view = findView(event.y);
        if (view != null)
            view.on_button_press(event);
        else select(null);
        return false;
    }
    
    public override bool motion_notify_event (Gdk.EventMotion event) {
        TrackView view = findView(event.y);
        if (view != null)
            view.on_motion_notify(event);
        return false;
    }
    
    public override bool button_release_event (Gdk.EventButton event) {
        TrackView view = findView(event.y);
        if (view != null)
            view.on_button_release(event);
        return false;
    }
}
