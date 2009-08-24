/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */


namespace Model {
public class VideoTrack : Track {
    
    public VideoTrack(Model.Project project) {
        base(project, "Video Track");
    }

    protected override string name() { return "video"; }

    protected override Gst.Element empty_element() {
        Gst.Element blackness = make_element("videotestsrc");
        blackness.set("pattern", 2);     // 2 == GST_VIDEO_TEST_SRC_BLACK
        return blackness;
    }

    protected override void check(Clip clip) {
        Fraction rate1;
        Fraction rate2;
        
        if (!get_framerate(out rate2))
            error ("Cannot get initial frame rate!");
        
        if (!clip.clipfile.get_frame_rate(out rate1))
            error("can't get frame rate");
        
        if (!rate1.equal(rate2))
            error ("can't insert clip with different frame rate");
    }
    
    /* It would be nice if we could query or seek in frames using GST_FORMAT_DEFAULT, or ask
     * GStreamer to convert frame->time and time->frame for us using gst_element_query_convert().
     * Unfortunately there are several reasons we can't.
     * 1) It appears that position queries using GST_FORMAT_DEFAULT are broken since GstBaseSink
     *    won't pass them upstream.
     * 2) Some codecs (e.g. theoradec) will convert between time and frames, but
     *    others (e.g. ffmpegdec, dvdec) haven't implemented this conversion.
     * 3) Even when a codec will perform conversions, its frame->time and time->frame functions may
     *    not be perfect inverses; see the comments in time_to_frame(), below.
     *
     * So instead we must convert manually using the frame rate.
     *
     * TODO:   We should file GStreamer bugs for all of these.
     */
    
    int64 frame_to_time(int frame) {
        Fraction rate;
        if (!get_framerate(out rate))
            return 0;

        return (int64) Gst.util_uint64_scale(frame, Gst.SECOND * rate.denominator, rate.numerator);
    }
    
    int time_to_frame(int64 time) {
        Fraction rate;
        if (!get_framerate(out rate))
            return 0;
        return time_to_frame_with_rate(time, rate);
    }
    
    public int get_current_frame(int64 time) {
        return time_to_frame(time);
    }
    
    public int64 previous_frame(int64 position) {
        int frame = time_to_frame(position);
        return frame_to_time(frame - 1);
    }
    
    public int64 next_frame(int64 position) {
        int frame = time_to_frame(position);
        return frame_to_time(frame + 1);
    }

    public bool get_framerate(out Fraction rate) {
        if (clips.size == 0) {
            rate.numerator = 2997;
            rate.denominator = 100;
            return true;
        }
        return clips[0].clipfile.get_frame_rate(out rate);
    }

}
    
}

