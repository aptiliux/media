/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public enum PlayState {
    STOPPED,
    PRE_PLAY, PLAYING,
    PRE_RECORD_NULL, PRE_RECORD, RECORDING, POST_RECORD,
    PRE_EXPORT, EXPORTING, CANCEL_EXPORT,
    PRE_LOAD, LOADING, 
    CLOSING, CLOSED
}

namespace View {

class MediaClip {
    public Gst.Element file_source;
    weak Model.Clip clip;
    Gst.Bin composition;
    
    public signal void clip_removed(MediaClip clip);
    
    public MediaClip(Gst.Bin composition, Model.Clip clip) {
        this.clip = clip;
        this.composition = composition;
        file_source = make_element("gnlsource");
        if (!clip.is_recording) {
            clip.duration_changed += on_duration_changed;
            clip.media_start_changed += on_media_start_changed;
            clip.start_changed += on_start_changed;

            composition.add(file_source);
        
            on_start_changed(clip.start);
            on_media_start_changed(clip.media_start);
            on_duration_changed(clip.duration);
        }
        clip.removed += on_clip_removed;
    }
    
    ~MediaClip() {
        clip.removed -= on_clip_removed;
        if (!clip.is_recording) {
            clip.duration_changed -= on_duration_changed;
            clip.media_start_changed -= on_media_start_changed;
            clip.start_changed -= on_start_changed;
        }
        file_source.set_state(Gst.State.NULL);
    }

    void on_clip_removed() {
        composition.remove((Gst.Bin)file_source);
        clip_removed(this);
    }
    
    void on_media_start_changed(int64 media_start) {
        file_source.set("media-start", media_start);
    }
    
    void on_duration_changed(int64 duration) {
        file_source.set("duration", duration);
        // TODO: is media-duration necessary?
        file_source.set("media-duration", duration);
    }
    
    void on_start_changed(int64 start) {
        file_source.set("start", start);
    }
    
    protected void add_single_decode_bin(string filename, string caps) {
        Gst.Element sbin = new SingleDecodeBin(Gst.Caps.from_string(caps), 
                                               "singledecoder", filename);
        bool add_result = ((Gst.Bin) file_source).add(sbin);
        assert(add_result);
        bool sync_result = file_source.sync_state_with_parent();
        assert(sync_result);
    }
}

class MediaAudioClip : MediaClip {
    public MediaAudioClip(Gst.Bin composition, Model.Clip clip, string filename) {
        base(composition, clip);
        if (!clip.is_recording) {
            add_single_decode_bin(filename, "audio/x-raw-int");
        }
    }
}

class MediaVideoClip : MediaClip {
    public MediaVideoClip(Gst.Bin composition, Model.Clip clip, string filename) {
        base(composition, clip);
        add_single_decode_bin(filename, "video/x-raw-yuv; video/x-raw-rgb");
    }
}

public abstract class MediaTrack {
    Gee.ArrayList<MediaClip> clips;
    protected weak MediaEngine media_engine;
    protected Gst.Bin composition;
    
    protected Gst.Element default_source;
    protected Gst.Element sink;    
    
    public signal void track_removed(MediaTrack track);

    public MediaTrack(MediaEngine media_engine, Model.Track track) {
        clips = new Gee.ArrayList<MediaClip>();
        this.media_engine = media_engine;
        track.clip_added += on_clip_added;
        track.track_removed += on_track_removed;
        
        media_engine.pre_export += on_pre_export;
        media_engine.post_export += on_post_export;
        
        composition = (Gst.Bin) make_element_with_name("gnlcomposition", track.display_name);
        
        default_source = make_element_with_name("gnlsource", "track_default_source");
        Gst.Bin default_source_bin = (Gst.Bin) default_source;
        if (!default_source_bin.add(empty_element()))
            error("can't add empty element");

        // If we set the priority to 0xffffffff, then Gnonlin will treat this source as
        // a default and we won't be able to seek past the end of the last region.
        // We want to be able to seek into empty space, so we use a fixed priority instead.
        default_source.set("priority", 1);
        default_source.set("start", 0 * Gst.SECOND);
        default_source.set("duration", 1000000 * Gst.SECOND);
        default_source.set("media-start", 0 * Gst.SECOND);
        default_source.set("media-duration", 1000000 * Gst.SECOND);
        
        if (!composition.add(default_source))
            error("can't add default source");
  
        media_engine.pipeline.add(composition);
        composition.pad_added += on_pad_added;
        composition.pad_removed += on_pad_removed;
    }
    
