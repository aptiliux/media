/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

public class GapView : Gtk.DrawingArea {
    public Model.Gap gap;
    Gdk.Color fill_color;
    
    public GapView(int64 start, int64 length, int width, int height) {

        gap = new Model.Gap(start, start + length);         
        
        Gdk.Color.parse("#777", out fill_color);
        
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        
        set_size_request(width, height);
    }  
    
    public signal void removed(GapView gap_view);
    public signal void unselected(GapView gap_view);
    
    public void remove() {
        removed(this);
    }
    
    public void unselect() {
        unselected(this);
    }
    
    public override bool expose_event(Gdk.EventExpose e) {
        draw_rounded_rectangle(window, fill_color, true, allocation.x, allocation.y, 
                                allocation.width - 1, allocation.height - 1);
        return true;
    }
}

public class ClipView : Gtk.DrawingArea {
    enum MotionMode {
        NONE,
        DRAGGING,
        LEFT_TRIM,
        RIGHT_TRIM
    }
    
    public Model.Clip clip;
    public int64 initial_time;
    weak Model.TimeSystem time_provider;
    public bool is_selected;
    public int height; // TODO: We request size of height, but we aren't allocated this height.
                       // We should be using the allocated height, not the requested height. 
    public static Gtk.Menu context_menu;
    Gdk.Color color_black;    
    Gdk.Color color_normal;
    Gdk.Color color_selected;
    int drag_point;
    MotionMode motion_mode = MotionMode.NONE;
    bool button_down = false;
    const int MIN_DRAG = 5;
    const int TRIM_WIDTH = 10;
    
    static Gdk.Cursor left_trim_cursor = new Gdk.Cursor(Gdk.CursorType.LEFT_SIDE);
    static Gdk.Cursor right_trim_cursor = new Gdk.Cursor(Gdk.CursorType.RIGHT_SIDE);
    static Gdk.Cursor hand_cursor = new Gdk.Cursor(Gdk.CursorType.HAND1);
    static Gdk.Cursor plus_cursor = new Gdk.Cursor(Gdk.CursorType.HAND2); // will be used for drag
    
    public signal void clip_deleted(Model.Clip clip);
    public signal void clip_moved(ClipView clip);
    public signal void selection_request(ClipView clip_view, bool extend_selection);
    public signal void move_request(ClipView clip_view, int delta);
    public signal void move_commit(ClipView clip_view, int delta);
    public signal void move_begin(ClipView clip_view, bool copy);
    public signal void trim_begin(ClipView clip_view, Gdk.WindowEdge edge);
    public signal void trim_commit(ClipView clip_view, Gdk.WindowEdge edge);
    
    public ClipView(Model.Clip clip, Model.TimeSystem time_provider, int height) {
        this.clip = clip;
        this.time_provider = time_provider;
        this.height = height;
        is_selected = false;
        
        clip.moved += on_clip_moved;
        clip.updated += on_clip_updated;

        Gdk.Color.parse("000", out color_black);
        get_clip_colors();
        
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
              
        adjust_size(height);
    }

    void get_clip_colors() {
        if (clip.clipfile.is_online()) {
            Gdk.Color.parse(clip.type == Model.MediaType.VIDEO ? "#d82" : "#84a", 
                out color_selected);
            Gdk.Color.parse(clip.type == Model.MediaType.VIDEO ? "#da5" : "#b9d", 
                out color_normal);
        } else {
            Gdk.Color.parse("red", out color_selected);
            Gdk.Color.parse("#AA0000", out color_normal);
        }
    }
    
