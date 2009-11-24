/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace Model {
public class MediaLoaderHandler : LoaderHandler {
    protected weak Project the_project;
    protected Track current_track;
    
    Gee.ArrayList<ClipFetcher> clipfetchers = new Gee.ArrayList<ClipFetcher>();
    int num_clipfiles_complete;
    
    public MediaLoaderHandler(Project the_project) {
        this.the_project = the_project;
        current_track = null;
    }
    
    public override bool commit_marina(string[] attr_names, string[] attr_values) {
        int number_of_attributes = attr_names.length;
        if (number_of_attributes != 1 ||
            attr_names[0] != "version") {
            load_error("Missing version information");
            return false;
        }
        
        if (the_project.get_file_version() < attr_values[0].to_int()) {
            load_error("Version mismatch! (File Version: %d, App Version: %d)".printf(
                the_project.get_file_version(), attr_values[0].to_int()));
            return false;
        }
        
        num_clipfiles_complete = 0;
        return true;
    }
    
    public override bool commit_library(string[] attr_names, string[] attr_values) {
        // We return true since framerate is an optional parameter
        if (attr_names.length != 1)
            return true;
        
        if (attr_names[0] != "framerate") {
            load_error("Missing framerate tag");
            return false;
        }
        
        string[] arr = attr_values[0].split("/");
        if (arr.length != 2) {
            load_error("Invalid framerate attribute");
            return false;
        }
            
        the_project.set_default_framerate(Fraction(arr[0].to_int(), arr[1].to_int()));
        return true;
    }
    
    public override bool commit_track(string[] attr_names, string[] attr_values) {
        assert(current_track == null);
        
        int number_of_attributes = attr_names.length;
        string? name = null;
        string? type = null;
        for (int i = 0; i < number_of_attributes; ++i) {
            switch(attr_names[i]) {
                case "type":
                    type = attr_values[i];
                    break;
                case "name":
                    name = attr_values[i];
                    break;
                default:
                    break;
            }
        }
        
        if (name == null) {
            load_error("Missing track name");
            return false;
        }
        
        if (type == null) {
            load_error("Missing track type");
            return false;
        }
        
        if (type == "audio") {
            AudioTrack audio_track = new AudioTrack(the_project, name);
            current_track = audio_track;
            
            for (int i = 0; i < number_of_attributes; ++i) {
                switch(attr_names[i]) {
                    case "panorama":
                        audio_track._set_pan(attr_values[i].to_double());
                        break;
                    case "volume":
                        audio_track._set_volume(attr_values[i].to_double());
                        break;
                    case "channels":
                        audio_track.set_default_num_channels(attr_values[i].to_int());
                        break;
                    default:
                        break;
                }
            }
            
            the_project.add_track(current_track);

            return true;
        } else if (type == "video") {
            current_track = new VideoTrack(the_project);
            the_project.add_track(current_track);
        }
        
        return base.commit_track(attr_names, attr_values);;
    }
    
    public override void leave_track() {
        assert(current_track != null);
        current_track = null;
    }
    
    public override bool commit_clip(string[] attr_names, string[] attr_values) {
        assert(current_track != null);
        
        int number_of_attributes = attr_names.length;
        int id = -1;
        string? clip_name = null;
        int64 start = -1;
        int64 media_start = -1;
        int64 duration = -1;
        for (int i = 0; i < number_of_attributes; i++) {
        switch (attr_names[i]) {
            case "id":
                id = attr_values[i].to_int();
                break;
            case "name":
                clip_name = attr_values[i];
                break;
            case "start":
                start = attr_values[i].to_int64();
                break;
            case "media-start":
                media_start = attr_values[i].to_int64();
                break;
            case "duration":
                duration = attr_values[i].to_int64();
                break;
            default:
                // TODO: we need a way to deal with orphaned attributes, for now, reject the file
                load_error("Unknown attribute %s".printf(attr_names[i]));
                return false;
            }
        }
        
        if (id == -1) {
            load_error("missing clip id");
            return false;
        }
        
        if (clip_name == null) {
            load_error("missing clip_name");
            return false;
        }
        
        if (start == -1) {
            load_error("missing start time");
            return false;
        }
        
        if (media_start == -1) {
            load_error("missing media_start");
            return false;
        }
        
        if (duration == -1) {
            load_error("missing duration");
            return false;
        }

        if (id >= clipfetchers.size) {
            load_error("clip file id %s was not loaded".printf(clip_name));
            return false;
        }
        
        Clip clip = new Clip(clipfetchers[id].clipfile, current_track.media_type(), clip_name, 
            start, media_start, duration, false);
        current_track.add(clip, start);
        return true;
    }
    
    void fetcher_ready(ClipFetcher f) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "fetcher_ready");
        if (f.error_string != null)
            load_error("%s: %s".printf(f.clipfile.filename, f.error_string));

        the_project.add_clipfile(f.clipfile);
        
        num_clipfiles_complete++;
        if (num_clipfiles_complete == clipfetchers.size)
            complete();
    }
    
    public override bool commit_clipfile(string[] attr_names, string[] attr_values) {
        string filename = null;
        int id = -1;

        for (int i = 0; i < attr_names.length; i++) {
            if (attr_names[i] == "filename") {
                filename = attr_values[i];
            } else if (attr_names[i] == "id") {
                id = attr_values[i].to_int();
            }
        }
        
        if (filename == null)
            load_error("Invalid clipfile filename!");
        if (id < 0)
            load_error("Invalid clipfile id!");     
        
        ClipFetcher fetcher = new ClipFetcher(filename);
        fetcher.ready += fetcher_ready;
        clipfetchers.insert(id, fetcher);        
        
        return true;
    }
    
    public override void leave_library() {
        if (clipfetchers.size == 0)
            complete();
    }
}