    ~MediaTrack() {
        if (composition != null && !media_engine.pipeline.remove(composition)) {
            error("couldn't remove composition");
        }    
    }
    
    protected abstract Gst.Element empty_element();
    public abstract Gst.Element? get_element();
    
    public abstract void link_new_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element);
    public abstract void unlink_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element);
    
    void on_clip_added(Model.Clip clip) {
        MediaClip media_clip;
        if (clip.type == Model.MediaType.AUDIO) {
            media_clip = new MediaAudioClip(composition, clip, clip.clipfile.filename);
        } else {
            media_clip = new MediaVideoClip(composition, clip, clip.clipfile.filename);
        }
        media_clip.clip_removed += on_media_clip_removed;
        
        clips.add(media_clip);
    }
    
    void on_media_clip_removed(MediaClip clip) {
        clip.clip_removed -= on_media_clip_removed;
        clips.remove(clip);
    }
    
    void on_pad_added(Gst.Bin bin, Gst.Pad pad) {
        link_new_pad(bin, pad, get_element());
    }
    
    void on_pad_removed(Gst.Bin bin, Gst.Pad pad) {
        unlink_pad(bin, pad, get_element());
    }

    void on_track_removed(Model.Track track) {
        track_removed(this);
    }

    void on_pre_export(int64 length) {
        default_source.set("duration", length);
        default_source.set("media-duration", length);
    }
    
    void on_post_export(bool deleted) {
        default_source.set("duration", 1000000 * Gst.SECOND);
        default_source.set("media-duration", 1000000 * Gst.SECOND);
    }
}    

public class MediaVideoTrack : MediaTrack {
    weak Gst.Element converter;

    public MediaVideoTrack(MediaEngine media_engine, Model.Track track, 
            Gst.Element converter) {
        base(media_engine, track);
        this.converter = converter;
    }
    
    public override Gst.Element? get_element() {
        //converter shouldn't be null.  since fillmore is currently not supporting
        //video, but this is a shared track, we can't guarantee at compile time that
        //convert is valid.  This is why we have "Gst.Element?" rather than "Gst.Element"
        assert(converter != null);
        assert(converter.sync_state_with_parent());
        return converter;
    }

    protected override Gst.Element empty_element() {
        Gst.Element blackness = make_element("videotestsrc");
        blackness.set("pattern", 2);     // 2 == GST_VIDEO_TEST_SRC_BLACK
        return blackness;
    }

    public override void link_new_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        if (pad.link(track_element.get_static_pad("sink")) != Gst.PadLinkReturn.OK) {
            error("couldn't link pad to converter");
        }
    }
    
    public override void unlink_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        pad.unlink(track_element.get_static_pad("sink"));
    }
}

public class MediaAudioTrack : MediaTrack {
    Gst.Element audio_convert;
    Gst.Element audio_resample;
    Gst.Element level;
    Gst.Element pan;
    Gst.Element volume;

    public MediaAudioTrack(MediaEngine media_engine, Model.AudioTrack track) {
        base(media_engine, track);
        string display_name = track.display_name;
        track.parameter_changed += on_parameter_changed;
        
        audio_convert = make_element_with_name("audioconvert",
            "audioconvert_%s".printf(display_name));
        audio_resample = make_element_with_name("audioresample",
            "audioresample_%s".printf(display_name));
        level = make_element("level");
 
        pan = make_element("audiopanorama");
        pan.set_property("panorama", 0);
        volume = make_element("volume");
        volume.set_property("volume", 10);

        Value the_level = (uint64) (Gst.SECOND / 30);
        level.set_property("interval", the_level);
        Value true_value = true;
        level.set_property("message", true_value);
        
        if (!media_engine.pipeline.add(audio_convert)) {
            error("could not add audio_convert");
        }
        
        if (!media_engine.pipeline.add(audio_resample)) {
            error("could not add audio_resample");
        }
        
        if (!media_engine.pipeline.add(level)) {
            error("could not add level");
        }
        
        if (!media_engine.pipeline.add(pan)) {
            error("could not add pan");
        }
        
        if (!media_engine.pipeline.add(volume)) {
            error("could not add volume");
        }
        
        media_engine.level_changed += on_level_changed;
        level_changed += track.on_level_changed;
    }
    
