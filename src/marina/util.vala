/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public errordomain MediaError {
    MISSING_PLUGIN
}

// I can't find a floating point absolute value function in Vala...
public float float_abs(float f) {
    if (f < 0.0f)
        return -f;
    return f;
}

public bool float_within(double f, double epsilon) {
    return float_abs((float) f) < epsilon;
}

public int sign(int x) {
    if (x == 0)
        return 0;
    return x < 0 ? -1 : 1;
}

int stricmp(string str1, string str2) {
    string temp_str1 = str1.casefold(-1);
    string temp_str2 = str2.casefold(-1);
    
    return temp_str1.collate(temp_str2);
}

// TODO: write this using generics.  
public string[] copy_array(string[] source) {
    string[] destination = new string[source.length];
    int i = 0;
    foreach (string item in source) {
        destination[i] = item;
        ++i;
    }
    return destination;
}

// Debug utilities

public bool debug_enabled;

public void print_debug(string text) {
    if (!debug_enabled)
        return;
        
    debug("%s", text);
}

public struct Fraction {
    public int numerator;
    public int denominator;
    
    public Fraction(int numerator, int denominator) {
        this.numerator = numerator;
        this.denominator = denominator;
    }
    
    public Fraction.from_string(string s) {
        string[] elements = s.split("/");
        if (elements.length != 2) {
            numerator = 0;
            denominator = 0;
        } else {
            numerator = elements[0].to_int();
            denominator = elements[1].to_int();
        }
    }
    
    public bool equal(Fraction f) {
        if (float_abs(((numerator / (float)denominator) - (f.numerator / (float)f.denominator))) <=
            (1000.0f / 1001.0f))
            return true;
        return false;
    }
    
    public int nearest_int() {
        return (int) (((double) numerator / denominator) + 0.5);    
    }
    
    public string to_string() {
        return "%d/%d".printf(numerator, denominator);
    }
    
}

public struct TimeCode {
    public int hour;
    public int minute;
    public int second;
    public int frame;
    public bool drop_code;
    
    public void get_from_length(int64 length) {
        length /= Gst.SECOND;
        
        hour = (int) (length / 3600);
        minute = (int) ((length % 3600) / 60);
        second = (int) ((length % 3600) % 60);
        frame = 0;
    }

    public string to_string() {
        string ret = "";
        if (hour != 0)
            ret += "%.2d:".printf(hour);

        ret += "%.2d:".printf(minute);
        ret += "%.2d".printf(second);
        
        if (drop_code)
            ret += ";";
        else
            ret += ":";
        ret += "%.2d".printf(frame);
        
        return ret;        
    }
}

public bool time_in_range(int64 time, int64 center, int64 delta) {
    int64 diff = time - center;
    return diff.abs() <= delta;
}

public string isolate_filename(string path) {
    string str = Path.get_basename(path);
    return str.split(".")[0];
}

public string get_file_extension(string path) {
    unowned string dot = path.rchr(-1, '.');
    return dot == null ? "" : dot.next_char();
}

public string append_extension(string path, string extension) {
    if (get_file_extension(path) == extension)
        return path;
        
    return path + "." + extension;
}

// Given two version number strings such as "0.10.2.4", return true if the first is
// greater than or equal to the second.
public bool version_at_least(string v, string w) {
    string[] va = v.split(".");
    string[] wa = w.split(".");
    for (int i = 0 ; i < wa.length ; ++i) {
        if (i >= va.length)
            return false;
        int vi = va[i].to_int();
        int wi = wa[i].to_int();
        if (vi > wi)
            return true;
        if (wi > vi)
            return false;
    }
    return true;
}

public bool get_file_md5_checksum(string filename, out string checksum) {
    string new_filename = append_extension(filename, "md5");
    
    size_t buffer_length;
    try {
        GLib.FileUtils.get_contents(new_filename, out checksum, out buffer_length);
    } catch (GLib.FileError e) {
        return false;
    }
    
    return buffer_length == 32;
}

public void save_file_md5_checksum(string filename, string checksum) {
    string new_filename = append_extension(filename, "md5");
    
    try {
        GLib.FileUtils.set_contents(new_filename, checksum);
    } catch (GLib.FileError e) {
        error("Cannot save md5 file %s!\n", new_filename);
    }
}

public bool md5_checksum_on_file(string filename, out string checksum) {
    string file_buffer;
    size_t len;
    
    try {
        GLib.FileUtils.get_contents(filename, out file_buffer, out len);
    } catch (GLib.FileError e) {
        return false;
    }

    GLib.Checksum c = new GLib.Checksum(GLib.ChecksumType.MD5);
    c.update((uchar[]) file_buffer, len);
    checksum = c.get_string();
    return true;
}

