/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
public enum PlayState {
    STOPPED,
    PRE_PLAY, PLAYING,
    PRE_RECORD_NULL, PRE_RECORD, RECORDING, POST_RECORD,
    PRE_EXPORT_NULL, PRE_EXPORT, EXPORTING, CANCEL_EXPORT
}

// TODO: Project derives from MultiFileProgress interface for exporting
// Move exporting work to separate object similar to import.    
public abstract class Project : MultiFileProgressInterface, Object {
    protected Gst.State gst_state;
    protected PlayState play_state = PlayState.STOPPED;
    
    Gst.Element file_sink;
    Gst.Element mux;
    Gst.Element export_sink;
    public Gst.Pipeline pipeline;
    public Gst.Element audio_sink;
    public Gst.Element adder;
    public Gst.Element capsfilter;

    public Gee.ArrayList<Track> tracks = new Gee.ArrayList<Track>();
    Gee.HashSet<Model.ClipFetcher> pending = new Gee.HashSet<Model.ClipFetcher>();
    Gee.ArrayList<ClipFile> clipfiles = new Gee.ArrayList<ClipFile>();

    public string project_file;
    public ProjectLoader loader;

    public bool playing;
    public int64 position;  // current play position in ns
    uint callback_id;
    FetcherCompletion fetcher_completion;
    
    public signal void pre_export();
    public signal void post_export();
    public signal void position_changed();
    public signal void callback_pulse();
    
    public signal void name_changed(string? project_file);
    public signal void load_error(string error);
    public signal void load_success();
    public signal void track_added(Track track);
    public signal void error_occurred(string error_message);
    
    public signal void clipfile_added(ClipFile c);

    public abstract TimeCode get_clip_time(ClipFile f);

    public Project(string? filename) {
        pipeline = new Gst.Pipeline("pipeline");
        pipeline.set_auto_flush_bus(false);

        Gst.Element silence = get_audio_silence();

        adder = make_element("adder");

        capsfilter = make_element("capsfilter");
        capsfilter.set("caps", get_project_audio_caps());

        audio_sink = make_element("gconfaudiosink");
        Gst.Element audio_convert = make_element_with_name("audioconvert", "projectconvert");
        pipeline.add_many(silence, audio_convert, adder, capsfilter, audio_sink);

        if (!silence.link_many(audio_convert, adder, capsfilter, audio_sink)) {
            error("silence: couldn't link");
        }

        Gst.Bus bus = pipeline.get_bus();

        bus.add_signal_watch();
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;
        bus.message["eos"] += on_eos;    
        set_gst_state(Gst.State.PAUSED);                  
    }

    public void print_graph(Gst.Bin bin, string file_name) {
        Gst.debug_bin_to_dot_file_with_ts(bin, Gst.DebugGraphDetails.ALL, file_name);
    }
    
