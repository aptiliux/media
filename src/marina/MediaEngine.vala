/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

public enum PlayState {
    STOPPED,
    PRE_PLAY, PLAYING,
    PRE_RECORD_NULL, PRE_RECORD, RECORDING, POST_RECORD,
    PRE_EXPORT, EXPORTING, CANCEL_EXPORT,
    LOADING, 
    CLOSING, CLOSED
}

namespace View {

class MediaClip : Object {
    public Gst.Element file_source;
    weak Model.Clip clip;
    Gst.Bin composition;

    public signal void clip_removed(MediaClip clip);

    public MediaClip(Gst.Bin composition, Model.Clip clip) throws Error {
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

    public void on_clip_removed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_removed");
        composition.remove((Gst.Bin)file_source);
        clip_removed(this);
    }

    void on_media_start_changed(int64 media_start) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_media_start_changed");
        file_source.set("media-start", media_start);
    }

    void on_duration_changed(int64 duration) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_duration_changed");
        file_source.set("duration", duration);
        // TODO: is media-duration necessary?
        file_source.set("media-duration", duration);
    }

    void on_start_changed(int64 start) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_start_changed");
        file_source.set("start", start);
    }

    protected void add_single_decode_bin(string filename, string caps) throws Error {
        Gst.Element sbin = new SingleDecodeBin(Gst.Caps.from_string(caps), 
                                               "singledecoder", filename);
        bool add_result = ((Gst.Bin) file_source).add(sbin);
        assert(add_result);
        bool sync_result = file_source.sync_state_with_parent();
        assert(sync_result);
    }

    public bool is_equal(Model.Clip clip) {
        return clip == this.clip;
    }
}

class MediaAudioClip : MediaClip {
    public MediaAudioClip(Gst.Bin composition, Model.Clip clip, string filename) throws Error {
        base(composition, clip);
        if (!clip.is_recording) {
            add_single_decode_bin(filename, "audio/x-raw-float;audio/x-raw-int");
        }
    }
}

class MediaVideoClip : MediaClip {
    public MediaVideoClip(Gst.Bin composition, Model.Clip clip, string filename) throws Error {
        base(composition, clip);
        add_single_decode_bin(filename, "video/x-raw-yuv; video/x-raw-rgb");
    }
}

public abstract class MediaTrack : Object {
    Gee.ArrayList<MediaClip> clips;
    protected weak MediaEngine media_engine;
    protected Gst.Bin composition;

    protected Gst.Element default_source;
    protected Gst.Element sink;

    public signal void track_removed(MediaTrack track);
    public signal void error_occurred(string major_message, string? minor_message);

    public MediaTrack(MediaEngine media_engine, Model.Track track) throws Error {
        clips = new Gee.ArrayList<MediaClip>();
        this.media_engine = media_engine;
        track.clip_added += on_clip_added;
        track.track_removed += on_track_removed;

        media_engine.pre_export += on_pre_export;
        media_engine.post_export += on_post_export;

        composition = (Gst.Bin) make_element("gnlcomposition");

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

        if (!composition.add(default_source)) {
            error("can't add default source");
        }

        media_engine.pipeline.add(composition);
        composition.pad_added += on_pad_added;
        composition.pad_removed += on_pad_removed;
    }

    ~MediaTrack() {
        if (composition != null && !media_engine.pipeline.remove(composition)) {
            error("couldn't remove composition");
        }
    }

    protected abstract Gst.Element empty_element() throws Error;
    public abstract Gst.Element? get_element();

