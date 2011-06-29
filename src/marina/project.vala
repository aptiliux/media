/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

extern const string _VERSION;

namespace Model {
public class MediaLoaderHandler : LoaderHandler {
    protected weak Project the_project;
    protected Track current_track;

    Gee.ArrayList<ClipFetcher> clipfetchers = new Gee.ArrayList<ClipFetcher>();
    int num_mediafiles_complete;

    public MediaLoaderHandler(Project the_project) {
        this.the_project = the_project;
        current_track = null;
    }

    public override bool commit_marina(string[] attr_names, string[] attr_values) {
        int number_of_attributes = attr_names.length;
        if (number_of_attributes != 1 ||
            attr_names[0] != "version") {
            load_error(ErrorClass.LoadFailure, "Missing version information");
            return false;
        }

        if (the_project.get_file_version() < int.parse(attr_values[0])) {
            load_error(ErrorClass.LoadFailure, 
                "Version mismatch! (File Version: %d, App Version: %d)".printf(
                    the_project.get_file_version(), int.parse(attr_values[0]) ));
            return false;
        }

        num_mediafiles_complete = 0;
        return true;
    }

    public override bool commit_library(string[] attr_names, string[] attr_values) {
        // We return true since framerate is an optional parameter
        if (attr_names.length != 1)
            return true;

        if (attr_names[0] != "framerate") {
            load_error(ErrorClass.FormatError, "Missing framerate tag");
            return false;
        }

        string[] arr = attr_values[0].split("/");
        if (arr.length != 2) {
            load_error(ErrorClass.FormatError, "Invalid framerate attribute");
            return false;
        }

        the_project.set_default_framerate(Fraction(int.parse(arr[0]), int.parse(arr[1])));
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
            load_error(ErrorClass.FormatError, "Missing track name");
            return false;
        }

        if (type == null) {
            load_error(ErrorClass.FormatError, "Missing track type");
            return false;
        }

        if (type == "audio") {
            AudioTrack audio_track = new AudioTrack(the_project, name);
            current_track = audio_track;
            the_project.add_track(current_track);

            for (int i = 0; i < number_of_attributes; ++i) {
                switch(attr_names[i]) {
                    case "panorama":
                        audio_track._set_pan(double.parse(attr_values[i]));
                        break;
                    case "volume":
                        audio_track._set_volume(double.parse(attr_values[i]));
                        break;
                    case "channels":
                        audio_track.set_default_num_channels(int.parse(attr_values[i]));
                        break;
                    case "solo":
                        audio_track.solo = bool.parse(attr_values[i]);
                        break;
                    case "mute":
                        audio_track.mute = bool.parse(attr_values[i]);
                        break;
                    default:
                        break;
                }
            }
            return true;
        } else if (type == "video") {
            current_track = new VideoTrack(the_project);
            the_project.add_track(current_track);
        }