// TODO: Project derives from MultiFileProgress interface for exporting
// Move exporting work to separate object similar to import.    
public abstract class Project : Object {

    public const string FILLMORE_FILE_EXTENSION = "fill";
    public const string FILLMORE_FILE_FILTER = "*." + FILLMORE_FILE_EXTENSION;   
    public const string LOMBARD_FILE_EXTENSION = "lom";
    public const string LOMBARD_FILE_FILTER = "*." + LOMBARD_FILE_EXTENSION;

    public Gee.ArrayList<Track> tracks = new Gee.ArrayList<Track>();
    public Gee.ArrayList<Track> inactive_tracks = new Gee.ArrayList<Track>();
    Gee.HashSet<ClipFetcher> pending = new Gee.HashSet<ClipFetcher>();
    Gee.ArrayList<ClipFile> clipfiles = new Gee.ArrayList<ClipFile>();
    // TODO: media_engine is a member of project only temporarily.  It will be
    // less work to move it to fillmore/lombard once we have a transport class.
    public View.MediaEngine media_engine;

    public string project_file;
    public ProjectLoader loader;

    FetcherCompletion fetcher_completion;
    public UndoManager undo_manager;
    public LibraryImporter importer;

    public Fraction default_framerate;
    
    /* TODO:
        * This can't be const since the Vala compiler
        * (0.7.7) crashes if we try to make it a const.
        * I've filed a bug with the Vala bugzilla for this.
    */    
    public static Fraction INVALID_FRAME_RATE = Fraction(-1, 1);

    public signal void playstate_changed(PlayState playstate);
    
    public signal void name_changed(string? project_file);
    public signal void load_error(string error);
    public virtual signal void load_complete() {
    
    }

    public signal void closed();
    
    public signal void track_added(Track track);
    public signal void track_removed(Track track);
    public signal void error_occurred(string major_message, string? minor_message);
    
    public signal void clipfile_added(ClipFile c);
    public signal void cleared();

    public abstract TimeCode get_clip_time(ClipFile f);

    public Project(string? filename, bool include_video) {
        undo_manager = new UndoManager();
        project_file = filename;
        media_engine = new View.MediaEngine(this, include_video);
        track_added += media_engine.on_track_added;
        media_engine.playstate_changed += on_playstate_changed;
        
        set_default_framerate(INVALID_FRAME_RATE);
    }
    