    public abstract void link_new_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element);
    public abstract void unlink_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element);

    void on_clip_added(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_added");
        clip.updated += on_clip_updated;
        on_clip_updated(clip);
    }

    void on_clip_updated(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_updated");
        if (clip.clipfile.is_online()) {
            try {
                MediaClip media_clip;
                if (clip.type == Model.MediaType.AUDIO) {
                    media_clip = new MediaAudioClip(composition, clip, clip.clipfile.filename);
                } else {
                    media_clip = new MediaVideoClip(composition, clip, clip.clipfile.filename);
                }
                media_clip.clip_removed += on_media_clip_removed;

                clips.add(media_clip);
            } catch (Error e) {
                error_occurred("Could not create clip", e.message);
            }
        } else {
            foreach (MediaClip media_clip in clips) {
                if (media_clip.is_equal(clip)) {
                    media_clip.on_clip_removed();
                }
            }
        }
    }

    void on_media_clip_removed(MediaClip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_media_clip_removed");
        clip.clip_removed -= on_media_clip_removed;
        clips.remove(clip);
    }

    void on_pad_added(Gst.Bin bin, Gst.Pad pad) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_pad_added");
        link_new_pad(bin, pad, get_element());
    }

    void on_pad_removed(Gst.Bin bin, Gst.Pad pad) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_pad_removed");
        unlink_pad(bin, pad, get_element());
    }

    void on_track_removed(Model.Track track) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_removed");
        track_removed(this);
    }

    void on_pre_export(int64 length) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_pre_export");
        default_source.set("duration", length);
        default_source.set("media-duration", length);
    }

    void on_post_export(bool deleted) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_post_export");
        default_source.set("duration", 1000000 * Gst.SECOND);
        default_source.set("media-duration", 1000000 * Gst.SECOND);
    }
}

public class MediaVideoTrack : MediaTrack {
    weak Gst.Element converter;

    public MediaVideoTrack(MediaEngine media_engine, Model.Track track, 
            Gst.Element converter) throws Error {
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

    protected override Gst.Element empty_element() throws Error {
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

public class ClickTrack : Object {
    Gst.Controller click_controller;
    Gst.Controller volume_controller;
    Gst.Element audio_source;
    Gst.Element audio_convert;
    Gst.Element volume;
    weak Model.Project project;

    public ClickTrack(MediaEngine engine, Model.Project project) throws Error {
        this.project = project;
        audio_source = make_element("audiotestsrc");
        audio_convert = make_element("audioconvert");
        volume = make_element("volume");
        GLib.List<string> list = new GLib.List<string>();
        list.append("freq");
        click_controller = new Gst.Controller.list(audio_source, list);
        list.remove_all("freq");
        list.append("mute");
        volume_controller = new Gst.Controller.list(volume, list);
        engine.pipeline.add_many(audio_source, volume, audio_convert);
        audio_source.set("volume", project.click_volume);

        audio_source.link_many(audio_convert, volume, engine.adder);
        engine.playstate_changed += on_playstate_changed;
    }

    void clear_controllers() {
        volume_controller.unset_all("mute");
        click_controller.unset_all("freq");
        volume.set("mute", true);
        volume.set("volume", 0.0);
    }

    void on_playstate_changed() {
        switch (project.media_engine.get_play_state()) {
            case PlayState.PRE_EXPORT:
            case PlayState.STOPPED:
                clear_controllers();
            break;
            case PlayState.PLAYING: {
                if (project.click_during_play) {
                    setup_clicks(project.get_bpm(), project.get_time_signature());
                } else {
                    clear_controllers();
                }
            }
            break;
            case PlayState.PRE_RECORD: {
                if (project.click_during_record) {
                    setup_clicks(project.get_bpm(), project.get_time_signature());
                } else {
                    clear_controllers();
                }
            }
            break;
        }
    }

    void setup_clicks(int bpm, Fraction time_signature) {
        clear_controllers();
        volume.set("volume", project.click_volume / 10);

        Gst.Value double_value = Gst.Value();
        double_value.init(Type.from_name("gdouble"));
        Gst.Value bool_value = Gst.Value();
        bool_value.init(Type.from_name("gboolean"));

        Gst.ClockTime time = (Gst.ClockTime)(0);
        bool_value.set_boolean(true);
        volume_controller.set("volume", time, bool_value);

        int64 conversion = (Gst.SECOND * 60) / bpm;
        uint64 current_time = 0;
        // TODO: We are playing for a hard-coded amount of time.
        for (int i = 0; current_time < Gst.SECOND * 60 * 10; ++i) {
            current_time = i * conversion;
            if (i > 0) {
                time = (Gst.ClockTime)(current_time - Gst.SECOND/10);
                bool_value.set_boolean(true);
                volume_controller.set("mute", time, bool_value);
            }
            time = (Gst.ClockTime)(current_time);
            if ((i % time_signature.numerator) == 0) {
                double_value.set_double(880.0);
            } else {
                double_value.set_double(440.0);
            }
            click_controller.set("freq", time, double_value);
            bool_value.set_boolean(false);
            volume_controller.set("mute", time, bool_value);

            time = (Gst.ClockTime)(current_time + Gst.SECOND/10);
            bool_value.set_boolean(true);
            volume_controller.set("mute", time, bool_value);
        }
    }
}

public class MediaAudioTrack : MediaTrack {
    Gst.Element audio_convert;
    Gst.Element audio_resample;
    Gst.Element level;
    Gst.Element pan;
    Gst.Element volume;
    Gst.Pad adder_pad;

    public MediaAudioTrack(MediaEngine media_engine, Model.AudioTrack track) throws Error {
        base(media_engine, track);
        track.parameter_changed += on_parameter_changed;

        audio_convert = make_element("audioconvert");
        audio_resample = make_element("audioresample");
        level = make_element("level");

        pan = make_element("audiopanorama");
        on_parameter_changed(Model.Parameter.PAN, track.get_pan());
        volume = make_element("volume");
        on_parameter_changed(Model.Parameter.VOLUME, track.get_volume());

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
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_parameter_changed");
        switch (parameter) {
            case Model.Parameter.PAN:
                pan.set_property("panorama", new_value);
                break;
            case Model.Parameter.VOLUME:
                volume.set_property("volume", new_value);    
                break;
        }    
    }

    void on_level_changed(Gst.Object source, double level_left, double level_right) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_level_changed");
        if (source == level) {
            level_changed(level_left, level_right);
        }
    }

    protected override Gst.Element empty_element() throws Error {
        return media_engine.get_audio_silence();
    }

    override void link_new_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        if (!bin.link_many(audio_convert, audio_resample, level, pan, volume)) {
            stderr.printf("could not link_new_pad for audio track");
        }

        Gst.Pad volume_pad = volume.get_pad("src");
        adder_pad = track_element.request_new_pad(
            track_element.get_compatible_pad_template(volume_pad.get_pad_template()), null);

        if (volume_pad.link(adder_pad) != Gst.PadLinkReturn.OK) {
            error("could not link to adder %s->%s\n", volume.name, track_element.name);
        }
    }

    public override void unlink_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        bin.unlink_many(audio_convert, audio_resample, level, pan, volume, track_element);
        track_element.release_request_pad(adder_pad);
    }

