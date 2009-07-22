/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */


namespace Model {
class Project {
    public Gst.Pipeline pipeline;

    public Gee.ArrayList<Track> tracks = new Gee.ArrayList<Track>();
    ClipFile[] clipfiles = new ClipFile[0];

    public string project_file;
    public ProjectLoader loader;

    public bool playing;
    public int64 position;  // current play position in ns
    uint callback_id;
    
    public signal void position_changed();
    
    public signal void name_changed(string? project_file);
    public signal void load_error(string error);
    public signal void load_success();
    
    public Project() {
        pipeline = new Gst.Pipeline("pipeline");
        Gst.Bus bus = pipeline.get_bus();

        bus.add_signal_watch();
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;
    }
    
    void on_warning(Gst.Bus bus, Gst.Message message) {
        Error error;
        string text;
        message.parse_warning(out error, out text);
        warning(text);
    }
    
    void on_error(Gst.Bus bus, Gst.Message message) {
        Error error;
        string text;
        message.parse_error(out error, out text);
        warning(text);
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
        tracks.add(track);
    }
    
    public void add_clipfile(ClipFile clipfile) {
        clipfiles += clipfile;
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
        if (!playing) {
            callback_id = 0;
            return false;
        }

        Gst.Format format = Gst.Format.TIME;
        int64 time;
        if (pipeline.query_position(ref format, out time) && format == Gst.Format.TIME) {
            position = time;
            
            if (position >= get_length()) {
                go(get_length());
                pause();
            }
            position_changed();
        }
        return true;
    }
    
    public void play() {
        if (playing)
            return;
            
        pipeline.set_state(Gst.State.PLAYING);
        if (callback_id == 0)
            callback_id = Timeout.add(50, on_callback);
        playing = true;
    }
    
    public void pause() {
        if (!playing)
            return;
            
        pipeline.set_state(Gst.State.PAUSED);
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
        clipfiles = new ClipFile[0];
        set_name(null);
    }
    
    void on_state_change(Gst.Bus bus, Gst.Message message) {
        if (loader == null)
            return;
        if (message.src != pipeline)
            return;
            
        Gst.State old_state;
        Gst.State new_state;
        Gst.State pending;
        
        message.parse_state_changed(out old_state, out new_state, out pending);
        if (new_state != Gst.State.PAUSED)
            return;
        go (0);
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
            Gst.Bus bus = pipeline.get_bus();
            
            bus.add_signal_watch();
            bus.message["state-changed"] += on_state_change;
            pipeline.set_state(Gst.State.PAUSED);        
        
            load_success();
        }
    }
    
    // Load a project file.  The load is asynchronous: it may continue after this method returns.
    // Any load error will be reported via the load_error signal, which may run either while this
    // method executes or afterward.
    public void load(string fname) {
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
        
        f.printf("<lombard version=\"%f\">\n", App.VERSION);
        foreach (Track track in tracks) {
            track.save(f);
        }
        f.printf("</lombard>\n"); 
    }
}

class ProjectLoader {
    Model.Project project;

    string text;
    ulong text_len;
        
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
         
            if (App.VERSION < attr_values[0].to_double())
                throw new MarkupError.INVALID_CONTENT(
                    "Version mismatch! (File Version: %f, App Version: %f)",
                    App.VERSION, attr_values[0].to_double());
                    
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
