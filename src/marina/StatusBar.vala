/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace View {
public class StatusBar : Gtk.DrawingArea {
    Model.TimeSystem provider;
    int64 current_position = 0;
    
    public StatusBar(Model.Project p, Model.TimeSystem provider, int height) {
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        modify_bg(Gtk.StateType.NORMAL, parse_color("#666"));
        set_size_request(0, height);
        
        p.media_engine.position_changed.connect(on_position_changed);
        this.provider = provider;
    }
    
    public void on_position_changed(int64 new_position) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_position_changed");
        current_position = new_position;
        queue_draw();
    }
    
    public override bool expose_event(Gdk.EventExpose e) {
        window.draw_rectangle(style.bg_gc[(int) Gtk.StateType.NORMAL], true, 
                              allocation.x, allocation.y, allocation.width, allocation.height);  

        string time = provider.get_time_string(current_position);

        Pango.Layout layout = create_pango_layout(time);         
        Gdk.draw_layout(window, style.white_gc, allocation.x + 4, allocation.y + 2, layout);
                                
        return true;
    }
}
}
