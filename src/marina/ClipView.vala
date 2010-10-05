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
        Cairo.Context context = Gdk.cairo_create(window);
        draw_rounded_rectangle(context, fill_color, true, allocation.x, allocation.y, 
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

    public enum SelectionType {
        NONE,
        ADD,
        EXTEND
    }

    public Model.Clip clip;
    public int64 initial_time;
    weak Model.TimeSystem time_provider;
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
    SelectionType selection_type;
    const int MIN_DRAG = 5;
    const int TRIM_WIDTH = 10;
    public const int SNAP_DELTA = 10;

    static Gdk.Cursor left_trim_cursor = new Gdk.Cursor(Gdk.CursorType.LEFT_SIDE);
    static Gdk.Cursor right_trim_cursor = new Gdk.Cursor(Gdk.CursorType.RIGHT_SIDE);
    static Gdk.Cursor hand_cursor = new Gdk.Cursor.from_name(Gdk.Display.get_default(), "dnd-none");
    // will be used for drag
    static Gdk.Cursor plus_cursor = new Gdk.Cursor.from_name(Gdk.Display.get_default(), "dnd-copy");

    public signal void clip_deleted(Model.Clip clip);
    public signal void clip_moved();
    public signal void selection_request(SelectionType selection_type);
    public signal void move_request(int64 delta);
    public signal void move_commit(int64 delta);
    public signal void move_begin(bool copy);
    public signal void trim_begin(Gdk.WindowEdge edge);
    public signal void trim_request(Gdk.WindowEdge edge, int64 delta);
    public signal void trim_commit(Gdk.WindowEdge edge);
    public signal void selection_changed();
    public ClipView(TransportDelegate transport_delegate, Model.Clip clip, 
            Model.TimeSystem time_provider, int height) {
        this.transport_delegate = transport_delegate;
        this.clip = clip;
        this.time_provider = time_provider;
        this.height = height;

        clip.moved.connect(on_clip_moved);
        clip.updated.connect(on_clip_updated);
        clip.selection_changed.connect(on_selection_changed);

        Gdk.Color.parse("000", out color_black);
        get_clip_colors();

        set_flags(Gtk.WidgetFlags.NO_WINDOW);

        adjust_size(height);
    }

    public TrackView get_track_view() {
        return get_parent() as TrackView;
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

    void on_selection_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_selection_changed");
        selection_changed();
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
        clip_moved();
    }

    public void delete_clip() {
        clip_deleted(clip);
    }

    public void draw(Cairo.Context context) {
        context.save();
        weak Gdk.Color fill = clip.is_selected ? color_selected : color_normal;

        bool left_trimmed = clip.media_start != 0 && !clip.is_recording;

        bool right_trimmed = clip.mediafile.is_online() ? 
                              (clip.media_start + clip.duration != clip.mediafile.length) : false;

        if (!left_trimmed && !right_trimmed) {
            draw_rounded_rectangle(context, fill, true, allocation.x + 1, allocation.y + 1,
                                   allocation.width - 2, allocation.height - 2);
            draw_rounded_rectangle(context, color_black, false, allocation.x, allocation.y,
                                   allocation.width - 1, allocation.height - 1);

        } else if (!left_trimmed && right_trimmed) {
            draw_left_rounded_rectangle(context, fill, true, allocation.x + 1, allocation.y + 1,
                                        allocation.width - 2, allocation.height - 2);
            draw_left_rounded_rectangle(context, color_black, false, allocation.x, allocation.y,
                                   allocation.width - 1, allocation.height - 1);

        } else if (left_trimmed && !right_trimmed) {
            draw_right_rounded_rectangle(context, fill, true, allocation.x + 1, allocation.y + 1,
                                         allocation.width - 2, allocation.height - 2);
            draw_right_rounded_rectangle(context, color_black, false, allocation.x, allocation.y,
                                         allocation.width - 1, allocation.height - 1);

        } else {
            draw_square_rectangle(context, fill, true, allocation.x + 1, allocation.y + 1,
                                  allocation.width - 2, allocation.height - 2);
            draw_square_rectangle(context, color_black, false, allocation.x, allocation.y,
                                  allocation.width - 1, allocation.height - 1);
        }

        context.rectangle(allocation.x, allocation.y, allocation.width, allocation.height);
        context.clip();
        Pango.Layout layout = Pango.cairo_create_layout(context);
        Gdk.Color color = style.text[Gtk.StateType.NORMAL];

        context.set_source_rgb(color.red, color.green, color.blue);
        layout.set_font_description(style.font_desc);
        string s;
        if (clip.is_recording) {
            s = "Recording";
        } else if (!clip.mediafile.is_online()) {
            s = "%s (Offline)".printf(clip.name);
        }
        else {
            s = "%s".printf(clip.name);
        }
        layout.set_text(s, (int) s.length);

        int width, height;
        layout.get_pixel_size(out width, out height);
        context.move_to(allocation.x + 10, allocation.y + height);
        Pango.cairo_show_layout(context, layout);
        context.restore();
    }

    public override bool expose_event(Gdk.EventExpose event) {
        Cairo.Context context = Gdk.cairo_create(window);
        draw(context);
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

        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            selection_type = SelectionType.ADD;
        } else if ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0) {
            selection_type = SelectionType.EXTEND;
        } else {
            selection_type = SelectionType.NONE;
        }
        // The clip is not responsible for changing the selection state.
        // It may depend upon knowledge of multiple clips.  Let anyone who is interested
        // update our state.
        if (is_left_trim(event.x, event.y)) {
            selection_request(SelectionType.NONE);
            if (primary_press) {
                trim_begin(Gdk.WindowEdge.WEST);
                motion_mode = MotionMode.LEFT_TRIM;
            }
        } else if (is_right_trim(event.x, event.y)){
            selection_request(SelectionType.NONE);
            if (primary_press) {
                trim_begin(Gdk.WindowEdge.EAST);
                motion_mode = MotionMode.RIGHT_TRIM;
            }
        } else {
            if (!clip.is_selected) {
                pending_selection = false;
                selection_request(selection_type);
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
                        selection_request(SelectionType.ADD);
                    }
                }
                break;
                case MotionMode.DRAGGING: {
                    int64 delta = time_provider.xsize_to_time((int) event.x - drag_point);
                    if (motion_mode == MotionMode.DRAGGING) {
                        move_commit(delta);
                    }
                }
                break;
                case MotionMode.LEFT_TRIM:
                    trim_commit(Gdk.WindowEdge.WEST);
                break;
                case MotionMode.RIGHT_TRIM:
                    trim_commit(Gdk.WindowEdge.EAST);
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
                } else if (clip.is_selected && button_down) {
                    if (delta_pixels.abs() > MIN_DRAG) {
                        bool do_copy = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
                        if (do_copy) {
                            window.set_cursor(plus_cursor);
                        } else {
                            window.set_cursor(hand_cursor);
                        }
                        motion_mode = MotionMode.DRAGGING;
                        move_begin(do_copy);
                    }
                } else {
                    window.set_cursor(null);
                }
            break;
            case MotionMode.RIGHT_TRIM:
                if (button_down) {
                    int64 duration = clip.duration;
                    trim_request(Gdk.WindowEdge.EAST, delta_time);
                    if (duration != clip.duration) {
                        drag_point += time_provider.time_to_xsize(clip.duration - duration);
                    }
                    return true;
                }
            break;
            case MotionMode.LEFT_TRIM:
                if (button_down) {
                    trim_request(Gdk.WindowEdge.WEST, delta_time);
                }
                return true;
            case MotionMode.DRAGGING:
                move_request(delta_time);
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
        if (!clip.is_selected) {
            selection_request(SelectionType.ADD);
        }
    }
    
    public void snap(int64 amount) {
        snap_amount = time_provider.time_to_xsize(amount);
        snapped = true;
    }
}
