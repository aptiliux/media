/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Gee;

class Ruler : Gtk.DrawingArea {
    TimeLine timeline;
    
    Ruler(TimeLine timeline) {
        this.timeline = timeline;
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        modify_bg(Gtk.StateType.NORMAL, parse_color("#777"));
        set_size_request(0, TimeLine.BAR_HEIGHT);
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        window.draw_rectangle(style.bg_gc[(int) Gtk.StateType.NORMAL],
                            true, allocation.x, allocation.y, allocation.width, allocation.height);
        return true;
    }
    
    public override bool button_press_event(Gdk.EventButton event) {
        timeline.update_pos((int) event.x);
        return false;
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        timeline.update_pos((int) event.x);
        return false;
    }
}

class StatusBar : Gtk.DrawingArea {
    Model.VideoProject project;
    
    public StatusBar(Model.VideoProject p) {
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        modify_bg(Gtk.StateType.NORMAL, parse_color("#666"));
        set_size_request(0, TimeLine.BAR_HEIGHT);
        project = p;
        
        project.position_changed += position_changed;
    }
    
    public void position_changed() {
        queue_draw();
    }
    
    public override bool expose_event(Gdk.EventExpose e) {
        window.draw_rectangle(style.bg_gc[(int) Gtk.StateType.NORMAL], true, 
                              allocation.x, allocation.y, allocation.width, allocation.height);  

        Fraction rate;
        string time;
        if (project.get_framerate_fraction(out rate))
            time = frame_to_string(project.get_current_frame(), rate);
        else
            time = "00:00:00";

        Pango.Layout layout = create_pango_layout(time);         
        Gdk.draw_layout(window, style.white_gc, allocation.x + 4, allocation.y + 2, layout);
                                
        return true;
    }
}

class TimeLine : Gtk.EventBox {
    public Model.VideoProject project;
    
    Ruler ruler;
    ArrayList<TrackView> tracks = new ArrayList<TrackView>();
    Gtk.VBox vbox;
    
    public ClipView drag_source_clip;
    public ClipView selected_clip;
    public Model.Clip clipboard_clip = null;
    
    public Gtk.Menu context_menu;
    
    Gtk.Widget drag;
    
    public bool shift_pressed = false;
    public bool control_pressed = false;
    
    float pixel_percentage = 0.0f;
    float pixel_min = 0.1f;
    float pixel_max = 4505.0f;
    float pixel_div;
    public float pixels_per_second;
    float pixels_per_frame;

    public int pixels_per_large = 300;
    public int pixels_per_medium = 50;
    public int pixels_per_small = 20;

    int small_pixel_frames = 0;
    int medium_pixel_frames = 0;
    int large_pixel_frames = 0;

    int[] timeline_seconds = { 1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1200, 1800, 3600 };

    public const int BORDER = 4;
    public const int BAR_HEIGHT = 20;
    public const int PIXEL_SNAP_INTERVAL = 10;
    
    public int64 pixel_snap_time;
    
    public signal void selection_changed();
    
    public GapView gap_view;

    public TimeLine(Model.VideoProject p) {
        project = p;
        
        vbox = new Gtk.VBox(false, 0);
        ruler = new Ruler(this);
        vbox.pack_start(ruler, false, false, 0);
        
        foreach (Model.Track track in project.tracks) {
            tracks.add(new TrackView(track, this));
        }
        
        project.position_changed += on_position_changed;
        vbox.pack_start(find_video_track_view(), false, false, 0);
        vbox.pack_start(find_audio_track_view(), false, false, 0);
        add(vbox);
        
        modify_bg(Gtk.StateType.NORMAL, parse_color("#444"));
        modify_fg(Gtk.StateType.NORMAL, parse_color("#f00"));
        
        pixel_div = pixel_max / pixel_min;
        calculate_pixel_step (0.5f);
    }

    int correct_seconds_value (float seconds, int div, int fps) {
        
        if (seconds < 1.0f) {
            int frames = (int)(fps * seconds);
            if (frames == 0)
                return 1;
                
            if (div == 0)
                div = fps;
                
            int mod = div % frames;
            while (mod != 0) {
                mod = div % (++frames);
            }
            return frames;
        }
        
        int i;
        int secs = (int) seconds;
        for (i = timeline_seconds.length - 1; i > 0; i--) {
            if (secs <= timeline_seconds[i] &&
                secs >= timeline_seconds[i - 1]) {
                if ((div % (timeline_seconds[i] * fps)) == 0)
                    break;
                if ((div % (timeline_seconds[i - 1] * fps)) == 0) {
                    i--;
                    break;
                }
            }
        }
        return timeline_seconds[i] * fps;
    }
    