// GTK utility functions

// constants from gdkkeysyms.h https://bugzilla.gnome.org/show_bug.cgi?id=551184
public enum KeySyms {
    LEFT = 0xff51,
    UP = 0xff52,
    RIGHT = 0xff53,
    DOWN = 0xff54,
    MINUS = 0x002d,
    PLUS = 0x003d,
    SHIFT_LEFT = 0xffe1,
    SHIFT_RIGHT = 0xffe2,
    ESCAPE = 0xff1b,
    CONTROL_LEFT = 0xffe3,
    CONTROL_RIGHT = 0xffe4
}


public const Gtk.TargetEntry[] drag_target_entries = {
    { "text/uri-list", 0, 0 } 
};

public Gtk.Alignment get_aligned_label(float x, float y, float exp_x, float exp_y, string text) {
    Gtk.Label l = new Gtk.Label(text);
    l.set_line_wrap(true);
    l.use_markup = true;
    
    Gtk.Alignment a = new Gtk.Alignment(x, y, exp_x, exp_y);
    a.add(l);
    
    return a;
}

public void add_label_to_table(Gtk.Table t, string str, int x, int y, int xpad, int ypad) {
    Gtk.Alignment a = get_aligned_label(0.0f, 0.0f, 0.0f, 0.0f, str);
    t.attach(a, x, x + 1, y, y + 1, Gtk.AttachOptions.FILL, Gtk.AttachOptions.FILL, xpad, ypad);
}

public Gdk.Color parse_color(string color) {
    Gdk.Color c;
    if (!Gdk.Color.parse(color, out c))
        error("can't parse color");
    return c;
}

public Gtk.Widget get_widget(Gtk.UIManager manager, string name) {
    Gtk.Widget widget = manager.get_widget(name);
    if (widget == null)
        error("can't find widget");
    return widget;
}

/////////////////////////////////////////////////////////////////////////////
//                    Rectangle drawing stuff                              //
// Original rounded rectangle code from: http://cairographics.org/samples/ //
/////////////////////////////////////////////////////////////////////////////

const double LINE_WIDTH = 1.0;
const double RADIUS = 15.0;
const Cairo.Antialias ANTIALIAS = Cairo.Antialias.DEFAULT; // NONE/DEFAULT

public void draw_rounded_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
                            int x0, int y0, int width, int height) {
    if (width == 0 || height == 0)
        return;

    double x1 = x0 + width;
    double y1 = y0 + height;
    
    Cairo.Context cairo_window = Gdk.cairo_create(window);
    Gdk.cairo_set_source_color(cairo_window, color);
    cairo_window.set_antialias(ANTIALIAS);
        
    if ((width / 2) < RADIUS) {
        if ((height / 2) < RADIUS) {
            cairo_window.move_to(x0, ((y0 + y1) / 2));
            cairo_window.curve_to(x0, y0, x0, y0, (x0 + x1) / 2, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, (y0 + y1) / 2);
            cairo_window.curve_to(x1, y1, x1, y1, (x1 + x0) / 2, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, (y0 + y1) / 2);
        } else {
            cairo_window.move_to(x0, y0 + RADIUS);
            cairo_window.curve_to(x0,y0, x0, y0, (x0 + x1) / 2, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, y0 + RADIUS);
            cairo_window.line_to(x1, y1 - RADIUS);
            cairo_window.curve_to(x1, y1, x1, y1, (x1 + x0) / 2, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, y1 - RADIUS);
        }
    } else {
        if ((height / 2) < RADIUS) {
            cairo_window.move_to(x0, (y0 + y1) / 2);
            cairo_window.curve_to(x0, y0, x0, y0, x0 + RADIUS, y0);
            cairo_window.line_to(x1 - RADIUS, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, (y0 + y1) / 2);
            cairo_window.curve_to(x1, y1, x1, y1, x1 - RADIUS, y1);
            cairo_window.line_to(x0 + RADIUS, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, (y0 + y1) / 2);
        } else {
            cairo_window.move_to(x0, y0 + RADIUS);
            cairo_window.curve_to(x0, y0, x0, y0, x0 + RADIUS, y0);
            cairo_window.line_to(x1 - RADIUS, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, y0 + RADIUS);
            cairo_window.line_to(x1, y1 - RADIUS);
            cairo_window.curve_to(x1, y1, x1, y1, x1 - RADIUS, y1);
            cairo_window.line_to(x0 + RADIUS, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, y1 - RADIUS);
        }
    }
    cairo_window.close_path();

    if (filled) {
        cairo_window.fill();
    } else {
        cairo_window.set_line_width(LINE_WIDTH);
        cairo_window.stroke();
    }
}