    // We initialize this message here because there are problems
    // with getting state changes on an asynchronous load from the
    // command line, so we wait until the load is complete before
    // allowing them to be sent
    void bus_init() {
        Gst.Bus bus = pipeline.get_bus();
        bus.message["state-changed"] += on_state_change; 
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
    
    protected virtual bool do_state_changed(Gst.State state, PlayState play_state) {
        if (gst_state == Gst.State.PAUSED) {
            if (play_state == PlayState.PRE_PLAY) {
                do_play(PlayState.PLAYING);
                return true;
            }
        }
        return false;
    }
    
    protected void do_play(PlayState new_state) {
        assert(gst_state == Gst.State.PAUSED);

        seek(Gst.SeekFlags.FLUSH, position);

        play_state = new_state;
        play();
    }
    
    public int64 get_length() {
        int64 max = 0;
        foreach (Track track in tracks) {
            max = int64.max(max, track.get_length());
        }
        return max;
    }
    
    public void snap_clip(Clip c, int64 span) {
        foreach (Track track in tracks) {
            if (track.snap_clip(c, span)) {
                break;
            }
        }
    }
    
    public void snap_coord(out int64 coord, int64 span) {
        foreach (Track track in tracks) {
            if (track.snap_coord(out coord, span)) {
                break;
            }
        }
    }
    
    public bool delete_gap(Track t, Gap g, bool single) {
        if (single) {
            t.delete_gap(g);
            return true;
        } else {
            Gap temp = g;
            foreach (Track track in tracks) {
                if (track != t) {
                    temp = temp.intersect(track.find_first_gap(temp.start));
                }
            }

            if (!temp.is_empty()) {
                foreach (Track track in tracks) {
                    track.delete_gap(temp);
                }
                return true;
            }
            return false;
        }
    }

    protected virtual void do_append(ClipFile clipfile, string name, int64 insert_time) {
        if (clipfile.audio_caps != null) {
            Clip clip = new Clip(clipfile, MediaType.AUDIO, name, 0, 0, clipfile.length);
            Track? track = find_audio_track();
            if (track != null) {
                track.append_at_time(clip, insert_time);
            }
        }
    }
    
    public void append(ClipFile clipfile) {
        string name = isolate_filename(clipfile.filename);
        int64 insert_time = 0;
        
        foreach (Track temp_track in tracks) {
            insert_time = int64.max(insert_time, temp_track.get_length());
        }
        do_append(clipfile, name, insert_time);        
    }

    public void on_clip_removed(Track t, Clip clip) {
        reseek();
    }

    public virtual Gst.Element? get_track_element(Track track) {
        if (track is AudioTrack) {
            return adder;
        }
        
        assert(false); // shouldn't be able to get here
        return null;
    }
    
    public void on_pad_added(Track track, Gst.Bin bin, Gst.Pad pad) {
        track.link_new_pad(bin, pad, get_track_element(track));
    }
    
    public void on_pad_removed(Track track, Gst.Bin bin, Gst.Pad pad) {
        track.unlink_pad(bin, pad, get_track_element(track));
    }
   
    public void split_at_playhead() {
        foreach (Track track in tracks) {
            track.split_at(position);
        }
    }
    
    public bool can_trim(out bool left) {
        Clip first_clip = null;
        
        // When trimming multiple clips, we allow trimming left only if both clips already start
        // at the same position, and trimming right only if both clips already end at the same
        // position.

        int64 start = 0;
        int64 end = 0;
        bool start_same = true;
        bool end_same = true;
        foreach (Track track in tracks) {
            Clip clip = track.get_clip_by_position(position);
            if (first_clip != null && clip != null) {
                start_same = start_same && start == clip.start;
                end_same = end_same && end == clip.end;
            } else if (clip != null) {
                first_clip = clip;
                start = first_clip.start;
                end = first_clip.end;
            }
        }

        if (first_clip == null) {
            return false;
        }
        
        if (start_same && !end_same) {
            left = true;
            return true;
        }
        
        if (!start_same && end_same) {
            left = false;
            return true;
        }
        
        // which half of the clip are we closer to?
        left = (position - first_clip.start < first_clip.length / 2);
        return true;
    }
    
    public void trim_to_playhead() {
        bool left;
        if (!can_trim(out left))
            return;

        Clip first_clip = null;
        foreach (Track track in tracks) {
            Clip clip = track.get_clip_by_position(position);
            if (clip != null) {
                track.trim(clip, position, left);
            }
        }
            
        if (left && first_clip != null) {
            go(first_clip.start);
        }
    }
    
    public bool is_playing() {
        return playing;
    }
    
    public bool playhead_on_clip() {
        foreach (Track track in tracks) {
            if (track.get_clip_by_position(position) != null) {
                return true;
            }
        }
        return false;
    }
    
    public void add_track(Track track) {
        track.clip_removed += on_clip_removed;
        track.pad_added += on_pad_added;
        track.pad_removed += on_pad_removed;
        tracks.add(track);
        track_added(track);
    }
    
    public void add_clipfile(ClipFile clipfile) {
        clipfiles.add(clipfile);
        clipfile_added(clipfile);
    }
    
    public bool remove_clipfile(string filename) {
        ClipFile cf = find_clipfile(filename);
        if (cf != null) {
            foreach (Track t in tracks) {
                if (t.contains_clipfile(cf))
                    return false;
            }
            clipfiles.remove(cf);
        }
        return true;
    }
    
    public ClipFile? find_clipfile(string filename) {
        foreach (ClipFile cf in clipfiles)
            if (cf.filename == filename)
                return cf;
        return null;
    }
    
    // TODO this should go away all together when the XML loading gets fixed up
    public VideoTrack? find_video_track() {
        foreach (Track track in tracks) {
            if (track is VideoTrack) {
                return track as VideoTrack;
            }
        }
        return null;
    }
    
    // TODO this should go away all together when the XML loading gets fixed up
    public Track? find_audio_track() {
        foreach (Track track in tracks) {
            if (track is AudioTrack) {
                return track;
            }
        }
        return null;
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
            
            if (play_state == PlayState.STOPPED) {
                
                if (position >= get_length()) {
                    go(get_length());
                    pause();
                }
                position_changed();
            } else if (play_state == PlayState.EXPORTING) {
                if (time > get_length()) {
                    fraction_updated(1.0);
                }
                else
                    fraction_updated(time / (double) get_length());
            }
        }
        return true;
    }
    