    void calculate_pixel_step(float inc) {
        pixel_percentage += inc;    
        if (pixel_percentage < 0.0f)
            pixel_percentage = 0.0f;
        else if (pixel_percentage > 1.0f)
            pixel_percentage = 1.0f;
         
        pixels_per_second = pixel_min * GLib.Math.powf(pixel_div, pixel_percentage);
            
        int fps = project.get_framerate();
        if (fps == 0)
            fps = 30;          
                    
        large_pixel_frames = correct_seconds_value(pixels_per_large / pixels_per_second, 0, fps);
        medium_pixel_frames = correct_seconds_value(pixels_per_medium / pixels_per_second, 
                                                    large_pixel_frames, fps);
        small_pixel_frames = correct_seconds_value(pixels_per_small / pixels_per_second, 
                                                    medium_pixel_frames, fps);
    
        if (small_pixel_frames == medium_pixel_frames) {
            int i = medium_pixel_frames;
            
            while (--i > 0) {
                if ((medium_pixel_frames % i) == 0) {
                    small_pixel_frames = i;
                    break;
                }
            }
        }
    
        pixels_per_frame = pixels_per_second / (float) fps;
        pixel_snap_time = xsize_to_time(PIXEL_SNAP_INTERVAL);
    }
    
    public void zoom_to_project(double width) {
        double numerator = GLib.Math.log(
                    (width * Gst.SECOND) / ((double) project.get_length() * (double) pixel_min));
        double denominator = GLib.Math.log((double) pixel_div);
        
        zoom((float) (numerator / denominator) - pixel_percentage);
    }
    
    public void zoom (float inc) {
        calculate_pixel_step(inc);
        foreach (TrackView track in tracks) {
            track.resize();
        }
        project.position_changed();
        queue_draw();
    }
    
    void on_position_changed() {
        queue_draw();
    }
    
    public void select_clip(ClipView? w) {
        drag_source_clip = w;
        selected_clip = w;
        queue_draw();
        selection_changed();
    }
    
    public bool is_clip_selected() {
        return selected_clip != null;
    }
    
    public Model.Clip get_selected_clip() {
        return selected_clip.clip;
    }
    
    public bool gap_selected() {
        return gap_view != null;
    }
    
    public void delete_selection(bool ripple) {
        if (selected_clip != null) {
            selected_clip.trackview.track.delete_clip(selected_clip.clip, ripple);
            
            if (ripple) {
                foreach (TrackView track in tracks) {
                    if (selected_clip.trackview != track) {
                        track.track.ripple_delete(selected_clip.clip.length, 
                                            selected_clip.clip.start, selected_clip.clip.length);
                    }
                }
            }
            selected_clip.trackview.clear_drag();
            select_clip(null);
        } else {
            if (gap_view != null) {
                if (!project.delete_gap(gap_view.trackview.track, gap_view.gap, false)) {
                  if (create_delete_cancel_dialog("Confirm", "Really delete single-track gap?") ==
                           Gtk.ResponseType.YES) {
                       project.delete_gap(gap_view.trackview.track, gap_view.gap, true);       
                    }                
                }
                gap_view.trackview.unselect_gap();
            }
        }
    }
    
    public void do_cut(bool ripple) {
        clipboard_clip = selected_clip.clip;
        delete_selection(ripple);
    }
    
    public void do_copy() {
        clipboard_clip = selected_clip.clip;
        selection_changed();
    }
    
    public void paste(bool over) {
        do_paste(clipboard_clip.copy(), project.position, over, true);
    }
    
    public int do_paste(Model.Clip c, int64 pos, bool over, bool new_clip) {
        TrackView view = c.type == Model.MediaType.VIDEO ? 
            find_video_track_view() : find_audio_track_view();
        int do_ripple = view.track.do_clip_paste(c, pos, over, new_clip);
        
        if (do_ripple == -1) {
            Gtk.Dialog d = create_error_dialog("Error", "Cannot paste clip onto another clip.");
            d.run();
            d.destroy();
        } else if (do_ripple == 1) {
            TrackView other = (view == tracks[0]) ? tracks[1] : tracks[0];
            other.track.ripple_paste(c.length, pos);
        }
        queue_draw();
        return do_ripple;
    }
    
