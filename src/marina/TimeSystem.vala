/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
using Logging;

public interface TimeSystem : Object {
    public signal void geometry_changed();
    public abstract void calculate_pixel_step(float inc, float pixel_min, float pixel_div);
    public abstract int64 xpos_to_time(int x);
    public abstract int64 xsize_to_time(int x);
    public abstract int time_to_xpos(int64 time);
    public abstract int64 get_pixel_snap_time();
    public abstract int time_to_xsize(int64 time);
    public abstract float get_pixel_percentage();
    public abstract int get_start_token(int xsize);
    public abstract int get_next_position(int token);
    public abstract int get_pixel_height(int token);
    public abstract string? get_display_string(int token);
    public abstract int frame_to_xsize(int frame);
    public abstract int xsize_to_frame(int xsize);
    public abstract string get_time_string(int64 time);
    public abstract string get_time_duration(int64 time);
    public abstract int64 next_tick(int64 time);
    public abstract int64 previous_tick(int64 time);
}

public abstract class TimeSystemBase : Object {
    public const int PIXEL_SNAP_INTERVAL = 10;

    public float pixel_percentage = 0.0f;
    public float pixels_per_second;
    public int64 pixel_snap_time;

    const int BORDER = 4;  // TODO: should use same value as timeline.  will happen when this gets
                           // refactored back into view code.

    protected abstract int[] get_timeline_seconds();
    protected abstract int correct_sub_second_value(float seconds, int div, int fps);

    protected int correct_seconds_value (float seconds, int div, int fps) {
        if (seconds < 1) {
            return correct_sub_second_value(seconds, div, fps);
        }

        int i;
        int secs = (int) seconds;
        int [] timeline_seconds = get_timeline_seconds();
        for (i = timeline_seconds.length - 1; i > 0; i--) {
            if (secs <= timeline_seconds[i] &&
                secs >= timeline_seconds[i - 1]) {
                if ((div % (timeline_seconds[i] * fps)) == 0) {
                    break;
                }
                if ((div % (timeline_seconds[i - 1] * fps)) == 0) {
                    i--;
                    break;
                }
            }
        }
        return timeline_seconds[i] * fps;
    }

    public int64 get_pixel_snap_time() {
        return pixel_snap_time;
    }

    public float get_pixel_percentage() {
        return pixel_percentage;
    }

    public int64 xpos_to_time(int x) {
        return xsize_to_time(x - BORDER);
    }

    public int64 xsize_to_time(int size) {
        return (int64) ((float)(size * Gst.SECOND) / pixels_per_second);
    }

    public int64 xsize_to_time_double(double size) {
        return (int64)((size * Gst.SECOND) / pixels_per_second);
    }

    public int time_to_xsize(int64 time) {
        return (int) (time * pixels_per_second / Gst.SECOND);
    }

    public int time_to_xpos(int64 time) {
        int pos = time_to_xsize(time) + BORDER;
        
        if (xpos_to_time(pos) != time)
            pos++;
        return pos;
    }

    public int64 tick_increment(int64 the_time, int64 boundary, int increment) {
        int64 result = ((the_time / boundary) + increment) * boundary;
        return result < 0 ? 0 : result;
    }
}

public class TimecodeTimeSystem : TimeSystem, TimeSystemBase {
    float pixels_per_frame;

    int small_pixel_frames = 0;
    int medium_pixel_frames = 0;
    int large_pixel_frames = 0;

    public Fraction frame_rate_fraction = Fraction(30000, 1001);

    protected override int correct_sub_second_value(float seconds, int div, int fps) {
        int frames = (int)(fps * seconds);
        if (frames == 0) {
            return 1;
        }

        if (div == 0) {
            div = fps;
        }

        int mod = div % frames;
        while (mod != 0) {
            mod = div % (++frames);
        }
        return frames;
    }

    public string get_time_string(int64 the_time) {
        string time;

        int frame = time_to_frame_with_rate(the_time, frame_rate_fraction);
        time = frame_to_string(frame, frame_rate_fraction);

        return time;
    }

    public string get_time_duration(int64 the_time) {
        // Timecode is already zero-based
        return get_time_string(the_time);
    }

    public int64 next_tick(int64 the_time) {
        return tick_increment(the_time, 
            xsize_to_time_double(large_pixel_frames * pixels_per_frame), 1);
    }

    public int64 previous_tick(int64 the_time) {
        return tick_increment(the_time, 
            xsize_to_time_double(large_pixel_frames * pixels_per_frame), -1);
    }

