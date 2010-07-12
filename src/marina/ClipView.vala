/* Copyright 2009-2010 Yorba Foundation
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
    TransportDelegate transport_delegate;
    Gdk.Color color_black;
    Gdk.Color color_normal;
    Gdk.Color color_selected;
    int drag_point;
    int snap_amount;
    bool snapped;
    MotionMode motion_mode = MotionMode.NONE;
    bool button_down = false;
    bool pending_selection;
    const int MIN_DRAG = 5;
    const int TRIM_WIDTH = 10;
    public const int SNAP_DELTA = 10;

    static Gdk.Cursor left_trim_cursor = new Gdk.Cursor(Gdk.CursorType.LEFT_SIDE);
    static Gdk.Cursor right_trim_cursor = new Gdk.Cursor(Gdk.CursorType.RIGHT_SIDE);
    static Gdk.Cursor hand_cursor = new Gdk.Cursor.from_name(Gdk.Display.get_default(), "dnd-none");
    // will be used for drag
    static Gdk.Cursor plus_cursor = new Gdk.Cursor.from_name(Gdk.Display.get_default(), "dnd-copy");

    public signal void clip_deleted(Model.Clip clip);
    public signal void clip_moved(ClipView clip);
    public signal void selection_request(ClipView clip_view, bool extend_selection);
    public signal void move_request(ClipView clip_view, int64 delta);
    public signal void move_commit(ClipView clip_view, int64 delta);
    public signal void move_begin(ClipView clip_view, bool copy);
    public signal void trim_begin(ClipView clip_view, Gdk.WindowEdge edge);
    public signal void trim_request(ClipView clip_view, Gdk.WindowEdge edge, int64 delta);
    public signal void trim_commit(ClipView clip_view, Gdk.WindowEdge edge);

    public ClipView(TransportDelegate transport_delegate, Model.Clip clip, 
            Model.TimeSystem time_provider, int height) {
        this.transport_delegate = transport_delegate;
        this.clip = clip;
        this.time_provider = time_provider;
        this.height = height;
        is_selected = false;

        clip.moved.connect(on_clip_moved);
        clip.updated.connect(on_clip_updated);

        Gdk.Color.parse("000", out color_black);
        get_clip_colors();

        set_flags(Gtk.WidgetFlags.NO_WINDOW);

        adjust_size(height);
    }

    void get_clip_colors() {
        if (clip.mediafile.is_online()) {
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

        bool right_trimmed = clip.mediafile.is_online() ? 
                              (clip.media_start + clip.duration != clip.mediafile.length) : false;

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
        } else if (!clip.mediafile.is_online()) {
            layout = create_pango_layout("%s (Offline)".printf(clip.name));
        }
        else {
            layout = create_pango_layout("%s".printf(clip.name));
        }
        int width, height;
        layout.get_pixel_size(out width, out height);
        Gdk.draw_layout(window, gc, allocation.x + 10, allocation.y + height, layout);
    }

    public override bool expose_event(Gdk.EventExpose event) {
        draw();
        return true;
    }

    public override bool button_press_event(Gdk.EventButton event) {
        if (!transport_delegate.is_stopped()) {
            return false;
        }

        event.x -= allocation.x;
        bool primary_press = event.button == 1;
        if (primary_press) {
            button_down = true;
            drag_point = (int)event.x;
            snap_amount = 0;
            snapped = false;
        }

        bool extend_selection = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
        // The clip is not responsible for changing the selection state.
        // It may depend upon knowledge of multiple clips.  Let anyone who is interested
        // update our state.
        if (is_left_trim(event.x, event.y)) {
            selection_request(this, false);
            if (primary_press) {
                trim_begin(this, Gdk.WindowEdge.WEST);
                motion_mode = MotionMode.LEFT_TRIM;
            }
        } else if (is_right_trim(event.x, event.y)){
            selection_request(this, false);
            if (primary_press) {
                trim_begin(this, Gdk.WindowEdge.EAST);
                motion_mode = MotionMode.RIGHT_TRIM;
            }
        } else {
            if (!is_selected) {
                pending_selection = false;
                selection_request(this, extend_selection);
            } else {
                pending_selection = true;
            }
        }

        if (event.button == 3) {
            context_menu.select_first(true);
            context_menu.popup(null, null, null, event.button, event.time);
        } else {
            context_menu.popdown();
        }

        return false;
    }

    public override bool button_release_event(Gdk.EventButton event) {
        if (!transport_delegate.is_stopped()) {
            return false;
        }

        event.x -= allocation.x;
        button_down = false;
        if (event.button == 1) {
            switch (motion_mode) {
                case MotionMode.NONE: {
                    if (pending_selection) {
                        selection_request(this, true);
                    }
                }
                break;
                case MotionMode.DRAGGING: {
                    int64 delta = time_provider.xsize_to_time((int) event.x - drag_point);
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
        return false;
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        if (!transport_delegate.is_stopped()) {
            return true;
        }

        event.x -= allocation.x;
        int delta_pixels = (int)(event.x - drag_point) - snap_amount;
        if (snapped) {
            snap_amount += delta_pixels;
            if (snap_amount.abs() < SNAP_DELTA) {
                return true;
            }
            delta_pixels += snap_amount;
            snap_amount = 0;
            snapped = false;
        }

        int64 delta_time = time_provider.xsize_to_time(delta_pixels);

        switch (motion_mode) {
            case MotionMode.NONE:
                if (!button_down && is_left_trim(event.x, event.y)) {
                    window.set_cursor(left_trim_cursor);
                } else if (!button_down && is_right_trim(event.x, event.y)) {
                    window.set_cursor(right_trim_cursor);
                } else if (is_selected && button_down) {
                    if (delta_pixels.abs() > MIN_DRAG) {
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
                if (button_down) {
                    int64 duration = clip.duration;
                    trim_request(this, Gdk.WindowEdge.EAST, delta_time);
                    if (duration != clip.duration) {
                        drag_point += time_provider.time_to_xsize(clip.duration - duration);
                    }
                    return true;
                }
            break;
            case MotionMode.LEFT_TRIM:
                if (button_down) {
                    trim_request(this, Gdk.WindowEdge.WEST, delta_time);
                }
                return true;
            case MotionMode.DRAGGING:
                move_request(this, delta_time);
                return true;
        }
        return false;
    }

    bool is_trim_height(double y) {
        return y - allocation.y > allocation.height / 2;
    }

    bool is_left_trim(double x, double y) {
        return is_trim_height(y) && x > 0 && x < TRIM_WIDTH;
    }

    bool is_right_trim(double x, double y) {
        return is_trim_height(y) && x > allocation.width - TRIM_WIDTH && 
            x < allocation.width;
    }

    public void select() {
        if (!is_selected) {
            selection_request(this, true);
        }
    }
    
    public void snap(int64 amount) {
        snap_amount = time_provider.time_to_xsize(amount);
        snapped = true;
    }
}