    ~MediaAudioTrack() {
        media_engine.level_changed -= on_level_changed;
        media_engine.pipeline.remove_many(audio_convert, audio_resample, pan, volume, level);
    }

    public signal void level_changed(double level_left, double level_right);

    void on_parameter_changed(Model.Parameter parameter, double new_value) {
        switch(parameter) {
            case Model.Parameter.PAN:
                pan.set_property("panorama", new_value);
                break;
            case Model.Parameter.VOLUME:
                volume.set_property("volume", new_value);    
                break;
        }    
    }

    void on_level_changed(Gst.Object source, double level_left, double level_right) {
        if (source == level) {
            level_changed(level_left, level_right);
        }
    }

    protected override Gst.Element empty_element() {
        return media_engine.get_audio_silence();
    }
    
    override void link_new_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        if (!bin.link_many(audio_convert, audio_resample, level, pan, volume, track_element)) {
            error("could not link_new_pad for audio track");
        }
    }
    
    public override void unlink_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        bin.unlink_many(audio_convert, audio_resample, level, pan, volume, track_element);
    }

    public override Gst.Element? get_element() {
        return media_engine.adder;
    }
}

public abstract class MediaConnector {
    public enum MediaTypes { Audio = 1, Video = 2 }
    MediaTypes media_types;
    
    // AudioIndex and VideoIndex are the order elements are passed in to connect and disconnect
    protected int AudioIndex = 0;
    protected int VideoIndex = 1;
    
    protected MediaConnector(MediaTypes media_types) {
        this.media_types = media_types;
    }
    
    protected bool has_audio() {
        return (media_types & MediaTypes.Audio) == MediaTypes.Audio;
    }
    
    protected bool has_video() {
        return (media_types & MediaTypes.Video) == MediaTypes.Video;
    }
    
    public abstract void connect(MediaEngine media_engine, Gst.Pipeline pipeline,
        Gst.Element[] elements);
    public abstract void disconnect(MediaEngine media_engine, Gst.Pipeline pipeline,
        Gst.Element[] elements);
}

public class VideoOutput : MediaConnector {
    Gst.Element sink;
    Gtk.Widget output_widget;

    public VideoOutput(Gtk.Widget output_widget) {
        base(MediaTypes.Video);
        sink = make_element("xvimagesink");
        sink.set("force-aspect-ratio", true);
        this.output_widget = output_widget;
    }

    public override void connect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        media_engine.prepare_window += on_prepare_window;
        pipeline.add(sink);
        if (!elements[VideoIndex].link(sink)) {
            error("can't link converter with video sink!");
        }
        media_engine.sync_element_message();
    }
    
    public override void disconnect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        elements[VideoIndex].unlink(sink);
        pipeline.remove(sink);
        media_engine.prepare_window -= on_prepare_window;
    }
    
    public void on_prepare_window() {
        uint32 xid = Gdk.x11_drawable_get_xid(output_widget.window);
        Gst.XOverlay overlay = (Gst.XOverlay) sink;
        overlay.set_xwindow_id(xid);

        // Once we've connected our video sink to a widget, it's best to turn off GTK
        // double buffering for the widget; otherwise the video image flickers as it's resized.
        output_widget.unset_flags(Gtk.WidgetFlags.DOUBLE_BUFFERED);
    }
}

public class AudioOutput : MediaConnector {
    Gst.Element audio_sink;
    Gst.Element capsfilter;
    
    public AudioOutput(Gst.Caps caps) {
        base(MediaTypes.Audio);
        audio_sink = make_element("gconfaudiosink");
        capsfilter = make_element("capsfilter");
        capsfilter.set("caps", caps);
    }
    
    public override void connect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        pipeline.add_many(capsfilter, audio_sink);
            