    public void play() {
        if (playing)
            return;

        set_gst_state(Gst.State.PLAYING);
        if (callback_id == 0)
            callback_id = Timeout.add(50, on_callback);
        playing = true;
    }
    
    public virtual void pause() {
        if (!playing)
            return;

        set_gst_state(Gst.State.PAUSED);
        playing = false;
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
        position_changed();
    }
    
    public void reseek() { go(position); }
    
    public void go_start() { go(0); }
  
    public void go_end() { go(get_length()); }
    
    public void go_previous() {
        int64 start_pos = position;
        
        // If we're currently playing, we jump to the previous clip if we're within the first
        // second of the current clip.
        if (playing)
            start_pos -= 1 * Gst.SECOND;
        
        int64 new_position = 0;
        foreach (Track track in tracks) {
            new_position = int64.max(new_position, track.previous_edit(start_pos));
        }
        go(new_position);
    }
    
    public void go_next() {
        int64 new_position = 0;
        foreach (Track track in tracks) {
            if (track.get_length() > position) {
                if (new_position != 0) {
                    new_position = int64.min(new_position, track.next_edit(position));
                } else {
                    new_position = track.next_edit(position);
                }
            }
        }
        go(new_position);
    }
    
    public int64 get_position() {
        return position;
    }
    
    public void set_name(string? filename) {
        this.project_file = filename;
        name_changed(filename);
    }
    
    public void clear() {
        foreach (Track track in tracks) {
            track.delete_all_clips();
        }
        clipfiles.clear();
        set_name(null);
    }
    
    public bool can_export() {
        return find_video_track().get_length() != 0 ||
               find_audio_track().get_length() != 0;
    }
    
    public void start_export(string filename) {
        play_state = PlayState.PRE_EXPORT_NULL;    
        file_sink = make_element("filesink");
        file_sink.set("location", filename);
        
        if (!pipeline.add(file_sink)) {
            error("could not add file_sink");
        }
        
        mux = make_element("oggmux");
        if (!pipeline.add(mux)) {
            error("could not add oggmux to pipeline");
        }

        pipeline.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0);
        pipeline.set_state(Gst.State.NULL);
        link_for_export(mux);            