public void draw_right_rounded_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
                                  int x0, int y0, int width, int height) {
    if (width == 0 || height == 0)
        return;

    double x1 = x0 + width;
    double y1 = y0 + height;
    
    Cairo.Context cairo_window = Gdk.cairo_create(window);
    Gdk.cairo_set_source_color(cairo_window, color);
    cairo_window.set_antialias(ANTIALIAS);

    if ((width / 2) < RADIUS) {
        if ((height / 2) < RADIUS) {
            cairo_window.move_to(x0, y0);
            cairo_window.line_to((x0 + x1) / 2, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, (y0 + y1) / 2);
            cairo_window.curve_to(x1, y1, x1, y1, (x1 + x0) / 2, y1);
            cairo_window.line_to(x0, y1);
            cairo_window.line_to(x0, y0);
        } else {
            cairo_window.move_to(x0, y0);
            cairo_window.line_to((x0 + x1) / 2, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, y0 + RADIUS);
            cairo_window.line_to(x1, y1 - RADIUS);
            cairo_window.curve_to(x1, y1, x1, y1, (x1 + x0) / 2, y1);
            cairo_window.line_to(x0, y1);
            cairo_window.line_to(x0, y0);
        }
    } else {
        if ((height / 2) < RADIUS) {
            cairo_window.move_to(x0, y0);
            cairo_window.line_to(x1 - RADIUS, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, (y0 + y1) / 2);
            cairo_window.curve_to(x1, y1, x1, y1, x1 - RADIUS, y1);
            cairo_window.line_to(x0, y1);
            cairo_window.line_to(x0, y0);
        } else {
            cairo_window.move_to(x0, y0);
            cairo_window.line_to(x1 - RADIUS, y0);
            cairo_window.curve_to(x1, y0, x1, y0, x1, y0 + RADIUS);
            cairo_window.line_to(x1, y1 - RADIUS);
            cairo_window.curve_to(x1, y1, x1, y1, x1 - RADIUS, y1);
            cairo_window.line_to(x0, y1);
            cairo_window.line_to(x0, y0);
        }
    }
    cairo_window.close_path();

    if (filled) {
        cairo_window.fill();
    } else {
        cairo_window.set_line_width(LINE_WIDTH);
        cairo_window.stroke();
    }
}

public void draw_left_rounded_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
                                 int x0, int y0, int width, int height) {
    if (width == 0 || height == 0)
        return;

    double x1 = x0 + width;
    double y1 = y0 + height;

    Cairo.Context cairo_window = Gdk.cairo_create(window);
    Gdk.cairo_set_source_color(cairo_window, color);
    cairo_window.set_antialias(ANTIALIAS);

    if ((width / 2) < RADIUS) {
        if ((height / 2) < RADIUS) {
            cairo_window.move_to(x0, ((y0 + y1) / 2));
            cairo_window.curve_to(x0, y0, x0, y0, (x0 + x1) / 2, y0);
            cairo_window.line_to(x1, y0);
            cairo_window.line_to(x1, y1);
            cairo_window.line_to((x1 + x0) / 2, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, (y0 + y1) / 2);
        } else {
            cairo_window.move_to(x0, y0 + RADIUS);
            cairo_window.curve_to(x0,y0, x0, y0, (x0 + x1) / 2, y0);
            cairo_window.line_to(x1, y0);
            cairo_window.line_to(x1, y1);
            cairo_window.line_to((x1 + x0) / 2, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, y1 - RADIUS);
        }
    } else {
        if ((height / 2) < RADIUS) {
            cairo_window.move_to(x0, (y0 + y1) / 2);
            cairo_window.curve_to(x0, y0, x0, y0, x0 + RADIUS, y0);
            cairo_window.line_to(x1, y0);
            cairo_window.line_to(x1, y1);
            cairo_window.line_to(x0 + RADIUS, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, (y0 + y1) / 2);
        } else {
            cairo_window.move_to(x0, y0 + RADIUS);
            cairo_window.curve_to(x0, y0, x0, y0, x0 + RADIUS, y0);
            cairo_window.line_to(x1, y0);
            cairo_window.line_to(x1, y1);
            cairo_window.line_to(x0 + RADIUS, y1);
            cairo_window.curve_to(x0, y1, x0, y1, x0, y1 - RADIUS);
        }
    }
    cairo_window.close_path();

    if (filled) {
        cairo_window.fill();
    } else {
        cairo_window.set_line_width(LINE_WIDTH);
        cairo_window.stroke();
    }
}