    public void on_playstate_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_playstate_changed");
        switch (media_engine.play_state) {
            case PlayState.STOPPED:
                ClearTrackMeters();
                break;
            case PlayState.CLOSED:
                closed();
                break;
        }
        playstate_changed(media_engine.play_state);
    }
    
    public ClipFile? get_clipfile(int index) {
        if (index < 0 ||
            index >= clipfiles.size)
            return null;
        return clipfiles[index];
    }
    
    public int get_clipfile_index(ClipFile find) {
        int i = 0;
        foreach (ClipFile f in clipfiles) {
            if (f == find)
                return i;
            i++;
        }
        return -1;
    }
    
    public Track? track_from_clip(Clip clip) {
        foreach (Track track in tracks) {
            foreach (Clip match in track.clips) {
                if (match == clip) {
                    return track;
                }
            }
        }
        return null;
    }

    public void print_graph(Gst.Bin bin, string file_name) {
        Gst.debug_bin_to_dot_file_with_ts(bin, Gst.DebugGraphDetails.ALL, file_name);
    }

    public int64 get_length() {
        int64 max = 0;
        foreach (Track track in tracks) {
            max = int64.max(max, track.get_length());
        }
        return max;
    }
    
    public int64 snap_clip(Clip c, int64 span) {
        foreach (Track track in tracks) {
            int64 new_start = track.snap_clip(c, span);
            if (new_start != c.start) {
                return new_start;
            }
        }
        return c.start;
    }
    
    public void snap_coord(out int64 coord, int64 span) {
        foreach (Track track in tracks) {
            if (track.snap_coord(out coord, span)) {
                break;
            }
        }
    }
    
    Gap get_gap_intersection(Gap gap) {
        Gap intersection = gap;
        
        foreach (Track track in tracks) {
            intersection = intersection.intersect(track.find_first_gap(intersection.start));
        }
        
        return intersection;
    }
    
    public bool can_delete_gap(Gap gap) {
        Gap intersection = get_gap_intersection(gap);        
        return !intersection.is_empty();
    }
    
    public void delete_gap(Gap gap) {
        Gap intersection = get_gap_intersection(gap);
        assert(!intersection.is_empty());

        foreach (Track track in tracks) {
            track.delete_gap(intersection);
        }
    }

    protected virtual void do_append(Track track, ClipFile clipfile, string name, 
        int64 insert_time) {
        switch(track.media_type()) {
            case MediaType.AUDIO:
                if (clipfile.audio_caps == null) {
                    return;
                }
                break;
            case MediaType.VIDEO:
                if (clipfile.video_caps == null) {
                    return;
                }
            break;
        }
        
        if (clipfile.audio_caps != null) {
            Clip clip = new Clip(clipfile, track.media_type(), name, 0, 0, clipfile.length, false);
            track.append_at_time(clip, insert_time);
        }
    }
    
    public void append(Track track, ClipFile clipfile) {
        string name = isolate_filename(clipfile.filename);
        int64 insert_time = 0;
        
        foreach (Track temp_track in tracks) {
            insert_time = int64.max(insert_time, temp_track.get_length());
        }
        do_append(track, clipfile, name, insert_time);        
    }

    public void on_clip_removed(Track t, Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_removed");
        reseek();
    }

    public void split_at_playhead() {
        undo_manager.start_transaction();
        foreach (Track track in tracks) {
            if (track.get_clip_by_position(transport_get_position()) != null) {
                track.split_at(transport_get_position());
            }
        }
        undo_manager.end_transaction();
    }
    
    public void join_at_playhead() {
        undo_manager.start_transaction();
        foreach (Track track in tracks) {
            track.join(transport_get_position());
        }
        undo_manager.end_transaction();
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
            Clip clip = track.get_clip_by_position(transport_get_position());
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
        left = (transport_get_position() - first_clip.start < first_clip.duration / 2);
        return true;
    }
    
    public void trim_to_playhead() {
        bool left;
        if (!can_trim(out left)) {
            return;
        }

        Clip first_clip = null;
        undo_manager.start_transaction();
        foreach (Track track in tracks) {
            Clip clip = track.get_clip_by_position(transport_get_position());
            if (clip != null) {
                int64 delta;
                if (left) {
                    delta = transport_get_position() - clip.start;
                } else {
                    delta = transport_get_position() - clip.end;
                }
                track.trim(clip, delta, left ? Gdk.WindowEdge.WEST : Gdk.WindowEdge.EAST);
            }
        }
        undo_manager.end_transaction();
            
        if (left && first_clip != null) {
            transport_go(first_clip.start);
        }
    }
    
    public void transport_go(int64 position) {
        media_engine.go(position);
    }

    public bool transport_is_playing() {
        return media_engine.playing;
    }

    public bool transport_is_recording() {
        return media_engine.play_state == PlayState.PRE_RECORD ||
               media_engine.play_state == PlayState.RECORDING;
    }
    
    public bool playhead_on_clip() {
        foreach (Track track in tracks) {
            if (track.get_clip_by_position(transport_get_position()) != null) {
                return true;
            }
        }
        return false;
    }
    
    public bool playhead_on_contiguous_clip() {
        foreach (Track track in tracks) {
            if (track.are_contiguous_clips(transport_get_position())) {
                return true;
            }
        }
        return false;
    }
    
    public virtual void add_track(Track track) {
        track.clip_removed += on_clip_removed;
        track.error_occurred += on_error_occurred;
        tracks.add(track);
        track_added(track);
    }
    
    public void add_inactive_track(Track track) {
        track.hide();
        inactive_tracks.add(track);
    }
    
    public void remove_track(Track track) {
        media_engine.pipeline.set_state(Gst.State.NULL);
        tracks.remove(track);
        track_removed(track);
    }

    public virtual void add_clipfile(ClipFile clipfile) {
        clipfiles.add(clipfile);
    }
    
    public bool clipfile_on_track(string filename) {
        ClipFile cf = find_clipfile(filename);
        
        foreach (Track t in tracks) {
            foreach (Clip c in t.clips) {
                if (c.clipfile == cf)
                    return true;
            }
        }
        
        foreach (Track t in inactive_tracks) {
            foreach (Clip c in t.clips) {
                if (c.clipfile == cf)
                    return true;
            }
        }
        
        return false;
    }
    
    void delete_clipfile_from_tracks(ClipFile cf) {
        foreach (Track t in tracks) {
            for (int i = 0; i < t.clips.size; i++) {
                if (t.clips[i].clipfile == cf) {
                    t.delete_clip(t.clips[i]);
                    i --;
                }
            }
        }
        
        foreach (Track t in inactive_tracks) {
            for (int i = 0; i < t.clips.size; i++) {
                if (t.clips[i].clipfile == cf) {
                    t.delete_clip(t.clips[i]);
                    i --;
                }
            }
        }
    }
    
    public void _remove_clipfile(ClipFile cf) {
        clipfiles.remove(cf);
    }
    
    public void remove_clipfile(string filename) {
        ClipFile cf = find_clipfile(filename);
        if (cf != null) {
            undo_manager.start_transaction();
            
            delete_clipfile_from_tracks(cf);
    
            Command clipfile_delete = new ClipFileDeleteCommand(this, cf);
            do_command(clipfile_delete);
                
            undo_manager.end_transaction();
        }
    }
    
    public ClipFile? find_clipfile(string filename) {
        foreach (ClipFile cf in clipfiles)
            if (cf.filename == filename)
                return cf;
        return null;
    }

    public void reseek() { transport_go(transport_get_position()); }

    public void go_start() { transport_go(0); }
  
    public void go_end() { transport_go(get_length()); }
    
    public void go_previous() {
        int64 start_pos = transport_get_position();
        
        // If we're currently playing, we jump to the previous clip if we're within the first
        // second of the current clip.
        if (transport_is_playing())
            start_pos -= 1 * Gst.SECOND;
        
        int64 new_position = 0;
        foreach (Track track in tracks) {
            new_position = int64.max(new_position, track.previous_edit(start_pos));
        }
        transport_go(new_position);
    }
    
    public void go_next() {
        int64 new_position = 0;
        foreach (Track track in tracks) {
            if (track.get_length() > transport_get_position()) {
                if (new_position != 0) {
                    new_position = int64.min(new_position, track.next_edit(transport_get_position()));
                } else {
                    new_position = track.next_edit(transport_get_position());
                }
            }
        }
        transport_go(new_position);
    }
    
    public int64 transport_get_position() {
        return media_engine.position;
    }
    
    public void set_name(string? filename) {
        this.project_file = filename;
        name_changed(filename);
    }
    
    public void set_default_framerate(Fraction rate) {
        default_framerate = rate;
    }
    
    public string get_file_display_name() {
        if (project_file == null) {
            return "Unsaved Project - %s".printf(get_app_name());
        }
        else {
            string dir = Path.get_dirname(project_file);
            string name = Path.get_basename(project_file);
            string home_path = GLib.Environment.get_home_dir();

            if (dir == ".")
                dir = GLib.Environment.get_current_dir();

            if (dir.has_prefix(home_path))
                dir = "~" + dir.substring(home_path.length);
            return "%s (%s) - %s".printf(name, dir, get_app_name());
        }
    }

    public void clear() {
        media_engine.set_gst_state(Gst.State.NULL);

        foreach (Track track in tracks) {
            track.delete_all_clips();
            track.track_removed(track);
            track_removed(track);
        }

        tracks.clear();
        
        clipfiles.clear();
        set_name(null);
        cleared();
    }
        
    public bool can_export() {
        foreach (Track track in tracks) {
            if (track.get_length() > 0) {
                return true;
            }
        }
        return false;
    }
    
    public void on_load_started(string filename) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_started");
        project_file = filename;
    }
    
    void on_load_error(string error) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_error");
        load_error(error);
    }
    
    void on_load_complete() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_complete");
        undo_manager.reset();
        
        set_name(project_file);
        
        load_complete(); 
    }
    
    // Load a project file.  The load is asynchronous: it may continue after this method returns.
    // Any load error will be reported via the load_error signal, which may run either while this
    // method executes or afterward.
    public void load(string? fname) {
        emit(this, Facility.LOADING, Level.INFO, "loading project");
        clear();
        set_name(null);
        if (fname == null) {
            return;
        }
        
        loader = new ProjectLoader(new MediaLoaderHandler(this), fname);
        
        loader.load_started += on_load_started;
        loader.load_error += on_load_error;
        loader.load_complete += on_load_complete;
        loader.load_complete += media_engine.on_load_complete;
        media_engine.play_state = PlayState.LOADING;
        media_engine.pipeline.set_state(Gst.State.NULL);
        loader.load();
    }
    
    public void on_error_occurred(string major_error, string? minor_error) {
        error_occurred(major_error, minor_error);
    }
    
    public int get_file_version() {
        return 3;
    }
    
    public void save_library(FileStream f) {
        f.printf("  <library");
        
        Fraction r = default_framerate;
        
        foreach (Track t in tracks) {
            if (t.media_type () == MediaType.VIDEO) {
                VideoTrack video_track = t as VideoTrack;
                if (video_track.get_framerate(out r))
                    break;
            }
        }
        if (!r.equal(INVALID_FRAME_RATE))
            f.printf(" framerate=\"%d/%d\"", r.numerator, 
                                             r.denominator);
        f.printf(">\n");
        
        for (int i = 0; i < clipfiles.size; i++) {
            f.printf("    <clipfile filename=\"%s\" id=\"%d\"/>\n", clipfiles[i].filename, i);
        }
        
        f.printf("  </library>\n");
    }
    
    public void save(string? filename) {
        if (filename != null)
            set_name(filename);

        FileStream f = FileStream.open(project_file, "w");
        
        f.printf("<marina version=\"%d\">\n", get_file_version());
        
        save_library(f);
        
        f.printf("  <tracks>\n");
        foreach (Track track in tracks) {
            track.save(f);
        }
        
        foreach (Track track in inactive_tracks) {
            track.save(f);
        }
        f.printf("  </tracks>\n");
        
        f.printf("</marina>\n");
        // TODO: clean up responsibility between dirty and undo
        undo_manager.mark_clean();
    }

    public void close() {
        media_engine.close();
    }
    
    public void on_importer_clip_complete(ClipFetcher fetcher) {
        if (fetcher.error_string != null) {
            error_occurred("Error importing clip", fetcher.error_string);         
        } else {
            fetcher_completion.complete(fetcher);
        }        
    }

    public void create_clip_fetcher(FetcherCompletion fetcher_completion, string filename) {
        ClipFetcher fetcher = new ClipFetcher(filename);
        this.fetcher_completion = fetcher_completion;
        fetcher.ready += on_fetcher_ready;
        pending.add(fetcher);
    }

    // TODO: We should be using Library importer rather than this mechanism for fillmore
    void on_fetcher_ready(ClipFetcher fetcher) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_fetcher_ready");
        pending.remove(fetcher);
        if (fetcher.error_string != null) {
            emit(this, Facility.DEVELOPER_WARNINGS, Level.INFO, fetcher.error_string);
            error_occurred("Error retrieving clip", fetcher.error_string);         
        } else {
            if (get_clipfile_index(fetcher.clipfile) == -1)
                add_clipfile(fetcher.clipfile);
            fetcher_completion.complete(fetcher);
        }
    }
    
    public bool is_project_extension(string filename) {
        string extension = get_file_extension(filename);
        return extension == LOMBARD_FILE_EXTENSION || extension == FILLMORE_FILE_EXTENSION;
    }

    public void do_command(Command the_command) {
        undo_manager.do_command(the_command);
    }

    public void undo() {
        undo_manager.undo();
    }

    void ClearTrackMeters() {
        foreach (Track track in tracks) {
            AudioTrack audio_track = track as AudioTrack;
            if (audio_track != null) {
                audio_track.level_changed(-100, -100);
            }
        }
    }

    public void create_clip_importer(Model.Track? track, bool timeline_add) {
        if (timeline_add) {
            assert(track != null);
            importer = new Model.TimelineImporter(track, this);
        } else {
            importer = new Model.LibraryImporter(this);
        }
    }

    public abstract double get_version();
    public abstract string get_app_name();

}
}