        file_updated(filename, 0);
    }
    
    void cancel() {
        play_state = PlayState.CANCEL_EXPORT;
        pipeline.set_state(Gst.State.NULL);
    }
    
    // TODO: Rework this
    public void complete() {
        pipeline.set_state(Gst.State.NULL);
    }
    
    protected virtual void do_null_state_export() {
        pre_export();
        if (!mux.link(file_sink)) {
            error("could not link mux and file_sink");
        }
        play_state = PlayState.PRE_EXPORT;
        pipeline.set_state(Gst.State.PAUSED);
    }
    
    void do_paused_state_export() {
        play_state = PlayState.EXPORTING;
              
        if (callback_id == 0)
            callback_id = Timeout.add(50, on_callback);
        
        pipeline.set_state(Gst.State.PLAYING);        
    }
    
    protected virtual void do_end_export(bool deleted) {
        if (deleted) {
            string str;
            file_sink.get("location", out str);
            GLib.FileUtils.remove(str);
        }
        link_for_playback(mux);
    }

    void end_export(bool deleted) {
        play_state = PlayState.STOPPED;
        do_end_export(deleted);

        pipeline.remove_many(mux, file_sink);
        
        callback_id = 0;
        pipeline.set_state(Gst.State.PAUSED);
        post_export();
    }

    protected virtual void link_for_export(Gst.Element mux) {
        capsfilter.unlink(audio_sink);
        capsfilter.set("caps", get_project_audio_export_caps());

        if (!pipeline.remove(audio_sink))
            error("couldn't remove for audio");

        get_export_sink();
        pipeline.add(export_sink);

        if (!capsfilter.link(export_sink)) {
            error("could not link capsfilter to export_sink");
        }
        
        if (!export_sink.link(mux)) {
            error("could not link export sink to mux");
        }
    }
    
    protected virtual void link_for_playback(Gst.Element mux) {
        export_sink.unlink(mux);
        capsfilter.unlink(export_sink);
        capsfilter.set("caps", get_project_audio_caps());

        if (!pipeline.remove(export_sink)) {
            error("could not remove export_sink");
        }

        if (!pipeline.add(audio_sink)) {
            error("could not add audio_sink to pipeline");
        }

        if (!capsfilter.link(audio_sink)) {
            error("could not link capsfilter to audio_sink");
        }
    }

    protected void get_export_sink() {
        export_sink = make_element("vorbisenc");
    }
    
    void on_eos(Gst.Bus bus, Gst.Message message) {
        if (play_state == PlayState.EXPORTING)
            pipeline.set_state(Gst.State.NULL);
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

    protected virtual bool do_state_change() {
        switch (play_state) {
            case PlayState.STOPPED:
                if (gst_state != Gst.State.PAUSED)
                    return false;
                go(position);
                return true;
            case PlayState.PRE_EXPORT_NULL:
                if (gst_state != Gst.State.NULL)
                    return false;
                do_null_state_export();
                return true;
            case PlayState.PRE_EXPORT:
                if (gst_state != Gst.State.PAUSED)
                    return false;
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
        }
        return false;
    }
    
    void on_load_complete(string? error) {
        loader = null;
        if (error != null) {
            clear();
            load_error(error);
        } else {
            // We do this here because there are problems with transitioning to the paused
            // state during an asynchronous load.  We wait until the loading is done, switch states,
            // and then, to get the image of the first frame, we set up a callback 
            // which seeks to position 0
           
            bus_init();
            pipeline.set_state(Gst.State.PAUSED);
        
            load_success();
        }
    }
    
    // Load a project file.  The load is asynchronous: it may continue after this method returns.
    // Any load error will be reported via the load_error signal, which may run either while this
    // method executes or afterward.
    public void load(string? fname) {
        if (fname == null) {
            bus_init();
            return;
        }
        
        if (loader != null) {
            load_error("already loading a project");
            return;
        }

        loader = new ProjectLoader(this);
        loader.load_complete += on_load_complete;
        loader.load(fname);
    }
    
    public void save(string? filename) {
        if (filename != null)
            set_name(filename);

        FileStream f = FileStream.open(project_file, "w");
        
        f.printf("<lombard version=\"%f\">\n", get_version());
        foreach (Track track in tracks) {
            track.save(f);
        }
        f.printf("</lombard>\n"); 
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
    
    public void on_importer_clip_complete(Model.ClipFetcher fetcher) {
        if (fetcher.error_string != null) {
            error_occurred(fetcher.error_string);         
        } else {
            fetcher_completion.complete(fetcher);
        }        
    }

    public void create_clip_fetcher(FetcherCompletion fetcher_completion, string filename) {
        Model.ClipFetcher fetcher = new Model.ClipFetcher(filename);
        this.fetcher_completion = fetcher_completion;
        fetcher.ready += on_fetcher_ready;
        pending.add(fetcher);
    }

    void on_fetcher_ready(Model.ClipFetcher fetcher) {
        pending.remove(fetcher);
        if (fetcher.error_string != null) {
            error_occurred(fetcher.error_string);         
        } else {
            fetcher_completion.complete(fetcher);
        }
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
    
    public Gst.Element get_audio_silence() {
        Gst.Element silence = make_element("audiotestsrc");
        silence.set("wave", 4);     // 4 is silence
        Gst.Caps audio_cap = get_project_audio_caps();
        foreach (Gst.Pad pad in silence.pads) {
            pad.set_caps(audio_cap);
        }
        return silence;
    }

    public abstract double get_version();
}

public class ProjectLoader {
    Model.Project project;

    string text;
    size_t text_len;
        
    bool loaded_file_header;
    Track track;
    string error;

    Gee.HashSet<ClipFetcher> pending = new Gee.HashSet<ClipFetcher>();
    
    public signal void load_complete(string? error);
    
    public ProjectLoader(Model.Project project) {
        this.project = project;
    }
    
    void parse(MarkupParser parser) {
        MarkupParseContext context =
            new MarkupParseContext(parser, (MarkupParseFlags) 0, this, null);
            
        try {
            context.parse(text, (long) text_len);
        } catch (MarkupError e) {
            error = e.message;
        }
    }
    
    void xml_start_element(GLib.MarkupParseContext c, string name, 
                           string[] attr_names, string[] attr_values) throws MarkupError {
        if (name == "track") {
            if (attr_names.length != 1 || attr_names[0] != "name")
                throw new MarkupError.INVALID_CONTENT("expected name attribute");
            switch (attr_values[0]) {
                case "video":
                    track = project.find_video_track();
                    break;
                case "audio":
                    track = project.find_audio_track();
                    break;
                default:
                    throw new MarkupError.INVALID_CONTENT("unknown track");
            }
        } else if (name == "clip") {
            string filename = null;
            string clip_name = null;
            int64 start = 0;
            int64 media_start = 0;
            int64 duration = 0;
    
            for (int i = 0; i < attr_names.length; i++) {
                string val = attr_values[i];
                switch (attr_names[i]) {
                    case "filename":
                        filename = val;
                        break;
                    case "name":
                        clip_name = val;
                        break;
                    case "start":
                        start = val.to_int64();
                        break;
                    case "media-start":
                        media_start = val.to_int64();
                        break;
                    case "duration":
                        duration = val.to_int64();
                        break;
                    default:
                        throw new MarkupError.INVALID_CONTENT("Unknown attribute %s!".printf(val));
                }
            }

            ClipFile clipfile = project.find_clipfile(filename);
            if (clipfile == null)
                GLib.error("clipfile not found");
            
            if (clip_name == null)
                clip_name = isolate_filename(clipfile.filename);
            Clip clip = new Clip(clipfile, 
                                 track == project.find_video_track() ? 
                                    MediaType.VIDEO : MediaType.AUDIO, 
                                 clip_name, 0, media_start, duration);
            
            if (track == null)
                throw new MarkupError.INVALID_CONTENT("clip outside track element");
            track.append_at_time(clip, start);
        }
    }
    
    void fetcher_callback(ClipFetcher f) {
        if (f.error_string != null && error == null)
            error = "%s: %s".printf(f.clipfile.filename, f.error_string);
        else project.add_clipfile(f.clipfile);
        pending.remove(f);
        
        if (pending.size == 0) {
            if (error == null) {
                // Now that all ClipFetchers have completed, parse the XML again and
                // create Clip objects.
                MarkupParser parser = { xml_start_element, null, null, null };
                parse(parser);
            }
            load_complete(error);
        }
    }
    
    void xml_start_clipfile(GLib.MarkupParseContext c, string name, 
                            string[] attr_names, string[] attr_values) throws MarkupError {
        
        if (!loaded_file_header) {
            if (name != "lombard")
                throw new MarkupError.INVALID_CONTENT("Missing header!");
                
            if (attr_names.length < 1 ||
                attr_names[0] != "version") {
                throw new MarkupError.INVALID_CONTENT("Corrupted header!");
            }
         
            if (project.get_version() < attr_values[0].to_double())
                throw new MarkupError.INVALID_CONTENT(
                    "Version mismatch! (File Version: %f, App Version: %f)",
                    project.get_version(), attr_values[0].to_double());
                    
            loaded_file_header = true;
        } else if (name == "clip")
            for (int i = 0; i < attr_names.length; i++)
                if (attr_names[i] == "filename") {
                    string filename = attr_values[i];
                    foreach (ClipFetcher fetcher in pending)
                        if (fetcher.get_filename() == filename)
                            return;     // we're already fetching this clipfile

                    ClipFetcher fetcher = new ClipFetcher(filename);
                    pending.add(fetcher);
                    fetcher.ready += fetcher_callback;
                    return;
                }
    }
    
    public void load(string filename) {
        try {
            FileUtils.get_contents(filename, out text, out text_len);
        } catch (FileError e) {
            load_complete(e.message);
            return;
        }

        project.clear();
        project.set_name(filename);
        
        // Parse the XML and start a ClipFetcher for each clip referenced.
        MarkupParser parser = { xml_start_clipfile, null, null, null };
        parse(parser);
        
        if (error != null || pending.size == 0)
            load_complete(error);
    }
}
}

