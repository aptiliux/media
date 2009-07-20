/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

struct Fraction {
    public int numerator;
    public int denominator;
    
    public Fraction(int numerator, int denominator) {
        this.numerator = numerator;
        this.denominator = denominator;
    }
    
    public bool equal(Fraction f) {
        return numerator == f.numerator && denominator == f.denominator;
    }
}

struct Time {
    public int hour;
    public int minute;
    public int second;
    public int frame;
    public bool drop_code;
    
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

bool time_in_range(int64 time, int64 center, int64 delta) {
    int64 diff = time - center;
    return diff.abs() <= delta;
}

int sign(int x) {
    if (x == 0)
        return 0;
    return x < 0 ? -1 : 1;
}

string isolate_filename(string path) {
    string str = Path.get_basename(path);
    return str.split(".")[0];
}

string get_file_extension(string path) {
    unowned string dot = path.rchr(-1, '.');
    return dot == null ? "" : dot.next_char();
}

string append_extension(string path, string extension) {
    if (get_file_extension(path) == extension)
        return path;
        
    return path + "." + extension;
}

// Given two version number strings such as "0.10.2.4", return true if the first is
// greater than or equal to the second.
bool version_at_least(string v, string w) {
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

// GTK utility functions

Gtk.Alignment get_aligned_label(float x, float y, float exp_x, float exp_y, string text) {
    Gtk.Label l = new Gtk.Label(text);
    l.set_line_wrap(true);
    l.use_markup = true;
    
    Gtk.Alignment a = new Gtk.Alignment(x, y, exp_x, exp_y);
    a.add(l);
    
    return a;
}

void add_label_to_table(Gtk.Table t, string str, int x, int y, int xpad, int ypad) {
    Gtk.Alignment a = get_aligned_label(0.0f, 0.0f, 0.0f, 0.0f, str);
    t.attach(a, x, x + 1, y, y + 1, Gtk.AttachOptions.FILL, Gtk.AttachOptions.FILL, xpad, ypad);
}

Gdk.Color parse_color(string color) {
    Gdk.Color c;
    if (!Gdk.Color.parse(color, out c))
        error("can't parse color");
    return c;
}

Gtk.Widget get_widget(Gtk.UIManager manager, string name) {
    Gtk.Widget widget = manager.get_widget(name);
    if (widget == null)
        error("can't find widget");
    return widget;
}

Gtk.Dialog create_error_dialog(string title, string message) {
    Gtk.MessageDialog d = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR,
                                                Gtk.ButtonsType.OK, message, null);
    d.set_title(title);
    
    return d;
}

Gtk.ResponseType create_delete_cancel_dialog(string title, string message) {
    Gtk.MessageDialog d = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, 
                                    Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, message, 
                                    null);
    d.set_title(title);                                                 
    
    d.add_buttons(Gtk.STOCK_DELETE, Gtk.ResponseType.YES, Gtk.STOCK_CANCEL, Gtk.ResponseType.NO);
    
    Gtk.ResponseType r = (Gtk.ResponseType) d.run();
    d.destroy();
    
    return r;
}

// GStreamer utility functions

int64 frame_to_time_with_rate(int frame, Fraction rate) {
    int64 time = (int64) Gst.util_uint64_scale(frame, Gst.SECOND * rate.denominator, rate.numerator);
    return time;
}

int time_to_frame_with_rate(int64 time, Fraction rate) {
    int frame = (int) Gst.util_uint64_scale(time, rate.numerator, Gst.SECOND * rate.denominator);
        
    /* We need frame_to_time_with_rate and time_to_frame_with_rate to be inverse functions, so that
     * time_to_frame(frame_to_time_with_rate(f)) = f for all f.  With the simple calculation
     * above the functions might not be inverses due to rounding error, so we
     * need the following check. */
    return time >= frame_to_time_with_rate(frame + 1, rate) ? frame + 1 : frame;
}

Time frame_to_time(int frame, Fraction rate) {
    int frame_rate = 0;
   
    Time t = {};
    
    t.drop_code = false;   
    if (rate.denominator == 1)
        frame_rate = rate.numerator;
    else if (rate.numerator == 2997 && rate.denominator == 100) {
        t.drop_code = true;
        frame_rate = 30;

        // We can't declare these as const int due to a Vala compiler bug.
        int FRAMES_PER_MINUTE = 30 * 60 - 2;
        int FRAMES_PER_10_MINUTES = 10 * FRAMES_PER_MINUTE + 2;
       
        int block = frame / FRAMES_PER_10_MINUTES;  // number of 10-minute blocks elapsed
        int minute_in_block = (frame % FRAMES_PER_10_MINUTES - 2) / FRAMES_PER_MINUTE;
        int minutes = 10 * block + minute_in_block;
        frame += 2 * minutes - 2 * block;   // skip 2 frames per minute, except every 10 minutes
    } else error("can't handle fractional frame rate");
   
    t.frame = frame % frame_rate;
    
    int64 secs = frame / frame_rate;
    t.hour = (int) secs / 3600;
    t.minute = ((int) secs % 3600) / 60;   
    t.second = ((int) secs % 3600) % 60;
    
    return t;
}

string frame_to_string(int frame, Fraction rate) {    
    return frame_to_time(frame, rate).to_string();
}

Gst.Element make_element(string name) {
    Gst.Element e = Gst.ElementFactory.make(name, null);
    if (e == null)
        error("can't create element: %s", name);
    return e;
}


/////////////////////////////////////////////////////////////////////////////
//                    Rectangle drawing stuff                              //
// Original rounded rectangle code from: http://cairographics.org/samples/ //
/////////////////////////////////////////////////////////////////////////////

const double LINE_WIDTH = 1.0;
const double RADIUS = 15.0;
const Cairo.Antialias ANTIALIAS = Cairo.Antialias.DEFAULT; // NONE/DEFAULT

void draw_rounded_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
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


void draw_right_rounded_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
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


void draw_left_rounded_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
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

void draw_square_rectangle(Gdk.Window window, Gdk.Color color, bool filled, 
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