        if (!elements[AudioIndex].link_many(capsfilter, audio_sink)) {
            warning("could not link audio_sink");
        }
    }
    
    public override void disconnect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        elements[AudioIndex].unlink_many(capsfilter, audio_sink);
        pipeline.remove_many(capsfilter, audio_sink);
    }
}

public class OggVorbisExport : MediaConnector {
    Gst.Element capsfilter;
    Gst.Element export_sink;    
    Gst.Element mux;
    Gst.Element file_sink;
    Gst.Element video_export_sink;
    
    public OggVorbisExport(MediaConnector.MediaTypes media_types, string filename, Gst.Caps caps) {
        base(media_types);

        file_sink = make_element("filesink");
        file_sink.set("location", filename);
        mux = make_element("oggmux");
        
        if (has_audio()) {
            capsfilter = make_element("capsfilter");
            capsfilter.set("caps", caps);
            export_sink = make_element("vorbisenc");
        }
        
        if (has_video()) {
            video_export_sink = make_element("theoraenc");
        }
    }
    
    public string get_filename() {
        string filename;
        file_sink.get("location", out filename);
        return filename;
    }
    
    public override void connect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        pipeline.add_many(mux, file_sink);
        mux.link(file_sink);
        
        if (has_audio()) {
            pipeline.add_many(capsfilter, export_sink);
            elements[AudioIndex].link_many(capsfilter, export_sink, mux);
        }

        if (has_video()) {
            pipeline.add(video_export_sink);

            if (!elements[VideoIndex].link(video_export_sink)) {
                error("could not link converter to video_export_sink");
            }
            
            if (!video_export_sink.link(mux)) {
                error("could not link video_export with mux");
            }
        }
    }
  
    public override void disconnect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        if (has_audio()) {
            elements[AudioIndex].unlink_many(capsfilter, export_sink, mux);
            pipeline.remove_many(capsfilter, export_sink);
        }
        
        if (has_video()) {
            elements[VideoIndex].unlink_many(video_export_sink, mux);
            pipeline.remove(video_export_sink);
        }
        
        mux.unlink(file_sink);
        pipeline.remove_many(mux, file_sink);
    }
}

public class MediaEngine : MultiFileProgressInterface, Object {
    public Gst.Pipeline pipeline;
    
    // Video playback
    public Gst.Element converter;

    // Audio playback
    public Gst.Element adder;
    
    protected Gst.State gst_state;
    protected PlayState play_state = PlayState.STOPPED;
    public int64 position;  // current play position in ns
    uint callback_id;
    public bool playing;

    public Model.AudioTrack record_track;
    public Model.Clip record_region;
    Gst.Element audio_in;
    Gst.Element record_capsfilter;
    Gst.Element wav_encoder;
    Gst.Element record_sink;

    weak Model.Project project;

    public signal void playstate_changed();
    public signal void position_changed(int64 position);
    public signal void pre_export(int64 length);
    public signal void post_export(bool canceled);
    public signal void callback_pulse();
    public signal void level_changed(Gst.Object source, double level_left, double level_right);
    public signal void record_completed();
    public signal void link_for_playback(Gst.Element mux);
    public signal void link_for_export(Gst.Element mux);
    public signal void prepare_window();

    Gee.ArrayList<MediaTrack> tracks;
    
    public MediaEngine(Model.Project project, bool include_video) {
        tracks = new Gee.ArrayList<MediaTrack>();
        this.project = project;
        playstate_changed += project.on_playstate_changed;
        pipeline = new Gst.Pipeline("pipeline");
        pipeline.set_auto_flush_bus(false);

        if (include_video) {
            converter = make_element("ffmpegcolorspace");
            pipeline.add(converter);
        }

        Gst.Element silence = get_audio_silence();

        adder = make_element("adder");

        Gst.Element audio_convert = make_element_with_name("audioconvert", "projectconvert");
        pipeline.add_many(silence, audio_convert, adder);

        if (!silence.link_many(audio_convert, adder)) {
            error("silence: couldn't link");
        }

        Gst.Bus bus = pipeline.get_bus();

        bus.add_signal_watch();
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;
        bus.message["eos"] += on_eos;    
        bus.message["state-changed"] += on_state_change;
        bus.message["element"] += on_element;
    }
    
