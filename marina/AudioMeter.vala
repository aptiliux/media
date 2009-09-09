/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
namespace View {
public class AudioMeter : Gtk.DrawingArea {
    Cairo.ImageSurface meter;
    Cairo.ImageSurface silkscreen;
    
    double current_level;
    const double minDB = -70;
    
    public AudioMeter(Model.AudioTrack track) {
        meter = null;
        current_level = -100;
        this.requisition.height = 5;
        expose_event += on_expose_event;
        track.level_changed += on_level_changed;
    }
    
    public bool on_expose_event(Gdk.EventExpose event) {
        Gdk.Window window = get_window();
        Cairo.Context context = Gdk.cairo_create(window);
        if (meter == null) {
            meter = new Cairo.ImageSurface(Cairo.Format.ARGB32, 
                allocation.width, allocation.height);
            Cairo.Context context2 = new Cairo.Context(meter);
            Cairo.Pattern pat = new Cairo.Pattern.linear(0, 0, allocation.width, 0);
            pat.add_color_stop_rgb(0, 0.1, 1, 0.4);
            pat.add_color_stop_rgb(0.8, 1, 1, 0);
            pat.add_color_stop_rgb(1, 1, 0, 0);
            context2.set_source(pat);
            context2.rectangle(0, 0, allocation.width, allocation.height);
            context2.fill();
            
            silkscreen = new Cairo.ImageSurface(Cairo.Format.ARGB32,
                allocation.width, allocation.height);
            context2 = new Cairo.Context(silkscreen);
            context2.set_source_rgba(0, 0, 0, 0);
            context2.rectangle(0, 0, allocation.width, allocation.height);
            context2.fill();
            
            // draw the segment edges
            for (int i=0;i<20;++i) {
                context2.set_source_rgba(0, 0, 0, 1);
                context2.rectangle(i * allocation.width / 20, 0, 3, allocation.height);
                context2.fill();
            }
            
            // draw a bevel around the edge
            context2.set_line_width(1.1);
            context2.set_source_rgba(0.9, 0.9, 0.9, 0.5);
            context2.rectangle(0, 0, allocation.width, allocation.height);
            context2.stroke();
        }

        int width = (int) ((current_level - minDB) * allocation.width / -minDB);
        context.set_source_rgb(0, 0, 0);
        context.rectangle(0, 0, allocation.width, allocation.height);
        context.fill();
        
        context.set_source_surface(meter, 0, 0);
        context.rectangle(0, 0, width, allocation.height);
        context.clip();
        context.paint_with_alpha(1);

        context.set_source_surface(silkscreen, 0, 0);
        context.paint_with_alpha(1);


        return true;
    }
    
    public void on_level_changed(double level) {
        current_level = level < minDB ? minDB : level;
        Gdk.Window window = get_window();
        window.invalidate_rect(null, false);
    }
}
}
