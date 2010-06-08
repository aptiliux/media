/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace View {
public class AudioMeter : Gtk.DrawingArea {
    Cairo.ImageSurface meter = null;
    Cairo.ImageSurface silkscreen;
    
    bool stereo = false;
    double current_level_left = -100;
    double current_level_right = -100;
    const double minDB = -70;
    
    public AudioMeter(Model.AudioTrack track) {
        int number_of_channels;
        if (track.get_num_channels(out number_of_channels)) {
            stereo = number_of_channels < 1;
        }

        this.requisition.height = 10;
        expose_event.connect(on_expose_event);
        track.level_changed.connect(on_level_changed);
        track.channel_count_changed.connect(on_channel_count_changed);
    }

    void initialize_meter() {
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

    public bool on_expose_event(Gdk.EventExpose event) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_expose_event");
        Gdk.Window window = get_window();
        Cairo.Context context = Gdk.cairo_create(window);
        if (meter == null) {
            initialize_meter();
        }

        context.set_source_rgb(0, 0, 0);
        context.rectangle(0, 0, allocation.width, allocation.height);
        context.fill();

        int bar_height = stereo ? (allocation.height / 2) - 1 : allocation.height - 2;

        if (stereo) {
            context.set_source_rgb(1, 1, 1);
            context.rectangle(0, bar_height + 1, allocation.width, 0.3);
            context.fill();
        }

        context.set_source_surface(meter, 0, 0);
        int width = (int) (Math.pow10(current_level_left / 40) * allocation.width);
        context.rectangle(0, 1, width, bar_height);

        if (stereo) {
            width = (int) (Math.pow10(current_level_right / 40) * allocation.width);
            context.rectangle(0, bar_height + 2, width, bar_height);
        }

        context.clip();
        context.paint_with_alpha(1);

        context.set_source_surface(silkscreen, 0, 0);
        context.paint_with_alpha(1);

        return true;
    }

    public void on_level_changed(double level_left, double level_right) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_level_changed");
        current_level_left = level_left < minDB ? minDB : level_left;
        current_level_right = level_right < minDB ? minDB : level_right;
        Gdk.Window window = get_window();
        window.invalidate_rect(null, false);
    }

    public void on_channel_count_changed(int number_of_channels) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_channel_count_changed");
        stereo = number_of_channels > 1;
        window.invalidate_rect(null, false);
    }
}
}
