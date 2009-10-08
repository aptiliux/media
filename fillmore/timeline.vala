/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class FillmoreFetcherCompletion : Model.FetcherCompletion {
    int64 time;
    
    public signal void fetch_complete(Model.ClipFile clip_file, int64 time);
    public FillmoreFetcherCompletion(int64 time) {
        base();
        this.time = time;
    }
    
    public override void complete(Model.ClipFetcher fetch) {
        base.complete(fetch);
        fetch_complete(fetch.clipfile, time);
    }
}

class TrackView : Gtk.Fixed {
    public weak Model.Track track;
    public weak TimeLine timeline;
    
    Model.Clip drag;
    int drag_region_x;
    int drag_mouse_x;
    
    public const int width = 500;
    public const int height = 50;
        
    public TrackView(Model.Track t) {
        track = t;
        track.clip_added += on_region_added;
        track.clip_removed += on_region_removed;
    }
    
    construct {
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, drag_target_entries, Gdk.DragAction.COPY);
    }
    
    public override void size_request(out Gtk.Requisition requisition) {
        requisition.width = width;
        requisition.height = height;
    }
    
    public void on_region_added(Model.Clip clip) {
        ClipView view = new ClipView(clip, timeline.provider, TrackView.height);
        view.clip_moved += update;
        
        put(view, timeline.provider.time_to_xpos(clip.start), TimeLine.BORDER);   
        view.show();
    }
    
    public void on_region_removed(Model.Clip clip) {
    // TODO revisit the dragging mechanism.  It would be good to have the clip
    // responsible for moving itself and removing itself rather than delegating
    // to the timeline and to the TrackView
        foreach (Gtk.Widget w in get_children()) {
            ClipView view = w as ClipView;
            if (view.clip == clip) {
                view.clip_moved -= update;
                remove(view);
                return;
            }
        }
    }
    
    public void update(ClipView rv) {
        move(rv, timeline.provider.time_to_xpos(rv.clip.start), TimeLine.BORDER);
    }
    
    public override void drag_data_received (Gdk.DragContext context, int x, int y,
                                      Gtk.SelectionData selection_data, uint info, uint time) {
        string[] a = selection_data.get_uris();
        Gtk.drag_finish(context, true, false, time);
        int number_of_files = a.length;
        foreach (string s in a) {
            string filename;
            try {
                filename = GLib.Filename.from_uri(s);
                if (number_of_files == 1 && timeline.project.is_project_extension(filename)) {
                    timeline.project.load(filename);
                    return;
                }
            } catch (GLib.ConvertError e) { continue; }

            Model.ClipFile cf = timeline.project.find_clipfile(filename);
            if (cf != null) {
                on_clip_file_ready(cf, timeline.provider.xpos_to_time(x));
            } else {
                FillmoreFetcherCompletion clip_fetcher_complete = 
                    new FillmoreFetcherCompletion(timeline.provider.xpos_to_time(x));
                clip_fetcher_complete.fetch_complete += on_clip_file_ready;
                timeline.project.create_clip_fetcher(clip_fetcher_complete, filename);
            }
        }
    }

    private void on_clip_file_ready(Model.ClipFile clip_file, int64 time) {
        track.append_at_time(new Model.Clip(clip_file, Model.MediaType.AUDIO, 
            isolate_filename(clip_file.filename), 
            time, 0, clip_file.length, false), time);
    }

    public override bool button_press_event(Gdk.EventButton event) {
        timeline.recorder.select(track);
        
        foreach (Gtk.Widget w in get_children()) {
            ClipView rv = (ClipView) w;
            if (rv.allocation.x <= event.x && event.x < rv.allocation.x + rv.allocation.width) {
                timeline.select(rv);
                drag = rv.clip;
                drag_mouse_x = (int) event.x; 
                drag_region_x = rv.allocation.x;
                return true;
            }
        }
        timeline.select(null);
        return true;
    }
    
    public override bool motion_notify_event(Gdk.EventMotion event) {
        if (drag != null) {
            int new_x = drag_region_x + (int) event.x - drag_mouse_x;
            drag.start = timeline.provider.xpos_to_time(new_x);
            return true;
        }
        return false;
    }
    
    public override bool button_release_event(Gdk.EventButton event) {
        drag = null;
        return true;
    }
    
    public void on_resized() {
        foreach (Gtk.Widget w in get_children()) {
            ClipView view = w as ClipView;
            if (view != null) {
                view.on_clip_moved(view.clip);
            }
        }            
    }
}

class TimeLine : Gtk.EventBox {
    public weak Model.Project project;
    public weak Recorder recorder;
    public Model.TimeSystem provider;
    
    Gtk.VBox vbox;
    View.Ruler ruler;
    Gdk.Color background_color = parse_color("#444");

    public ClipView selected;
    
    public const int track_margin = 2;
    public const int BORDER = 1;
    float pixel_div;
    float pixel_min = 0.1f;
    float pixel_max = 4505.0f;
    public const int RULER_HEIGHT = 20;
    public signal void selection_changed(ClipView? new_selection);
    public Gtk.Menu context_menu;