        return base.commit_track(attr_names, attr_values);
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
                id = int.parse(attr_values[i]);
                break;
            case "name":
                clip_name = attr_values[i];
                break;
            case "start":
                start = int64.parse(attr_values[i]);
                break;
            case "media-start":
                media_start = int64.parse(attr_values[i]);
                break;
            case "duration":
                duration = int64.parse(attr_values[i]);
                break;
            default:
                // TODO: we need a way to deal with orphaned attributes, for now, reject the file
                load_error(ErrorClass.FormatError, "Unknown attribute %s".printf(attr_names[i]));
                return false;
            }
        }

        if (id == -1) {
            load_error(ErrorClass.FormatError, "missing clip id");
            return false;
        }

        if (clip_name == null) {
            load_error(ErrorClass.FormatError, "missing clip_name");
            return false;
        }

        if (start == -1) {
            load_error(ErrorClass.FormatError, "missing start time");
            return false;
        }

        if (media_start == -1) {
            load_error(ErrorClass.FormatError, "missing media_start");
            return false;
        }

        if (duration == -1) {
            load_error(ErrorClass.FormatError, "missing duration");
            return false;
        }

        if (id >= clipfetchers.size) {
            load_error(ErrorClass.FormatError, "clip file id %s was not loaded".printf(clip_name));
            return false;
        }

        Clip clip = new Clip(clipfetchers[id].mediafile, current_track.media_type(), clip_name, 
            start, media_start, duration, false);
        current_track.add(clip, start, false);
        return true;
    }

    void fetcher_ready(Fetcher f) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "fetcher_ready");
        if (f.error_string != null) {
            load_error(ErrorClass.MissingFiles, "Could not load %s.".printf(f.mediafile.filename));
            warning("Could not load %s: %s", f.mediafile.filename, f.error_string);
        }
        the_project.add_mediafile(f.mediafile);
        num_mediafiles_complete++;
        if (num_mediafiles_complete == clipfetchers.size) {
            complete();
        }
    }

    public override bool commit_mediafile(string[] attr_names, string[] attr_values) {
        string filename = null;
        int id = -1;

        for (int i = 0; i < attr_names.length; i++) {
            if (attr_names[i] == "filename") {
                filename = attr_values[i];
            } else if (attr_names[i] == "id") {
                id = int.parse(attr_values[i]);
            }
        }

        if (filename == null) {
            load_error(ErrorClass.FormatError, "Invalid clipfile filename");
            return false;
        }

        if (id < 0) {
            load_error(ErrorClass.FormatError, "Invalid clipfile id");
            return false;
        }

        try {
            ClipFetcher fetcher = new ClipFetcher(filename);
            fetcher.ready.connect(fetcher_ready);
            clipfetchers.insert(id, fetcher);
        } catch (Error e) {
            load_error(ErrorClass.MissingFiles, e.message);
            return false;
        }
        return true;
    }

    public override bool commit_tempo_entry(string[] attr_names, string[] attr_values) {
        if (attr_names[0] != "tempo") {
            load_error(ErrorClass.FormatError, "Invalid attribute on tempo entry");
            return false;
        }

        the_project._set_bpm(int.parse(attr_values[0]));
        return true;
    }

    public override bool commit_time_signature_entry(string[] attr_names, string[] attr_values) {
        if (attr_names[0] != "signature") {
            load_error(ErrorClass.FormatError, "Invalid attribute on time signature");
            return false;
        }

        the_project._set_time_signature(Fraction.from_string(attr_values[0]));
        return true;
    }

    public override bool commit_click(string[] attr_names, string[] attr_values) {
        for (int i = 0; i < attr_names.length; ++i) {
            switch (attr_names[i]) {
                case "on_play":
                    the_project.click_during_play = attr_values[i] == "true";
                break;
                case "on_record":
                    the_project.click_during_record = attr_values[i] == "true";
                break;
                case "volume":
                    the_project.click_volume = double.parse(attr_values[i]);
                break;
                default:
                    load_error(ErrorClass.FormatError, 
                        "unknown attribute for click '%s'".printf(attr_names[i]));
                    return false;
            }
        }
        return true;
    }

    public override bool commit_library_preference(string[] attr_names, string[] attr_values) {
        for (int i = 0; i < attr_names.length; ++i) {
            switch (attr_names[i]) {
                case "width":
                    the_project.library_width = int.parse(attr_values[i]);
                break;
                case "visible":
                    the_project.library_visible = attr_values[i] == "true";
                break;
                default:
                    load_error(ErrorClass.FormatError, 
                        "unknown attribute for library '%s'".printf(attr_names[i]));
                    return false;
            }
        }
        return true;
    }

    public override void leave_library() {
        if (clipfetchers.size == 0)
            complete();
    }
}

public abstract class Project : TempoInformation, Object {
    public const string FILLMORE_FILE_EXTENSION = "fill";
    public const string FILLMORE_FILE_FILTER = "*." + FILLMORE_FILE_EXTENSION;   
    public const string LOMBARD_FILE_EXTENSION = "lom";
    public const string LOMBARD_FILE_FILTER = "*." + LOMBARD_FILE_EXTENSION;

