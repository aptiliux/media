/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
 
namespace View {
public class Ruler : Gtk.DrawingArea {
    weak Model.TimeProvider provider;
    const int BORDER = 4;

    public signal void position_changed(int x);
    
    public Ruler(Model.TimeProvider provider, int height) {
        this.provider = provider;
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        modify_bg(Gtk.StateType.NORMAL, parse_color("#777"));
        set_size_request(0, height);
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        window.draw_rectangle(style.bg_gc[(int) Gtk.StateType.NORMAL],
                            true, allocation.x, allocation.y, allocation.width, allocation.height);
        int x = BORDER;

        int frame = 0;
        while (x <= allocation.width) {
            x = provider.frame_to_xsize(frame);
            int y = provider.get_pixel_height(frame);
            Gdk.draw_line(window, style.white_gc, x + BORDER, 0, x + BORDER, y);
            string? display_string = provider.get_display_string(frame);
            if (display_string != null) {
                Pango.Layout layout = create_pango_layout(display_string);
                Pango.FontDescription f = Pango.FontDescription.from_string("Sans 8");
                        
                int w;
                int h;
                layout.set_font_description(f);
                layout.get_pixel_size (out w, out h);
                int text_pos = x - (w / 2) + BORDER;
                if (text_pos < 0) {
                    text_pos = 0;
                }
                
                Gdk.draw_layout(window, style.white_gc, text_pos, 7, layout);
            }
            
            frame = provider.get_next_position(frame);
        }
        return true;
    }
    
    public override bool button_press_event(Gdk.EventButton event) {
        position_changed((int) event.x);
        return false;
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        position_changed((int) event.x);
        return false;
    }
}
}