    public int64 xpos_to_time(int x) {
        return xsize_to_time(x - BORDER);
    }

    public int64 xsize_to_time(int size) {
        return (int64) ((float)(size * Gst.SECOND) / pixels_per_second);
    }

    public int time_to_xsize(int64 time) {
        return (int) (time * pixels_per_second / Gst.SECOND);
    }
    
    public int frame_to_xsize(int frame) {
        return ((int) (frame * pixels_per_frame));
    }
    
    public int time_to_xpos(int64 time) {
        int pos = time_to_xsize(time) + BORDER;
        
        if (xpos_to_time(pos) != time)
            pos++;
        return pos;
    }
    
    void draw_tick_marks() {
        int x = BORDER;

        Fraction r;
        int fps;
        if (!project.get_framerate_fraction(out r)) {
            r.numerator = 2997;
            r.denominator = 100;
        }
        fps = 30;

        int frame = 0;
        while (x <= allocation.width) {
            x = frame_to_xsize(frame);
            
            if ((frame % medium_pixel_frames) == 0) {
            
                if (medium_pixel_frames == small_pixel_frames &&
                    (medium_pixel_frames != large_pixel_frames &&
                    frame % large_pixel_frames != 0))
                    Gdk.draw_line(window, style.white_gc, x + BORDER, 0, x + BORDER, 2);
                else
                    Gdk.draw_line(window, style.white_gc, x + BORDER, 0, x + BORDER, 6);                
                
                if ((frame % large_pixel_frames) == 0) {
                    Pango.Layout layout = create_pango_layout(frame_to_time(
                                frame, r).to_string());
                    Pango.FontDescription f = Pango.FontDescription.from_string("Sans 8");
                            
                    int w;
                    int h;
                    layout.set_font_description(f);
                    layout.get_pixel_size (out w, out h);
                      
                    Gdk.draw_layout(window, style.white_gc, x - (w / 2) + BORDER, 7, layout);
                }
            } else {
                Gdk.draw_line(window, style.white_gc, x + BORDER, 0, x + BORDER, 2);
            }
            frame += small_pixel_frames;
        }
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        base.expose_event(event);

        draw_tick_marks();
        int xpos = time_to_xpos(project.position);
        Gdk.draw_line(window, style.fg_gc[(int) Gtk.StateType.NORMAL],
                      xpos, 0,
                      xpos, allocation.height);
        
        if (!shift_pressed) {
            foreach (TrackView track in tracks) {
                if (track.dragging && track.drag_intersect) {
                    Gdk.draw_line(window, style.white_gc, 
                                track.drag_x_coord, 0, 
                                track.drag_x_coord, allocation.height);
                }
            }
        }
        
        return true;
    }

    public void update_pos(int event_x) {
        int64 time = xpos_to_time(event_x);
        
        project.snap_coord(out time, pixel_snap_time);
        project.go(time);
    }

    public void set_control_pressed(bool c) {
        if (c == control_pressed) return;
        
        control_pressed = c;
        if (selected_clip != null &&
            selected_clip.trackview.dragging)
            selected_clip.trackview.update_drag_clip();
        queue_draw();
    }

    public void set_shift_pressed(bool s) {
        shift_pressed = s;
        
        TrackView t = drag as TrackView;
        if (t != null) {
            if (t.dragging)
                t.update_intersect_state();
            queue_draw();
        }
    }
    
    public void escape_pressed() {
        TrackView t = drag as TrackView;
        if (t != null) {
            if (t.dragging)
                t.cancel_drag();
            queue_draw();
        }
    }

    Gtk.Widget? find_child(double x, double y) {
        foreach (Gtk.Widget w in vbox.get_children())
            if (w.allocation.y <= y && y < w.allocation.y + w.allocation.height)
                return w;
        return null;
    }

    public override bool button_press_event(Gdk.EventButton event) {
        if (gap_view != null)
            gap_view.trackview.unselect_gap();
        
        drag = find_child(event.x, event.y);
        if (drag != null)
            drag.button_press_event(event);
        queue_draw();
        
        return false;
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        if (drag != null) {
            drag.motion_notify_event(event);
            queue_draw();
        }
        return false;
    }

