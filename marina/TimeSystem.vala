/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {

public interface TimeSystem : Object {
    public abstract void calculate_pixel_step(float inc, float pixel_min, float pixel_div);
    public abstract int64 xpos_to_time(int x);
    public abstract int64 xsize_to_time(int x);
    public abstract int time_to_xpos(int64 time);
    public abstract int64 get_pixel_snap_time();
    public abstract int time_to_xsize(int64 time);    
    public abstract float get_pixel_percentage();
    public abstract int get_start_token();
    public abstract int get_next_position(int token);
    public abstract int get_pixel_height(int token);
    public abstract string? get_display_string(int token);    
    public abstract int frame_to_xsize(int frame);
    public abstract string get_time_string(int64 time);
}

public abstract class TimeSystemBase : Object {
    public const int PIXEL_SNAP_INTERVAL = 10;
    protected int[] timeline_seconds = { 1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600, 
        900, 1200, 1800, 3600 };

    public float pixel_percentage = 0.0f;
    public float pixels_per_second;
    public int64 pixel_snap_time;
    
    const int BORDER = 4;  // TODO: should use same value as timeline.  will happen when this gets
                            // refactored back into view code.

    protected int correct_seconds_value (float seconds, int div, int fps) {
        if (seconds < 1.0f) {
            int frames = (int)(fps * seconds);
            if (frames == 0)
                return 1;
                
            if (div == 0)
                div = fps;
                
            int mod = div % frames;
            while (mod != 0) {
                mod = div % (++frames);
            }
            return frames;
        }
        
        int i;
        int secs = (int) seconds;
        for (i = timeline_seconds.length - 1; i > 0; i--) {
            if (secs <= timeline_seconds[i] &&
                secs >= timeline_seconds[i - 1]) {
                if ((div % (timeline_seconds[i] * fps)) == 0)
                    break;
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

    public int time_to_xsize(int64 time) {
        return (int) (time * pixels_per_second / Gst.SECOND);
    }

    public int time_to_xpos(int64 time) {
        int pos = time_to_xsize(time) + BORDER;
        
        if (xpos_to_time(pos) != time)
            pos++;
        return pos;
    }
}

public class TimecodeTimeSystem : TimeSystem, TimeSystemBase {
    float pixels_per_frame;

    int small_pixel_frames = 0;
    int medium_pixel_frames = 0;
    int large_pixel_frames = 0;

    public Fraction frame_rate_fraction = Fraction(30000, 1001);

    public string get_time_string(int64 the_time) {
        string time;
        
        int frame = time_to_frame_with_rate(the_time, frame_rate_fraction);
        time = frame_to_string(frame, frame_rate_fraction);
        
        return time;
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
        large_pixel_frames = correct_seconds_value(pixels_per_large / pixels_per_second, 0, fps);
        medium_pixel_frames = correct_seconds_value(pixels_per_medium / pixels_per_second, 
                                                    large_pixel_frames, fps);
        small_pixel_frames = correct_seconds_value(pixels_per_small / pixels_per_second, 
                                                    medium_pixel_frames, fps);
    
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

    public int get_start_token() {
        return 0;
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
}
}