    public void calculate_pixel_step(float inc, float pixel_min, float pixel_div) {
        int pixels_per_large = 300;
        int pixels_per_medium = 50;
        int pixels_per_small = 20;

        pixel_percentage += inc;
        if (pixel_percentage < 0.0f)
            pixel_percentage = 0.0f;
        else if (pixel_percentage > 1.0f)
            pixel_percentage = 1.0f;

        pixels_per_second = pixel_min * GLib.Math.powf(pixel_div, pixel_percentage);
        int fps = frame_rate_fraction.nearest_int();
        float seconds = pixels_per_large / pixels_per_second;
        large_pixel_frames = correct_seconds_value(seconds, 0, fps);
        seconds = pixels_per_medium / pixels_per_second;
        medium_pixel_frames = correct_seconds_value(seconds, large_pixel_frames, fps);
        seconds = pixels_per_small / pixels_per_second;
        small_pixel_frames = correct_seconds_value(seconds, medium_pixel_frames, fps);

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

    public int frame_to_xsize(int frame) {
        return ((int) (frame * pixels_per_frame));
    }

    public int xsize_to_frame(int xsize) {
        return (int) (xsize / pixels_per_frame);
    }

    public int get_start_token(int xsize) {
        int start_frame = xsize_to_frame(xsize);
        return large_pixel_frames * (start_frame / large_pixel_frames);
    }

    public int get_next_position(int token) {
        return token + small_pixel_frames;
    }

    public string? get_display_string(int frame) {
        if ((frame % large_pixel_frames) == 0) {
            return frame_to_time(frame, frame_rate_fraction).to_string();
        }
        return null;
    }

    public int get_pixel_height(int frame) {
        if ((frame % medium_pixel_frames) == 0) {
            if (medium_pixel_frames == small_pixel_frames &&
                    (medium_pixel_frames != large_pixel_frames &&
                    frame % large_pixel_frames != 0)) {
                return 2;
            }
            else {
                return 6;
            }
        } else {
            return 2;
        }
    }

    protected override int[] get_timeline_seconds() {
        return { 1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1200, 1800, 3600 };
    }
}

public interface TempoInformation {
    public abstract Fraction get_time_signature();
    public abstract int get_bpm();
    public signal void time_signature_changed(Fraction time_signature);
    public signal void bpm_changed(int bpm);
}

public class BarBeatTimeSystem : TimeSystem, TimeSystemBase {
    float pixels_per_sixteenth;

    int small_pixel_sixteenth = 0;
    int medium_pixel_sixteenth = 0;
    int large_pixel_sixteenth = 0;
    int[] timeline_bars = { 
            1, 2, 4, 8, 16, 24, 32, 64, 128, 256, 512, 768, 1024, 2048, 3192 
        };

    int bpm;
    Fraction time_signature;
    float bars_per_minute;
    float bars_per_second;
    int sixteenths_per_bar;
    int sixteenths_per_beat;

    public BarBeatTimeSystem(TempoInformation tempo_information) {
        bpm = tempo_information.get_bpm();
        time_signature = tempo_information.get_time_signature();
        tempo_information.bpm_changed.connect(on_bpm_changed);
        tempo_information.time_signature_changed.connect(on_time_signature_changed);
        set_constants();
    }

    void on_time_signature_changed(Fraction time_signature) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_time_signature_changed");
        this.time_signature = time_signature;
        set_constants();
    }