    public override Gst.Element? get_element() {
        return media_engine.adder;
    }
}

public abstract class MediaConnector : Object {
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

    public new abstract void connect(MediaEngine media_engine, Gst.Pipeline pipeline,
        Gst.Element[] elements);
    public abstract void do_disconnect(MediaEngine media_engine, Gst.Pipeline pipeline,
        Gst.Element[] elements);
}

public class VideoOutput : MediaConnector {
    Gst.Element sink;
    Gtk.Widget output_widget;

    public VideoOutput(Gtk.Widget output_widget) throws Error {
        base(MediaTypes.Video);
        sink = make_element("xvimagesink");
        sink.set("force-aspect-ratio", true);
        this.output_widget = output_widget;
    }

    public override void connect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        emit(this, Facility.GRAPH, Level.INFO, "connecting");

        X.ID xid = Gdk.x11_drawable_get_xid(output_widget.window);
        Gst.XOverlay overlay = (Gst.XOverlay) sink;
        overlay.set_xwindow_id(xid);

        // Once we've connected our video sink to a widget, it's best to turn off GTK
        // double buffering for the widget; otherwise the video image flickers as it's resized.
        output_widget.unset_flags(Gtk.WidgetFlags.DOUBLE_BUFFERED);

        if (!pipeline.add(sink)) {
            error("could not add sink");
        }
        if (!elements[VideoIndex].link(sink)) {
            error("can't link converter with video sink!");
        }
    }

    public override void do_disconnect(MediaEngine media_engine, Gst.Pipeline pipeline, 
            Gst.Element[] elements) {
        emit(this, Facility.GRAPH, Level.INFO, "disconnecting");
        elements[VideoIndex].unlink(sink);
        pipeline.remove(sink);
    }
}

