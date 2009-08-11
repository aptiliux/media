/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
class VideoProject : Project {
    Gst.Element video_export_sink;
    Gst.Element sink;
    Gst.Element converter;
    Gtk.Widget output_widget;

    public VideoProject(string? filename) {
        base(filename);      
        converter = make_element("ffmpegcolorspace");
        sink = make_element("xvimagesink");
        sink.set("force-aspect-ratio", true);
        
        pipeline.add_many(converter, sink);
        if (!converter.link(sink))
            error("can't link converter with video sink!");
    }
    
    public override double get_version() {
        return 0.01;
    }

    public override void on_pad_added(Track track, Gst.Bin bin, Gst.Pad pad) {
        base.on_pad_added(track, bin, pad);
        VideoTrack? video_track = track as VideoTrack;
        if (video_track != null) {
            if (pad.link(converter.get_static_pad("sink")) != Gst.PadLinkReturn.OK) {
                error("couldn't link pad to converter");
            }
        }
    }
    
    public override void on_pad_removed(Track track, Gst.Bin bin, Gst.Pad pad) {
        base.on_pad_removed(track, bin, pad);
        VideoTrack? video_track = track as VideoTrack;
        if (video_track != null) {
            pad.unlink(converter.get_static_pad("sink"));
        }
    }
    
    protected override void do_append(ClipFile clipfile, string name, int64 insert_time) {
        if (clipfile.video_caps != null) {
            Clip clip = new Clip(clipfile, MediaType.VIDEO, name, 0, 0, clipfile.length);
            Track? track = find_video_track();
            if (track != null) {
                track.append_at_time(clip, insert_time);
            }
        }
        base.do_append(clipfile, name, insert_time);
    }
    
    protected override void do_null_state_export() {
        base.do_null_state_export();

        pipeline.set_state(Gst.State.PAUSED);
    }

    protected override void link_for_export(Gst.Element mux) {
        base.link_for_export(mux);
        converter.unlink(sink);

        if (!pipeline.remove(sink))
            error("couldn't remove for video");

        video_export_sink = make_element("theoraenc");
        pipeline.add(video_export_sink);

        if (!converter.link(video_export_sink)) {
            error("could not link converter to video_export_sink");
        }
        if (!video_export_sink.link(mux)) {
            error("could not link video_export_sink to mux");
        }
    }    
    
    public override void link_for_playback(Gst.Element mux) {
        base.link_for_playback(mux);
        video_export_sink.unlink(mux);

        converter.unlink(video_export_sink);
        pipeline.remove(video_export_sink);
              
        pipeline.add(sink);
        if (!converter.link(sink)) {
            error("could not link converter to sink");
        }
    }
    
    public void set_output_widget(Gtk.Widget widget) {
        Gst.Bus bus = pipeline.get_bus();
        output_widget = widget;
        
        // We need to wait for the prepare-xwindow-id element message, which tells us when it's
        // time to set the X window ID.  We must respond to this message synchronously.
        // If we used an asynchronous signal (enabled via gst_bus_add_signal_watch) then the
        // xvimagesink would create its own output window which would flash briefly
        // onto the display.
        
        bus.enable_sync_message_emission();
        bus.sync_message["element"] += on_element_message;

        // We can now progress to the PAUSED state.
        // We can only do this if we aren't currently loading a project
        
        if (loader == null)
            pipeline.set_state(Gst.State.PAUSED);
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

    public int get_current_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            return video_track.get_current_frame(position);
        }
        return 0;
    }

    public void go_previous_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            go(video_track.previous_frame(position));
        }
    }
    
    public void go_next_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            go(video_track.next_frame(position));
        }
    }

    public bool get_framerate_fraction(out Fraction rate) {
        foreach (Track track in tracks) {
            VideoTrack video_track = track as VideoTrack;
            if (video_track.get_framerate(out rate))
                return true;
        }
        return false;
    }

    public int get_framerate() {
        Fraction r;
        if (!get_framerate_fraction(out r))
            return 0;
        
        if (is_drop_frame_rate(r))
            return 30;
        return r.numerator / r.denominator;
    }
}
}