    public signal void resized();
    
    public TimeLine(Recorder recorder, Model.TimeSystem provider) {
        Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, drag_target_entries, Gdk.DragAction.COPY);

        this.project = recorder.project;
        this.recorder = recorder;
        this.provider = provider;
        
        project.media_engine.position_changed += update;
        project.track_added += add_track;
        project.track_removed += on_track_removed;
        
        vbox = new Gtk.VBox(false, 0);
        ruler = new View.Ruler(provider, RULER_HEIGHT);
        ruler.position_changed += on_ruler_position_changed;
        vbox.pack_start(ruler, false, false, 0);
        vbox.pack_start(separator(), false, false, 0);
        add(vbox);
        
        foreach (Model.Track track in project.tracks)
            add_track(track);
        
        set_flags(Gtk.WidgetFlags.CAN_FOCUS);
        modify_bg(Gtk.StateType.NORMAL, background_color);
        modify_fg(Gtk.StateType.NORMAL, parse_color("#f00"));
        
        set_size_request(5000, 0);
        pixel_div = pixel_max / pixel_min;
        provider.calculate_pixel_step (0.5f, pixel_min, pixel_div);
    }
    
    Gtk.HSeparator separator() {
        Gtk.HSeparator separator = new Gtk.HSeparator();
        separator.modify_bg(Gtk.StateType.NORMAL, background_color);
        return separator;
    }
    
    public void add_track(Model.Track track) {
        TrackView track_view = new TrackView(track);
        track_view.timeline = this;
        resized += track_view.on_resized;
        vbox.pack_start(track_view, false, false, track_margin);
        vbox.pack_start(separator(), false, false, 0);
        vbox.show_all();
    }
    
    public void on_track_removed(Model.Track track) {
        TrackView? my_track_view = null;
        Gtk.HSeparator? my_separator = null;
        foreach(Gtk.Widget widget in vbox.get_children()) {
            if (my_track_view == null) {
                TrackView? track_view = widget as TrackView;
                if (track_view != null && track_view.track == track) {
                    my_track_view = track_view;
                }
            } else {
                my_separator = widget as Gtk.HSeparator;
                break;
            }
        }
        
        assert(my_track_view != null);
        assert(my_separator != null);
        vbox.remove(my_track_view);
        vbox.remove(my_separator);
    }
    
    public void update() {
        if (project.transport_is_playing())
            recorder.scroll_toward_center(provider.time_to_xpos(project.media_engine.position));
        queue_draw();
    }
    
    public override bool expose_event (Gdk.EventExpose event) {
        base.expose_event(event);
        int xpos = provider.time_to_xpos(project.transport_get_position());
        int line_length = allocation.height;
        Gdk.draw_line(window, style.fg_gc[Gtk.StateType.NORMAL], xpos, 0, xpos, line_length);
        return true;
    }
    
    public void select(ClipView? view) {
        ClipView was_selected = selected;
        selected = view;
        if (was_selected != null) {
            was_selected.is_selected = false;
            was_selected.queue_draw();
        }
        if (selected != null) {
            selected.is_selected = true;
            selected.queue_draw();
        }
        selection_changed(view);
    }
    
    Gtk.Widget? find_child(double y) {
        foreach (Gtk.Widget w in vbox.get_children())
            if (w.allocation.y <= y && y < w.allocation.y + w.allocation.height)
                return w;
        return null;
    }
    
    public override bool button_press_event (Gdk.EventButton event) {
        Gtk.Widget? view = find_child(event.y);
        if (view != null) {
            return view.button_press_event(event);
        }
        else {
            select(null);
        }
        return false;
    }
    
    public override bool motion_notify_event (Gdk.EventMotion event) {
        Gtk.Widget? view = find_child(event.y);
        if (view != null) {
            return view.motion_notify_event(event);
        }
        return false;
    }
    
    public override bool button_release_event (Gdk.EventButton event) {
        // TODO: It would be better if the button_release propogated down to the clipview
        if (selected != null && event.button == 3) {
            context_menu.select_first(true);
            context_menu.popup(null, null, null, 0, 0);
        } else {
            context_menu.popdown();
        }

        Gtk.Widget? view = find_child(event.y);
        if (view != null) {
            return view.button_release_event(event);
        }
        
        return false;
    }

    public override void drag_data_received (Gdk.DragContext context, int x, int y,
                                      Gtk.SelectionData selection_data, uint info, uint time) {
        string[] a = selection_data.get_uris();
        Gtk.drag_finish(context, true, false, time);
        int number_of_files = a.length;
        if (number_of_files > 1) {
            return;
        }

        try {
            string filename = GLib.Filename.from_uri(a[0]);
            if (project.is_project_extension(filename)) {
                project.load(filename);
            }
        } catch (GLib.ConvertError e) { }
    }
    
    public void on_ruler_position_changed(int x) {
        project.media_engine.go(provider.xpos_to_time(x));
    }
    
    public void zoom (float inc) {
        provider.calculate_pixel_step(inc, pixel_min, pixel_div);
        resized();
        project.media_engine.position_changed(project.transport_get_position());
        queue_draw();
    }
}