public class AudioOutput : MediaConnector {
    Gst.Element audio_sink;
    Gst.Element capsfilter;

    public AudioOutput(Gst.Caps caps) throws Error {
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

    public override void do_disconnect(MediaEngine media_engine, Gst.Pipeline pipeline, 
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

    public OggVorbisExport(MediaConnector.MediaTypes media_types, string filename, Gst.Caps caps) 
            throws Error {
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

    public override void do_disconnect(MediaEngine media_engine, Gst.Pipeline pipeline, 
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
    const string MIN_GNONLIN = "0.10.15";
    const string MIN_GST_PLUGINS_GOOD = "0.10.21";
    const string MIN_GST_PLUGINS_BASE = "0.10.28";
    public Gst.Pipeline pipeline;
    public Gst.Bin record_bin;
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
    public signal void error_occurred(string major_message, string? minor_message);

    Gee.ArrayList<MediaTrack> tracks;

    public MediaEngine(Model.Project project, bool include_video) throws Error {
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

    public static void can_run() throws Error {
        Gst.Registry registry = Gst.Registry.get_default();
        check_version(registry, "adder", "gst-plugins-base", MIN_GST_PLUGINS_BASE);
        check_version(registry, "level", "gst-plugins-good", MIN_GST_PLUGINS_GOOD);
        check_version(registry, "gnonlin", "gnonlin", View.MediaEngine.MIN_GNONLIN);
    }

    static void check_version(Gst.Registry registry, string plugin_name, 
            string package_name, string min_version) throws Error {
        Gst.Plugin plugin = registry.find_plugin(plugin_name);
        if (plugin == null) {
            throw new MediaError.MISSING_PLUGIN(
                "You must install %s to use this program".printf(package_name));
        }

        string version = plugin.get_version();
        if (!version_at_least(version, min_version)) {
            throw new MediaError.MISSING_PLUGIN(
                "You have %s version %s, but this program requires at least version %s".printf(
                package_name, version, min_version));
        }
    }

    public void connect_output(MediaConnector connector) {
        connector.connect(this, pipeline, { adder, converter });
    }

    public void disconnect_output(MediaConnector connector) {
        pipeline.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0);
        pipeline.set_state(Gst.State.NULL);
        connector.do_disconnect(this, pipeline, {adder, converter});
    }

    public Gst.Element get_audio_silence() throws Error {
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

    public PlayState get_play_state() {
        return play_state;
    }

    public void set_play_state(PlayState play_state) {
        this.play_state = play_state;
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
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_warning");
        Error error;
        string text;
        message.parse_warning(out error, out text);
        warning("%s", text);
    }

    void on_error(Gst.Bus bus, Gst.Message message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_error");
        Error error;
        string text;
        message.parse_error(out error, out text);
        warning("%s", text);
        project.print_graph(pipeline, "bus_error");
    }

    void on_eos(Gst.Bus bus, Gst.Message message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_eos");
        if (play_state == PlayState.EXPORTING)
            pipeline.set_state(Gst.State.NULL);
    }

    void on_element(Gst.Bus bus, Gst.Message message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_element");
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
        if (message.src != pipeline) {
            emit(this, Facility.GRAPH, Level.VERBOSE, 
                "on_state_change returning.  message from %s".printf(message.src.get_name()));
            return;
        }

        Gst.State old_state;
        Gst.State new_state;
        Gst.State pending;

        message.parse_state_changed(out old_state, out new_state, out pending);

        emit(this, Facility.GRAPH, Level.INFO, 
            "on_state_change old(%s) new(%s) pending(%s)".printf(old_state.to_string(),
                new_state.to_string(), pending.to_string()));
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
                    try {
                        start_record(record_region);
                    } catch (GLib.Error error) {
                        error_occurred("An error occurred starting the recording.", null);
                        warning("An error occurred starting the recording: %s", error.message);
                    }
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
            } else if (play_state == PlayState.RECORDING) {
                position_changed(time);
            }
        }
        return true;
    }

    public virtual void pause() {
        if (project.transport_is_recording()) {
            record_bin.send_event(new Gst.Event.eos());
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

    // TODO: don't expose Gst.State
    public void set_gst_state(Gst.State state) {
        if (pipeline.set_state(state) == Gst.StateChangeReturn.FAILURE)
            error("can't set state");
    }

    void seek(Gst.SeekFlags flags, int64 pos) {
        // We do *not* check the return value of seek_simple here: it will often
        // be false when seeking into a GnlSource which we have not yet played,
        // even though the seek appears to work fine in that case.
        pipeline.seek_simple(Gst.Format.TIME, flags, pos);
    }

    public void do_play(PlayState new_state) {
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
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_complete");
        play_state = PlayState.STOPPED;
        pipeline.set_state(Gst.State.PAUSED);
    }

    public void on_callback_pulse() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_callback_pulse");
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

        record_track._delete_clip(record_region);

        audio_in.unlink_many(record_capsfilter, wav_encoder, record_sink);
        record_bin.remove_many(audio_in, record_capsfilter, wav_encoder, record_sink);
        pipeline.remove(record_bin);
        record_completed();
        record_bin = null;
        record_region = null;
        record_track = null;
        audio_in = record_capsfilter = null;
        wav_encoder = record_sink = null;
    }

    public void record(Model.AudioTrack track) {
        assert(gst_state != Gst.State.NULL);
        play_state = PlayState.PRE_RECORD_NULL;
        set_gst_state(Gst.State.NULL);
        record_track = track;

        string filename = new_audio_filename(track);
        Model.ClipFile clip_file = new Model.ClipFile(filename);
        record_region = new Model.Clip(clip_file, Model.MediaType.AUDIO, "", position, 0, 1, true);
    }

    public void start_record(Model.Clip region) throws Error {
        if (project.transport_is_recording())
            return;

        if (project.transport_is_playing())
            error("can't switch from playing to recording");

        if (gst_state != Gst.State.NULL)
            error("can't record now: %s", gst_state.to_string());
        record_bin = new Gst.Bin("recordingbin");
        record_track._move(record_region, position);
        record_track.clip_added(record_region, true);
        audio_in = make_element("gconfaudiosrc");
        record_capsfilter = make_element("capsfilter");
        record_capsfilter.set("caps", get_record_audio_caps());
        record_sink = make_element("filesink");
        record_sink.set("location", record_region.clipfile.filename);
        wav_encoder = make_element("wavenc");

        record_bin.add_many(audio_in, record_capsfilter, wav_encoder, record_sink);
        if (!audio_in.link_many(record_capsfilter, wav_encoder, record_sink))
            error("audio_in: couldn't link");
        pipeline.add(record_bin);

        play_state = PlayState.PRE_RECORD;
        set_gst_state(Gst.State.PAUSED);    // we must advance to PAUSED before we can seek
    }

    protected Gst.Caps get_record_audio_caps() {
        return build_audio_caps(1);
    }

    string new_audio_filename(Model.Track track) {
        int i = 1;
        string base_path = project.get_audio_path();
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
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_added");
        MediaTrack? media_track = null;
        try {
            switch (track.media_type()) {
                case Model.MediaType.AUDIO:
                    media_track = create_audio_track(track);
                    break;
                case Model.MediaType.VIDEO:
                    media_track = new MediaVideoTrack(this, track, converter);
                    break;
            }
        } catch(GLib.Error error) {
            error_occurred("An error occurred adding the track.", null);
            warning("An error occurred adding the track: %s", error.message);
            return;
        }

        media_track.track_removed += on_track_removed;
        media_track.error_occurred += on_error_occurred;

        tracks.add(media_track);
        if (gst_state == Gst.State.PAUSED) {
            pipeline.set_state(Gst.State.READY);
            pipeline.set_state(Gst.State.PAUSED);
        }
    }

    MediaTrack create_audio_track(Model.Track track) throws Error {
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
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_track_removed");
        tracks.remove(track);
    }

    void on_error_occurred(string major_message, string? minor_message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_error_occurred");
        error_occurred(major_message, minor_message);
    }
}
}