    public override bool button_release_event(Gdk.EventButton event) {
        if (drag != null) {
            drag.button_release_event(event);
            drag = null;
            queue_draw();
        }
        
        if (selected_clip != null && event.button == 3) {
            context_menu.select_first(true);
            context_menu.popup(null, null, null, 0, 0);
        } else context_menu.popdown();

        return false;
    }

    public void show_clip_properties(Gtk.Window parent) {
        Gtk.Dialog d = new Gtk.Dialog.with_buttons("Clip Properties", parent, 
                                    Gtk.DialogFlags.MODAL, Gtk.STOCK_OK, Gtk.ResponseType.ACCEPT);
        Gtk.Table t = new Gtk.Table(8, 2, false);
        int row = 0;
        int tab_padding = 25;
        
        for (int i = 0; i < 8; i++)
            t.set_row_spacing(i, 10);
            
        row = 1;
        add_label_to_table(t, "<b>Clip</b>", 0, row++, 5, 0);
        
        add_label_to_table(t, "<i>Name:</i>", 0, row, tab_padding, 0);
        add_label_to_table(t, "%s".printf(selected_clip.clip.name), 1, row++, 5, 0);
    
        add_label_to_table(t, "<i>Location:</i>", 0, row, tab_padding, 0);
        add_label_to_table(t, "%s".printf(selected_clip.clip.clipfile.filename), 1, row++, 5, 0); 
    
        add_label_to_table(t, "<i>Timeline length:</i>", 0, row, tab_padding, 0);
    
        Fraction f;
        if (!project.get_framerate_fraction(out f)) {
            f.numerator = 2997;
            f.denominator = 100;
        }    
        Time time = frame_to_time (time_to_frame_with_rate(selected_clip.clip.length, f), f);
        add_label_to_table(t, "%s".printf(time.to_string()), 1, row++, 5, 0);
        
        if (selected_clip.clip.is_trimmed()) {
            add_label_to_table(t, "<i>Actual length:</i>", 0, row, tab_padding, 0);
            time = frame_to_time(time_to_frame_with_rate(selected_clip.clip.clipfile.length, f), f);
            add_label_to_table(t, "%s".printf(time.to_string()), 1, row++, 5, 0);
        }
    
        if (selected_clip.clip.clipfile.has_caps_structure(Model.MediaType.VIDEO)) {   
            add_label_to_table(t, "<b>Video</b>", 0, row++, 5, 0);

            int w, h;
            if (selected_clip.clip.clipfile.get_dimensions(out w, out h)) {
                add_label_to_table(t, "<i>Dimensions:</i>", 0, row, tab_padding, 0);
                add_label_to_table(t, "%d x %d".printf(w, h), 1, row++, 5, 0);
            }

            Fraction r;
            if (selected_clip.clip.clipfile.get_frame_rate(out r)) {
                add_label_to_table(t, "<i>Frame rate:</i>", 0, row, tab_padding, 0);
                
                if (r.numerator % r.denominator != 0)
                    add_label_to_table(t, 
                               "%.2f frames per second".printf(r.numerator / (float)r.denominator), 
                               1, row++, 5, 0);
                else
                    add_label_to_table(t, 
                                "%d frames per second".printf(r.numerator / r.denominator), 
                                1, row++, 5, 0);
            }
        }

        if (selected_clip.clip.clipfile.has_caps_structure(Model.MediaType.AUDIO)) {
            add_label_to_table(t, "<b>Audio</b>", 0, row++, 5, 0);
           
            int rate;
            if (selected_clip.clip.clipfile.get_sample_rate(out rate)) {
                add_label_to_table(t, "<i>Sample Rate:</i>", 0, row, tab_padding, 0);
                add_label_to_table(t, "%d Hz".printf(rate), 1, row++, 5, 0);
            }

            string s;
            if (selected_clip.clip.clipfile.get_num_channels_string(out s)) {
                add_label_to_table(t, "<i>Number of channels:</i>", 0, row, tab_padding, 0);
                add_label_to_table(t, "%s".printf(s), 1, row++, 5, 0);
            }
        } 
    
        d.vbox.pack_start(t, false, false, 0);
        d.set_size_request(400, 300);
    
        d.show_all();
        d.run();
        d.destroy();
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
