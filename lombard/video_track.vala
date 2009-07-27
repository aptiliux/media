/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */


namespace Model {
class VideoTrack : Track {
    
    Gtk.Widget output_widget;
    
    public VideoTrack(Model.Project project) {
        base(project);
        
        converter = make_element("ffmpegcolorspace");
        sink = make_element("xvimagesink");
        sink.set("force-aspect-ratio", true);
        
        project.pipeline.add_many(converter, sink);
        if (!converter.link(sink))
            error("can't link converter with video sink!");
    }

    protected override string name() { return "video"; }
    
    protected override Gst.Element empty_element() {
        Gst.Element blackness = make_element("videotestsrc");
        blackness.set("pattern", 2);     // 2 == GST_VIDEO_TEST_SRC_BLACK
        return blackness;
    }

    protected override void get_export_sink() {
        export_sink = make_element("theoraenc");
        project.pipeline.add(export_sink);
    }
    
    protected override void check(Clip clip) {
        if (clips.size > 0) {
            Fraction rate1;
            Fraction rate2 = Fraction(0, 0);
            if (!clip.clipfile.get_frame_rate(out rate1) || 
                !clips[0].clipfile.get_frame_rate(out rate2))
                error("can't get frame rate");
            if (!rate1.equal(rate2))
                error("can't insert clip with different frame rate");
        }
    }
    
    void on_element_message(Gst.Bus bus, Gst.Message message) {
        if (!message.structure.has_name("prepare-xwindow-id"))
            return;
        
        uint32 xid = Gdk.x11_drawable_get_xid(output_widget.window);
        Gst.XOverlay overlay = (Gst.XOverlay) sink;
        overlay.set_xwindow_id(xid);
        
        // Once we've connected our video sink to a widget, it's best to turn off GTK
        // double buffering for the widget; otherwise the video image flickers as it's resized.
        output_widget.unset_flags(Gtk.WidgetFlags.DOUBLE_BUFFERED);
    }

    public void set_output_widget(Gtk.Widget widget) {
        output_widget = widget;
        
        Gst.Bus bus = project.pipeline.get_bus();
        
        // We need to wait for the prepare-xwindow-id element message, which tells us when it's
        // time to set the X window ID.  We must respond to this message synchronously.
        // If we used an asynchronous signal (enabled via gst_bus_add_signal_watch) then the
        // xvimagesink would create its own output window which would flash briefly
        // onto the display.
        
        bus.enable_sync_message_emission();
        bus.sync_message["element"] += on_element_message;

        // We can now progress to the PAUSED state.
        // We can only do this if we aren't currently loading a project
        
        if (project.loader == null)
            project.pipeline.set_state(Gst.State.PAUSED);
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
}
    
}