    const string license = """
%s is free software; you can redistribute it and/or modify it under the 
terms of the GNU Lesser General Public License as published by the Free 
Software Foundation; either version 2.1 of the License, or (at your option) 
any later version.

%s is distributed in the hope that it will be useful, but WITHOUT 
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for 
more details.

You should have received a copy of the GNU Lesser General Public License 
along with %s; if not, write to the Free Software Foundation, Inc., 
51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
""";

    public const string[] authors = { 
        "Robert Powell <rob@yorba.org>",
        "Adam Dingle <adam@yorba.org>",
        "Andrew O'Mahony <andrew.omahony@att.net>",
        null
    };

    public Gee.ArrayList<Track> tracks = new Gee.ArrayList<Track>();
    public Gee.ArrayList<Track> inactive_tracks = new Gee.ArrayList<Track>();
    Gee.HashSet<ClipFetcher> pending = new Gee.HashSet<ClipFetcher>();
    Gee.ArrayList<ThumbnailFetcher> pending_thumbs = new Gee.ArrayList<ThumbnailFetcher>();
    protected Gee.ArrayList<MediaFile> mediafiles = new Gee.ArrayList<MediaFile>();
    // TODO: media_engine is a member of project only temporarily.  It will be
    // less work to move it to fillmore/lombard once we have a transport class.
    public View.MediaEngine media_engine;

    protected string project_file;  // may be null if project has not yet been saved
    public ProjectLoader loader;

    FetcherCompletion fetcher_completion;
    public UndoManager undo_manager;
    public LibraryImporter importer;

    public Fraction default_framerate;
    int tempo = 120;
    Fraction time_signature = Fraction(4, 4);
    public bool click_during_play = false;
    public bool click_during_record = true;
    public double click_volume = 0.8;
    public bool library_visible = true;
    public int library_width = 600;
    public bool snap_to_clip;
    public bool snap_to_grid;

    /* TODO:
     * This can't be const since the Vala compiler (0.7.7) crashes if we try to make it a const.
     * I've filed a bug with the Vala bugzilla for this:
     * https://bugzilla.gnome.org/show_bug.cgi?id=598204
     */    
    public static Fraction INVALID_FRAME_RATE = Fraction(-1, 1);

    public signal void playstate_changed(PlayState playstate);

    public signal void name_changed(string? project_file);
    public signal void load_error(ErrorClass error_class, string error);
    public virtual signal void load_complete() {
    }

    public signal void closed(bool did_close);
    public signal void query_closed(ref bool should_close);

    public signal void track_added(Track track);
    public signal void track_removed(Track track);
    public signal void error_occurred(string major_message, string? minor_message);

    public signal void mediafile_added(MediaFile c);
    public signal void mediafile_removed(MediaFile media_file);
    public signal void cleared();

    public abstract TimeCode get_clip_time(MediaFile f);

    public Project(string? filename, bool include_video) throws Error {
        undo_manager = new UndoManager();
        project_file = filename;

        media_engine = new View.MediaEngine(this, include_video);
        track_added.connect(media_engine.on_track_added);
        media_engine.playstate_changed.connect(on_playstate_changed);
        media_engine.error_occurred.connect(on_error_occurred);

        set_default_framerate(INVALID_FRAME_RATE);
    }