    public void connect_output(MediaConnector connector) {
        connector.connect(this, pipeline, { adder, converter });
    }
    
    public void disconnect_output(MediaConnector connector) {
        pipeline.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0);
        pipeline.set_state(Gst.State.NULL);
        connector.disconnect(this, pipeline, {adder, converter});
    }
    
    public void sync_element_message() {
        // We need to wait for the prepare-xwindow-id element message, which tells us when it's
        // time to set the X window ID.  We must respond to this message synchronously.
        // If we used an asynchronous signal (enabled via gst_bus_add_signal_watch) then the
        // xvimagesink would create its own output window which would flash briefly
        // onto the display.
        
        Gst.Bus bus = pipeline.get_bus();

        // TODO: we should be calling disable_sync_message_emission, but it seems that no matter
        // where or when we call it, we get a 'CRITICAL error number of watchers == 0' assert

        bus.enable_sync_message_emission();
        bus.sync_message["element"] += on_element_message;
        
        set_gst_state(Gst.State.PAUSED);                  
    }

    public Gst.Element get_audio_silence() {
        Gst.Element silence = make_element("audiotestsrc");
        silence.set("wave", 4);     // 4 is silence
        Gst.Caps audio_cap = get_project_audio_caps();
        foreach (Gst.Pad pad in silence.pads) {
            pad.set_caps(audio_cap);
        }
        return silence;
    }
    
    public int get_sample_rate() {
        return 48000;
    }
    
    public int get_sample_width() {
        return 16;
    }
    
    public int get_sample_depth() {
        return 16;
    }
    
    protected Gst.Caps build_audio_caps(int num_channels) {
        string caps = "audio/x-raw-int,rate=%d,channels=%d,width=%d,depth=%d";
        caps = caps.printf(get_sample_rate(), num_channels, get_sample_width(), get_sample_depth());
        return Gst.Caps.from_string(caps);
    }
    
    public Gst.Caps get_project_audio_caps() {
        return build_audio_caps(2);
    }

    public Gst.Caps get_project_audio_export_caps() {
        return Gst.Caps.from_string(
            "audio/x-raw-float,rate=48000,channels=2,width=32");
    }    

    void on_warning(Gst.Bus bus, Gst.Message message) {
        Error error;
        string text;
        message.parse_warning(out error, out text);
        warning("%s", text);
    }
    
    void on_error(Gst.Bus bus, Gst.Message message) {
        Error error;
        string text;
        message.parse_error(out error, out text);
        warning("%s", text);
    }

    void on_eos(Gst.Bus bus, Gst.Message message) {
        if (play_state == PlayState.EXPORTING)
            pipeline.set_state(Gst.State.NULL);
    }

    void on_element_message(Gst.Bus bus, Gst.Message message) {
        if (!message.structure.has_name("prepare-xwindow-id"))
            return;

        prepare_window();
        bus.sync_message["element"] -= on_element_message;
    }
    
    void on_element(Gst.Bus bus, Gst.Message message) {
        unowned Gst.Structure structure = message.get_structure();
        
        if (play_state == PlayState.PLAYING && structure.name.to_string() == "level") {
            Gst.Value? rms = structure.get_value("rms");
            uint size = rms.list_get_size();
            Gst.Value? temp = rms.list_get_value(0);
            double level_left = temp.get_double();
            double level_right = level_left;

            if (size > 1) {
                temp = rms.list_get_value(1);
                level_right = temp.get_double();
            }
            level_changed(message.src, level_left, level_right);
        }
    }

    void on_state_change(Gst.Bus bus, Gst.Message message) {
        if (message.src != pipeline)
            return;

        Gst.State old_state;
        Gst.State new_state;
        Gst.State pending;

        message.parse_state_changed(out old_state, out new_state, out pending);

        if (new_state == gst_state)
            return;

        gst_state = new_state;
        do_state_change();
    }

    protected bool do_state_change() {
        playstate_changed();
        switch (play_state) {
            case PlayState.STOPPED:
                if (gst_state != Gst.State.PAUSED) {
                    pipeline.set_state(Gst.State.PAUSED);
                } else {
                    go(position);
                }
                return true;
            case PlayState.PRE_EXPORT:
                if (gst_state != Gst.State.PAUSED) {
                    return false;
                }
                do_paused_state_export();
                return true;
            case PlayState.EXPORTING:
                if (gst_state != Gst.State.NULL)
                    return false;
                end_export(false);
                return true;
            case PlayState.CANCEL_EXPORT:
                if (gst_state != Gst.State.NULL)
                    return false;
                end_export(true);
                return true;
            case PlayState.CLOSING:
                close();
                return true;
            case PlayState.PRE_RECORD_NULL:
                if (gst_state == Gst.State.NULL) {
                    start_record(record_region);
                    return true;
                }
            break;
            case PlayState.PRE_RECORD:
                if (gst_state == Gst.State.PAUSED) {
                    do_play(PlayState.RECORDING);
                    return true;
                }
            break;
            case PlayState.POST_RECORD:
                if (gst_state != Gst.State.NULL) {
                    set_gst_state(Gst.State.NULL);
                } else {
                    post_record();
                    set_gst_state(Gst.State.PAUSED);
                    play_state = PlayState.STOPPED;
                }
                return true;
        }
        return false;
    }

    protected virtual void do_null_state_export(int64 length) {
        pre_export(length);
        play_state = PlayState.PRE_EXPORT;
        pipeline.set_state(Gst.State.PAUSED);
    }
    
    void do_paused_state_export() {
        play_state = PlayState.EXPORTING;
              
        if (callback_id == 0)
            callback_id = Timeout.add(50, on_callback);
        
        pipeline.set_state(Gst.State.PLAYING);        
    }
    
    void end_export(bool deleted) {
        play_state = PlayState.STOPPED;
        
        callback_id = 0;
        post_export(deleted);
    }

    public void go(int64 pos) {
        if (position == pos) {
            pipeline.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, position);        
            return;
        }
        if (pos < 0) 
            position = 0;
        else
            position = pos;
        
        // We ignore the return value of seek_simple(); sometimes it returns false even when
        // a seek succeeds.
        pipeline.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, position);
        position_changed(position);
    }

    bool on_callback() {
        if ((play_state == PlayState.STOPPED && !playing) ||
            (play_state == PlayState.POST_RECORD)) {
            callback_id = 0;
            return false;
        }

        Gst.Format format = Gst.Format.TIME;
        int64 time = 0;
        if (pipeline.query_position(ref format, out time) && format == Gst.Format.TIME) {
            position = time;
            callback_pulse();
            
            if (play_state == PlayState.PLAYING) {
                if (position >= project.get_length()) {
                    go(project.get_length());
                    pause();
                }
                position_changed(time);
            } else if (play_state == PlayState.EXPORTING) {
                if (time > project.get_length()) {
                    fraction_updated(1.0);
                }
                else
                    fraction_updated(time / (double) project.get_length());
            }
        }
        return true;
    }

    public virtual void pause() {
        if (project.transport_is_recording()) {
            play_state = PlayState.POST_RECORD;
        } else {
            if (!playing) {
                return;
            }
            play_state = PlayState.STOPPED;
        }
        set_gst_state(Gst.State.PAUSED);
        playing = false;
    }

    protected void set_gst_state(Gst.State state) {
        if (pipeline.set_state(state) == Gst.StateChangeReturn.FAILURE)
            error("can't set state");
    }

    void seek(Gst.SeekFlags flags, int64 pos) {
        // We do *not* check the return value of seek_simple here: it will often
        // be false when seeking into a GnlSource which we have not yet played,
        // even though the seek appears to work fine in that case.
        pipeline.seek_simple(Gst.Format.TIME, flags, pos);
    }

    protected void do_play(PlayState new_state) {
        seek(Gst.SeekFlags.FLUSH, position);
        play_state = new_state;
        play();
    }

    void play() {
        if (playing)
            return;

        set_gst_state(Gst.State.PLAYING);
        if (callback_id == 0)
            callback_id = Timeout.add(50, on_callback);
        playing = true;
    }

    public void start_export(string filename) {
        file_updated(filename, 0);
        do_null_state_export(project.get_length());
    }

    void cancel() {
        play_state = PlayState.CANCEL_EXPORT;
        pipeline.set_state(Gst.State.NULL);
    }
    
    public void complete() {
        pipeline.set_state(Gst.State.NULL);
    }

    public void on_load_complete() {
        play_state = PlayState.STOPPED;
        pipeline.set_state(Gst.State.PAUSED);
    }
    
    public void on_callback_pulse() {
        if (record_region != null) {
            record_region.duration = position - record_region.start;
        }
    }
    
    public void close() {
        if (gst_state != Gst.State.NULL) {
            play_state = PlayState.CLOSING;
            set_gst_state(Gst.State.NULL);
        } else {
            play_state = PlayState.CLOSED;
        }
        playstate_changed();
    }

    public void post_record() {
        assert(gst_state == Gst.State.NULL);

        int clip_index = record_track.get_clip_index(record_region);
        record_track.remove_clip(clip_index);
        
        audio_in.unlink_many(record_capsfilter, wav_encoder, record_sink);
        pipeline.remove_many(audio_in, record_capsfilter, wav_encoder, record_sink);

        record_completed();
        record_region = null;
        record_track = null;
        audio_in = record_capsfilter = null;
        wav_encoder = record_sink = null;
    }

    public void record(Model.AudioTrack track) {
        play_state = PlayState.PRE_RECORD_NULL;
        set_gst_state(Gst.State.NULL);
        record_track = track;

        string filename = new_audio_filename(track);
        Model.ClipFile clip_file = new Model.ClipFile(filename);
        record_region = new Model.Clip(clip_file, Model.MediaType.AUDIO, "", position, 0, 1, true);
    }

    public void start_record(Model.Clip region) {
        if (project.transport_is_recording())
            return;
        
        if (project.transport_is_playing())
            error("can't switch from playing to recording");
            
        if (gst_state != Gst.State.NULL)
            error("can't record now: %s", gst_state.to_string());

        record_track._add_clip_at(record_region, position, false);
        record_track.clip_added(record_region);
        audio_in = make_element("gconfaudiosrc");
        record_capsfilter = make_element("capsfilter");
        record_capsfilter.set("caps", get_record_audio_caps());
        record_sink = make_element("filesink");
        record_sink.set("location", region.clipfile.filename);
        wav_encoder = make_element("wavenc");
        
        pipeline.add_many(audio_in, record_capsfilter, wav_encoder, record_sink);
        if (!audio_in.link_many(record_capsfilter, wav_encoder, record_sink))
            error("audio_in: couldn't link");

        play_state = PlayState.PRE_RECORD;
        set_gst_state(Gst.State.PAUSED);    // we must advance to PAUSED before we can seek
    }

    protected Gst.Caps get_record_audio_caps() {
        return build_audio_caps(1);
    }

    string new_audio_filename(Model.Track track) {
        int i = 1;
        string base_path = Path.build_filename(GLib.Environment.get_home_dir(), "audio files");
        GLib.DirUtils.create(base_path, 0777);
        string base_name = Path.build_filename(base_path, generate_base(track.display_name));
        while (true) {
            string name = "%s_%d.wav".printf(base_name, i);
            if (!FileUtils.test(name, FileTest.EXISTS)) {
                return name;
            }
            ++i;
        }
    }
    
    string generate_base(string name) {
        string base_name = name.down();
        base_name.canon("abcdefghijklmnopqrstuvwxyz1234567890", '_');
        return base_name;
    }

    public void on_track_added(Model.Track track) {
        MediaTrack? media_track = null;
        switch (track.media_type()) {
            case Model.MediaType.AUDIO:
                media_track = create_audio_track(track);
                break;
            case Model.MediaType.VIDEO:
                media_track = new MediaVideoTrack(this, track, converter);
                break;
        }
        
        media_track.track_removed += on_track_removed;
        
        tracks.add(media_track);
    }

    MediaTrack create_audio_track(Model.Track track) {
        Model.AudioTrack? model_track = track as Model.AudioTrack;
        MediaAudioTrack? audio_track = null;
        if (model_track != null) {
            audio_track = new MediaAudioTrack(this, model_track);
        } else {
            assert(false);
        }
        return audio_track;
    }
    
    void on_track_removed(MediaTrack track) {
        tracks.remove(track);
    }
}
}