    void on_bpm_changed(int bpm) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_bpm_changed");
        this.bpm = bpm;
        set_constants();
    }

    void set_constants() {
        bars_per_minute = bpm / (float)time_signature.numerator;
        bars_per_second = bars_per_minute / 60.0f;

        sixteenths_per_beat = 16 / time_signature.denominator;
        sixteenths_per_bar = time_signature.numerator * sixteenths_per_beat;
        geometry_changed();
    }

    protected override int correct_sub_second_value(float bars, int div, int unused) {
        int sixteenths = (int)(sixteenths_per_bar * bars);

        if (sixteenths == 0) {
            return 1;
        }

        int current_try = sixteenths_per_bar / 2;
        do {
            if (current_try < sixteenths) {
                return current_try;
            }
            current_try = current_try / 2;
        } while (current_try > 1);
        return 1;
    }

   string beats_to_string(int total_sixteenths, bool maximum_resolution, bool zero_based) {
        int number_of_measures = 
            (total_sixteenths / sixteenths_per_beat) / time_signature.numerator;

        int number_of_beats = 
            (total_sixteenths / sixteenths_per_beat) % time_signature.numerator;
        int number_of_sixteenths = total_sixteenths % sixteenths_per_beat;
        if (!zero_based) {
            ++number_of_measures;
            ++number_of_beats;
            ++number_of_sixteenths;
        }
        float pixels_per_bar = pixels_per_second / bars_per_second;
        float pixels_per_large_gap = large_pixel_sixteenth * pixels_per_sixteenth;
        if (maximum_resolution ||
            ((pixels_per_large_gap < pixels_per_sixteenth * sixteenths_per_beat) &&
            number_of_sixteenths > 1)) {
            return "%d.%d.%d".printf(number_of_measures, number_of_beats, number_of_sixteenths);
        } else if (pixels_per_large_gap < pixels_per_bar && number_of_beats > 1) {
            return "%d.%d".printf(number_of_measures, number_of_beats);
        } else {
            return "%d".printf(number_of_measures);
        }
    }

    public string get_time_string(int64 the_time) {
        double beats_per_second = bpm / 60.0;
        double sixteenths_per_second = sixteenths_per_beat * beats_per_second;
        double sixteenths_per_nanosecond = sixteenths_per_second / Gst.SECOND;
        int total_beats = (int)(the_time * sixteenths_per_nanosecond);
        return beats_to_string(total_beats, true, false);
    }

    public string get_time_duration(int64 the_time) {
        double beats_per_second = bpm / 60.0;
        double sixteenths_per_second = sixteenths_per_beat * beats_per_second;
        double sixteenths_per_nanosecond = sixteenths_per_second / Gst.SECOND;
        int total_beats = (int)(the_time * sixteenths_per_nanosecond);
        if (total_beats == 0 && the_time > 0) {
            // round up
            total_beats = 1;
        }
        return beats_to_string(total_beats, true, true);
    }

    public int64 next_tick(int64 the_time) {
        return tick_increment(the_time, 
            xsize_to_time_double(large_pixel_sixteenth * pixels_per_sixteenth), 1);
    }

    public int64 previous_tick(int64 the_time) {
        return tick_increment(the_time,
            xsize_to_time_double(large_pixel_sixteenth * pixels_per_sixteenth), -1);
    }

    void constrain_seconds_value(out int pixel_sixteenth, int pixels_per, int min_pixels, 
        int max_pixels, float pixels_per_bar) {
        float pixels_per_size = 0;
        int count = 0;
        do {
            pixel_sixteenth = correct_seconds_value(
                pixels_per / pixels_per_bar, 0, sixteenths_per_bar);
            pixels_per_size = pixel_sixteenth * pixels_per_sixteenth;
            if (pixels_per_size < min_pixels) {
                pixels_per = (int) (pixels_per * 1.05);
            } else if (pixels_per_size > max_pixels) {
                pixels_per = (int) (pixels_per * 0.95);
            } else {
                break;
            }
            ++count;
        } while (count < 0);
    }

    public void calculate_pixel_step(float inc, float pixel_min, float pixel_div) {
        int pixels_per_large = 120;
        int min_pixels_per_large = 80;
        int max_pixels_per_large = 160;

        int pixels_per_medium = 60;
        int min_pixels_per_medium = 30;
        int max_pixels_per_medium = 80;

        int pixels_per_small = 15;
        int min_pixels_per_small = 10;
        int max_pixels_per_small = 20;

        pixel_percentage += inc;
        if (pixel_percentage < 0.0f) {
            pixel_percentage = 0.0f;
        } else if (pixel_percentage > 1.0f) {
            pixel_percentage = 1.0f;
        }

        pixels_per_second = pixel_min * GLib.Math.powf(pixel_div, pixel_percentage);
        float pixels_per_bar = pixels_per_second / bars_per_second;
        pixels_per_sixteenth = pixels_per_bar / (float) sixteenths_per_bar;

        constrain_seconds_value(out large_pixel_sixteenth, pixels_per_large, 
            min_pixels_per_large, max_pixels_per_large, pixels_per_bar);
        constrain_seconds_value(out medium_pixel_sixteenth, pixels_per_medium,
            min_pixels_per_medium, max_pixels_per_medium, pixels_per_bar);
        constrain_seconds_value(out small_pixel_sixteenth, pixels_per_small,
            min_pixels_per_small, max_pixels_per_small, pixels_per_bar);
        if (small_pixel_sixteenth * pixels_per_sixteenth < min_pixels_per_small) {
            small_pixel_sixteenth = medium_pixel_sixteenth;
        }
        pixel_snap_time = xsize_to_time(PIXEL_SNAP_INTERVAL);
    }

    public int frame_to_xsize(int frame) {
        return ((int) (frame * pixels_per_sixteenth));
    }

    public int xsize_to_frame(int xsize) {
        return (int) (xsize / pixels_per_sixteenth);
    }

    public int get_start_token(int xsize) {
        int start_frame = xsize_to_frame(xsize);
        return large_pixel_sixteenth * (start_frame / large_pixel_sixteenth);
    }

    public int get_next_position(int token) {
        return token + small_pixel_sixteenth;
    }

    public string? get_display_string(int frame) {
        if ((frame % large_pixel_sixteenth) == 0) {
            return beats_to_string(frame, false, false);
        }
        return null;
    }

    public int get_pixel_height(int frame) {
        if ((frame % medium_pixel_sixteenth) == 0) {
            if (medium_pixel_sixteenth == small_pixel_sixteenth &&
                    (medium_pixel_sixteenth != large_pixel_sixteenth &&
                    frame % large_pixel_sixteenth != 0)) {
                return 2;
            }
            else {
                return 6;
            }
        } else {
            return 2;
        }
    }

    protected override int[] get_timeline_seconds() {
        return timeline_bars;
    }
}
}