    public void on_playstate_changed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_playstate_changed");
        switch (media_engine.get_play_state()) {
            case PlayState.STOPPED:
                ClearTrackMeters();
                break;
            case PlayState.CLOSED:
                closed(true);
                break;
        }
        playstate_changed(media_engine.get_play_state());
    }

    public virtual string? get_project_file() {
        return project_file;
    }

    public MediaFile? get_mediafile(int index) {
        if (index < 0 ||
            index >= mediafiles.size)
            return null;
        return mediafiles[index];
    }

    public int get_mediafile_index(MediaFile find) {
        int i = 0;
        foreach (MediaFile f in mediafiles) {
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

    protected virtual void do_append(Track track, MediaFile mediafile, string name, 
        int64 insert_time) {
            if (mediafile.get_caps(track.media_type()) == null) {
                return;
            }

        Clip clip = new Clip(mediafile, track.media_type(), name, 0, 0, mediafile.length, false);
        track.append_at_time(clip, insert_time, true);
    }

    public void append(Track track, MediaFile mediafile) {
        string name = isolate_filename(mediafile.filename);
        int64 insert_time = 0;

        foreach (Track temp_track in tracks) {
            insert_time = int64.max(insert_time, temp_track.get_length());
        }
        do_append(track, mediafile, name, insert_time);
    }

    public void add(Track track, MediaFile mediafile, int64 time) {
        string name = isolate_filename(mediafile.filename);
        do_append(track, mediafile, name, time);
    }

    public void on_clip_removed(Track t, Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_removed");
        reseek();
    }

    public void split_at_playhead() {
        string description = "Split At Playhead";
        undo_manager.start_transaction(description);
        foreach (Track track in tracks) {
            if (track.get_clip_by_position(transport_get_position()) != null) {
                track.split_at(transport_get_position());
            }
        }
        undo_manager.end_transaction(description);
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
        string description = "Trim To Playhead";
        Clip first_clip = null;
        undo_manager.start_transaction(description);
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
        undo_manager.end_transaction(description);

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
        return media_engine.get_play_state() == PlayState.PRE_RECORD ||
               media_engine.get_play_state() == PlayState.RECORDING;
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

    public bool is_duplicate_track_name(Track? track, string new_name) {
        assert(new_name != "");
        foreach (Track this_track in tracks) {
            if (track != this_track) {
                if (this_track.get_display_name() == new_name) {
                    return true;
                }
            }
        }
        
        foreach (Track this_track in inactive_tracks) {
            if (track != this_track) {
                if (this_track.get_display_name() == new_name) {
                    return true;
                }
            }
        }
        return false;
    }

    public virtual void add_track(Track track) {
        track.clip_removed.connect(on_clip_removed);
        track.error_occurred.connect(on_error_occurred);
        tracks.add(track);
        track_added(track);
    }

    public void add_inactive_track(Track track) {
        track.hide();
        inactive_tracks.add(track);
    }

    public void remove_track(Track track) {
        media_engine.pipeline.set_state(Gst.State.NULL);
        track.track_removed(track);
        tracks.remove(track);
        track_removed(track);
    }

    public void add_mediafile(MediaFile mediafile) {
        Model.Command command = new Model.AddClipCommand(this, mediafile);
        do_command(command);
    }

    public void _add_mediafile(MediaFile mediafile) throws Error {
        mediafiles.add(mediafile);
        if (mediafile.is_online() && mediafile.get_caps(MediaType.VIDEO) != null) {
            ThumbnailFetcher fetcher = new ThumbnailFetcher(mediafile, 0);
            fetcher.ready.connect(on_thumbnail_ready);
            pending_thumbs.add(fetcher);
        } else {
            mediafile_added(mediafile);
        }
    }

    void on_thumbnail_ready(Fetcher f) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_thumbnail_ready");
        mediafile_added(f.mediafile);
        pending_thumbs.remove(f as ThumbnailFetcher);
    }

    public bool mediafile_on_track(string filename) {
        MediaFile cf = find_mediafile(filename);

        foreach (Track t in tracks) {
            foreach (Clip c in t.clips) {
                if (c.mediafile == cf)
                    return true;
            }
        }

        foreach (Track t in inactive_tracks) {
            foreach (Clip c in t.clips) {
                if (c.mediafile == cf)
                    return true;
            }
        }

        return false;
    }

    void delete_mediafile_from_tracks(MediaFile cf) {
        foreach (Track t in tracks) {
            for (int i = 0; i < t.clips.size; i++) {
                if (t.clips[i].mediafile == cf) {
                    t.delete_clip(t.clips[i]);
                    i --;
                }
            }
        }

        foreach (Track t in inactive_tracks) {
            for (int i = 0; i < t.clips.size; i++) {
                if (t.clips[i].mediafile == cf) {
                    t.delete_clip(t.clips[i]);
                    i --;
                }
            }
        }
    }

    public void _remove_mediafile(MediaFile cf) {
        mediafiles.remove(cf);
        mediafile_removed(cf);
    }

    public void remove_mediafile(string filename) {
        MediaFile cf = find_mediafile(filename);
        if (cf != null) {
            string description = "Delete From Library";
            undo_manager.start_transaction(description);

            delete_mediafile_from_tracks(cf);

            Command mediafile_delete = new MediaFileDeleteCommand(this, cf);
            do_command(mediafile_delete);

            undo_manager.end_transaction(description);
        }
    }
    
    public MediaFile? find_mediafile(string filename) {
        foreach (MediaFile cf in mediafiles)
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

    // Move to the next clip boundary after the current transport position.
    public void go_next() {
        int64 start_pos = transport_get_position();
        int64 new_position = get_length();
        foreach (Track track in tracks) {
            if (track.get_length() > start_pos) {
                new_position = int64.min(new_position, track.next_edit(start_pos));
            }
        }
        transport_go(new_position);
    }

    public int64 transport_get_position() {
        return media_engine.position;
    }

    public void set_name(string? filename) {
        if (filename != null) {
            this.project_file = filename;
        }
        name_changed(filename);
    }

    public void set_default_framerate(Fraction rate) {
        default_framerate = rate;
    }

    public string get_file_display_name() {
        string filename = get_project_file();
        if (filename == null) {
            return "Unsaved Project - %s".printf(get_app_name());
        }
        else {
            string dir = Path.get_dirname(filename);
            string name = Path.get_basename(filename);
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
        
        mediafiles.clear();
        set_name(null);
        cleared();
    }

    public bool can_export() {
        if (media_engine.get_play_state() != PlayState.STOPPED) {
            return false;
        }
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

    void on_load_error(ErrorClass error_class, string error) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_error");
        load_error(error_class, error);
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
    public virtual void load(string? fname) {
        emit(this, Facility.LOADING, Level.INFO, "loading project");
        clear();
        set_name(null);
        if (fname == null) {
            return;
        }

        loader = new ProjectLoader(new MediaLoaderHandler(this), fname);

        loader.load_started.connect(on_load_started);
        loader.load_error.connect(on_load_error);
        loader.load_complete.connect(on_load_complete);
        loader.load_complete.connect(media_engine.on_load_complete);
        media_engine.set_play_state(PlayState.LOADING);
        media_engine.pipeline.set_state(Gst.State.NULL);
        loader.load();
    }

    public void on_error_occurred(string major_error, string? minor_error) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_error_occurred");
        error_occurred(major_error, minor_error);
    }

    public int get_file_version() {
        return 4;
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

        for (int i = 0; i < mediafiles.size; i++) {
            f.printf("    <clipfile filename=\"%s\" id=\"%d\"/>\n", mediafiles[i].filename, i);
        }

        f.printf("  </library>\n");
    }

    public virtual void save(string? filename) {
        if (filename != null) {
            set_name(filename);
        }

        FileStream f = FileStream.open(project_file, "w");
        if (f == null) {
            error_occurred("Could not save project",
                "%s: %s".printf(project_file, GLib.strerror(GLib.errno)));
            return;
        }
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
        f.printf("  <preferences>\n");
        f.printf("    <click on_play=\"%s\" on_record=\"%s\" volume=\"%lf\"/>\n", 
            click_during_play ? "true" : "false",
            click_during_record ? "true" : "false",
            click_volume);
        f.printf("    <library width=\"%d\" visible=\"%s\" />\n",
            library_width, library_visible ? "true" : "false");
        f.printf("  </preferences>\n");
        f.printf("  <maps>\n");
        f.printf("    <tempo>\n");
        f.printf("      <entry tempo=\"%d\" />\n", tempo);
        f.printf("    </tempo>\n");
        f.printf("    <time_signature>\n");
        f.printf("      <entry signature=\"%s\" />\n", time_signature.to_string());
        f.printf("    </time_signature>\n");
        f.printf("  </maps>\n");

        f.printf("</marina>\n");
        f.flush();

        // TODO: clean up responsibility between dirty and undo
        undo_manager.mark_clean();
    }

    public void close() {
        bool should_close = true;
        query_closed(ref should_close);
        if (should_close) {
            media_engine.close();
        } else {
            closed(false);
        }
    }

    public void on_importer_clip_complete(ClipFetcher fetcher) {
        if (fetcher.error_string != null) {
            error_occurred("Error importing clip", fetcher.error_string);
        } else {
            fetcher_completion.complete(fetcher);
        }
    }

    public void create_clip_fetcher(FetcherCompletion fetcher_completion, string filename) 
            throws Error {
        ClipFetcher fetcher = new ClipFetcher(filename);
        this.fetcher_completion = fetcher_completion;
        fetcher.ready.connect(on_fetcher_ready);
        pending.add(fetcher);
    }

    // TODO: We should be using Library importer rather than this mechanism for fillmore
    void on_fetcher_ready(Fetcher fetcher) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_fetcher_ready");
        pending.remove(fetcher as ClipFetcher);
        if (fetcher.error_string != null) {
            emit(this, Facility.DEVELOPER_WARNINGS, Level.INFO, fetcher.error_string);
            error_occurred("Error retrieving clip", fetcher.error_string);
        } else {
            if (get_mediafile_index(fetcher.mediafile) == -1) {
                add_mediafile(fetcher.mediafile);
            }
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

    public void create_clip_importer(Model.Track? track, bool timeline_add, 
            int64 time_to_add, bool both_tracks, Gtk.Window? progress_window_parent, int number) {
        if (timeline_add) {
            assert(track != null);
            importer = new Model.TimelineImporter(track, this, time_to_add, both_tracks);
        } else {
            importer = new Model.LibraryImporter(this);
        }
        if (progress_window_parent != null) {
            new MultiFileProgress(progress_window_parent, number, "Import", 
                importer.importer);
        }

    }

    public string get_version() {
        return _VERSION;
    }

    public abstract string get_app_name();

    public string get_license() {
        return license.printf(get_app_name(), get_app_name(), get_app_name());
    }

    public void set_time_signature(Fraction time_signature) {
        TimeSignatureCommand command = new TimeSignatureCommand(this, time_signature);
        undo_manager.do_command(command);
    }

    public void _set_time_signature(Fraction time_signature) {
        this.time_signature = time_signature;
        time_signature_changed(time_signature);
    }

    public Fraction get_time_signature() {
        return time_signature;
    }

    public void set_bpm(int bpm) {
        BpmCommand command = new BpmCommand(this, bpm);
        undo_manager.do_command(command);
    }

    public void _set_bpm(int bpm) {
        this.tempo = bpm;
        bpm_changed(bpm);
    }

    public int get_bpm() {
        return tempo;
    }

    public string get_audio_path() {
        string path = get_path();
        return path == null ? null : Path.build_filename(path, "audio files");
    }

    string get_path() {
        return project_file == null ? null : Path.get_dirname(project_file);
    }

    public VideoTrack? find_video_track() {
        foreach (Track track in tracks) {
            if (track is VideoTrack) {
                return track as VideoTrack;
            }
        }
        return null;
    }

    public AudioTrack? find_audio_track() {
        foreach (Track track in tracks) {
            if (track is AudioTrack) {
                return track as AudioTrack;
            }
        }
        return null;
    }
}
}