public void draw_square_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
                           int x, int y, int width, int height) {
    if (width == 0 || height == 0)
        return;

    Cairo.Context cairo_window = Gdk.cairo_create(window);
    Gdk.cairo_set_source_color(cairo_window, color);
    cairo_window.set_antialias(ANTIALIAS);

    cairo_window.rectangle(x, y, width, height);

    if (filled) {
        cairo_window.fill();
    } else {
        cairo_window.set_line_width(LINE_WIDTH);
        cairo_window.stroke();
    }
}

// GStreamer utility functions

public bool is_drop_frame_rate(Fraction r) {
    return r.numerator == 2997 && r.denominator == 100 ||
           r.numerator == 30000 && r.denominator == 1001;    
}

public int64 frame_to_time_with_rate(int frame, Fraction rate) {
    int64 time = (int64) Gst.util_uint64_scale(frame, Gst.SECOND * rate.denominator, rate.numerator);
    return time;
}

public int time_to_frame_with_rate(int64 time, Fraction rate) {
    int frame = (int) Gst.util_uint64_scale(time, rate.numerator, Gst.SECOND * rate.denominator);
        
    /* We need frame_to_time_with_rate and time_to_frame_with_rate to be inverse functions, so that
     * time_to_frame(frame_to_time_with_rate(f)) = f for all f.  With the simple calculation
     * above the functions might not be inverses due to rounding error, so we
     * need the following check. */
    return time >= frame_to_time_with_rate(frame + 1, rate) ? frame + 1 : frame;
}

public TimeCode frame_to_time(int frame, Fraction rate) {
    int frame_rate = 0;
   
    TimeCode t = {};
    
    t.drop_code = false;   
    if (rate.denominator == 1)
        frame_rate = rate.numerator;
    else if (is_drop_frame_rate(rate)) {
        t.drop_code = true;
        frame_rate = 30;

        // We can't declare these as const int due to a Vala compiler bug.
        int FRAMES_PER_MINUTE = 30 * 60 - 2;
        int FRAMES_PER_10_MINUTES = 10 * FRAMES_PER_MINUTE + 2;
       
        int block = frame / FRAMES_PER_10_MINUTES;  // number of 10-minute blocks elapsed
        int minute_in_block = (frame % FRAMES_PER_10_MINUTES - 2) / FRAMES_PER_MINUTE;
        int minutes = 10 * block + minute_in_block;
        frame += 2 * minutes - 2 * block;   // skip 2 frames per minute, except every 10 minutes
    } else {
        // TODO: We're getting odd framerate fractions from imported videos, so
        // I've removed the error call until we decide what to do
        frame_rate = rate.numerator / rate.denominator;
    }
    
    t.frame = frame % frame_rate;
    
    int64 secs = frame / frame_rate;
    t.hour = (int) secs / 3600;
    t.minute = ((int) secs % 3600) / 60;   
    t.second = ((int) secs % 3600) % 60;
    
    return t;
}

public string frame_to_string(int frame, Fraction rate) {    
    return frame_to_time(frame, rate).to_string();
}

void breakup_time(int64 time, out int hours, out int minutes, out double seconds) {
    int64 the_time = time;
    int64 minute = Gst.SECOND * 60;
    int64 hour = minute * 60;
    hours = (int) (the_time / hour);
    the_time = the_time % hour;
    minutes = (int) (the_time / minute);
    the_time = the_time % minute;
    seconds = (double) the_time / Gst.SECOND;
}

public string time_to_HHMMSS(int64 time) {
    int hours;
    int minutes;
    double seconds;

    breakup_time(time, out hours, out minutes, out seconds);
    return "%02d:%02d:%05.2lf".printf(hours, minutes, seconds);
}

public string time_to_string(int64 time) {
    int hours;
    int minutes;
    double seconds;

    breakup_time(time, out hours, out minutes, out seconds);
    string return_value = "%1.2lfs".printf(seconds);
    if (hours > 0 || minutes > 0) {
        return_value = "%dm ".printf(minutes) + return_value;
    }
    
    if (hours > 0) {
        return_value = "%dh ".printf(hours) + return_value;
    }
    
    return return_value;
}

public static Gst.Element make_element_with_name(string element_name, string? display_name) 
        throws GLib.Error {
    Gst.Element e = Gst.ElementFactory.make(element_name, display_name);
    if (e == null) {
        throw new
            MediaError.MISSING_PLUGIN("Could not create element %s(%s)".printf(element_name, display_name));
    }
    return e;
}

public static Gst.Element make_element(string name) throws Error {
    return make_element_with_name(name, null);
}