    void on_clip_updated() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_updated");
        get_clip_colors();
        queue_draw();
    }

    // Note that a view's size may vary slightly (by a single pixel) depending on its
    // starting position.  This is because the clip's length may not be an integer number of
    // pixels, and may get rounded either up or down depending on the clip position.
    public void adjust_size(int height) {       
        int width = time_provider.time_to_xpos(clip.start + clip.duration) -
                    time_provider.time_to_xpos(clip.start);                  
        set_size_request(width + 1, height);
    }
    
    public void on_clip_moved(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_moved");
        adjust_size(height);
        clip_moved(this);
    }

    public void delete_clip() {
        clip_deleted(clip);
    }
    
    public void draw() {
        weak Gdk.Color fill = is_selected ? color_selected : color_normal;
                                                                         
        bool left_trimmed = clip.media_start != 0 && !clip.is_recording;
        
        bool right_trimmed = clip.clipfile.is_online() ? 
                              (clip.media_start + clip.duration != clip.clipfile.length) : false;
            
        if (!left_trimmed && !right_trimmed) {
            draw_rounded_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                   allocation.width - 2, allocation.height - 2);
            draw_rounded_rectangle(window, color_black, false, allocation.x, allocation.y,
                                   allocation.width - 1, allocation.height - 1);
                                   
        } else if (!left_trimmed && right_trimmed) {
            draw_left_rounded_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                        allocation.width - 2, allocation.height - 2);
            draw_left_rounded_rectangle(window, color_black, false, allocation.x, allocation.y,
                                   allocation.width - 1, allocation.height - 1);
                                   
        } else if (left_trimmed && !right_trimmed) {
            draw_right_rounded_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                         allocation.width - 2, allocation.height - 2);
            draw_right_rounded_rectangle(window, color_black, false, allocation.x, allocation.y,
                                         allocation.width - 1, allocation.height - 1);

        } else {
            draw_square_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                  allocation.width - 2, allocation.height - 2);
            draw_square_rectangle(window, color_black, false, allocation.x, allocation.y,
                                  allocation.width - 1, allocation.height - 1);
        }
           
        Gdk.GC gc = new Gdk.GC(window);
        Gdk.Rectangle r = { 0, 0, 0, 0 };

        // Due to a Vala compiler bug, we have to do this initialization here...
        r.x = allocation.x;
        r.y = allocation.y;
        r.width = allocation.width;
        r.height = allocation.height;
        
        gc.set_clip_rectangle(r);

        Pango.Layout layout;
        if (clip.is_recording) {
            layout = create_pango_layout("Recording");
        } else if (!clip.clipfile.is_online()) {
            layout = create_pango_layout("%s (Offline)".printf(clip.name));
        }
        else {
            layout = create_pango_layout("%s".printf(clip.name));
        }
        Gdk.draw_layout(window, gc, allocation.x + 10, allocation.y + 14, layout);
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        draw();
        return true;
    }
    
    public override bool button_press_event(Gdk.EventButton event) {
        event.x -= allocation.x;
        button_down = true;
        drag_point = (int)event.x;
        bool extend_selection = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
        // The clip is not responsible for changing the selection state.
        // It may depend upon knowledge of multiple clips.  Let anyone who is interested
        // update our state.
        if (is_left_trim(event.x, event.y)) {
            selection_request(this, false);
            trim_begin(this, Gdk.WindowEdge.WEST);
            motion_mode = MotionMode.LEFT_TRIM;
        } else if (is_right_trim(event.x, event.y)){
            selection_request(this, false);
            trim_begin(this, Gdk.WindowEdge.EAST);
            motion_mode = MotionMode.RIGHT_TRIM;
        } else {
            selection_request(this, extend_selection);
        }
        return true;
    }
    
    public override bool button_release_event(Gdk.EventButton event) {
        event.x -= allocation.x;
        button_down = false;
        
        if (event.button == 3) {
            context_menu.select_first(true);
            context_menu.popup(null, null, null, 0, 0);
        } else {
            context_menu.popdown();
        }
        
        if (event.button == 1) {
            switch (motion_mode) {
                case MotionMode.DRAGGING: {
                    int delta = (int) event.x - drag_point;
                    if (motion_mode == MotionMode.DRAGGING) {
                        move_commit(this, delta);
                    }
                }
                break;
                case MotionMode.LEFT_TRIM:
                    trim_commit(this, Gdk.WindowEdge.WEST);
                break;
                case MotionMode.RIGHT_TRIM:
                    trim_commit(this, Gdk.WindowEdge.EAST);
                break;
            }
        }
        motion_mode = MotionMode.NONE;
        return true;
    }
    
    public override bool motion_notify_event(Gdk.EventMotion event) {
        event.x -= allocation.x;
        int delta = (int) event.x - drag_point;
        
        switch (motion_mode) {
            case MotionMode.NONE:
                if (is_left_trim(event.x, event.y)) {
                    window.set_cursor(left_trim_cursor);
                } else if (is_right_trim(event.x, event.y)) {
                    window.set_cursor(right_trim_cursor);
                } else if (is_selected && button_down) {
                    if (delta.abs() > MIN_DRAG) {
                        bool do_copy = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
                        if (do_copy) {
                            window.set_cursor(plus_cursor);
                        } else {
                            window.set_cursor(hand_cursor);                        
                        }
                        motion_mode = MotionMode.DRAGGING;
                        move_begin(this, do_copy);
                    }
                } else {
                    window.set_cursor(null);
                }
            break;
            case MotionMode.RIGHT_TRIM:
            case MotionMode.LEFT_TRIM:
                if (button_down) {
                    int64 time_delta = time_provider.xsize_to_time(delta);
                    if (motion_mode == MotionMode.LEFT_TRIM) {
                        if (clip.media_start + time_delta < 0) {
                            return true;
                        }
                        if (clip.duration - time_delta < 0) {
                            return true;
                        }
                        clip.trim(time_delta, Gdk.WindowEdge.WEST);
                    } else {
                        int64 duration = clip.duration;
                        clip.trim(time_delta, Gdk.WindowEdge.EAST);
                        if (duration != clip.duration) {
                            drag_point += (int)delta;
                        }
                    }
                }
                return true;
            case MotionMode.DRAGGING:
                move_request(this, delta);
                return true;
        }
        return false;
    }

    bool is_trim_height(double y) {
        return y > allocation.height / 2;
    }

    bool is_left_trim(double x, double y) {
        return is_trim_height(y) && x > 0 && x < TRIM_WIDTH;
    }
    
    bool is_right_trim(double x, double y) {
        return is_trim_height(y) && x > allocation.width - TRIM_WIDTH && 
            x < allocation.width;
    }    
}
