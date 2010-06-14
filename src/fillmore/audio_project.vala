/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;
namespace Model {

class RecordFetcherCompletion : FetcherCompletion {
    Track track;
    Project project;
    int64 position;

    public RecordFetcherCompletion(Project project, Track track, int64 position) {
        base();
        this.track = track;
        this.project = project;
        this.position = position;
    }

    public override void complete(Fetcher fetch) {
        base.complete(fetch);
        Clip the_clip = new Clip(fetch.mediafile, MediaType.AUDIO, 
            isolate_filename(fetch.mediafile.filename), 0, 0, fetch.mediafile.length, false);
        project.undo_manager.start_transaction("Record");
        track.append_at_time(the_clip, position, true);
        project.undo_manager.end_transaction("Record");
    }
}

class AudioProject : Project {
    bool has_been_saved;

    public AudioProject(string? filename) throws Error {
        base(filename, false);
        // TODO: When vala supports throwing from base, remove this check
        if (this != null) {
            has_been_saved = filename != null;
            if (!has_been_saved) {
                project_file = generate_filename();
            }
            media_engine.callback_pulse.connect(media_engine.on_callback_pulse);
            media_engine.record_completed.connect(on_record_completed);
        }
    }

    public override TimeCode get_clip_time(MediaFile f) {
        TimeCode t = {};
        
        t.get_from_length(f.length);
        return t;
    }

    public override string? get_project_file() {
        if (!has_been_saved) {
            return null;
        } else {
            return base.get_project_file();
        }
    }

    string generate_filename() {
        Time now = Time.local(time_t());
        string timestring = now.to_string();
        timestring = timestring.replace(":", "_");
        string pathname = Path.build_filename(GLib.Environment.get_home_dir(), ".fillmore", 
            timestring);
        GLib.DirUtils.create(pathname, 0777);
        string filename = "%s.%s".printf(timestring, "fill");
        return Path.build_filename(pathname, filename);
    }

    public override string get_app_name() {
        return Recorder.NAME;
    }

    public override void add_track(Track track) {
        if (track.media_type() == MediaType.VIDEO) {
            track.hide();
            inactive_tracks.add(track);
            return;
        }
        
        base.add_track(track);
    }
    
    public void record(AudioTrack track) {
        media_engine.record(track);
    }

    public void on_record_completed() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_record_completed");
        try {
            create_clip_fetcher(new Model.RecordFetcherCompletion(this, media_engine.record_track,
                media_engine.record_region.start), media_engine.record_region.mediafile.filename);
        } catch (Error e) {
            error_occurred("Could not complete recording", e.message);
        }
    }

    public override void load(string? filename) {
        has_been_saved = filename != null;
        if (!has_been_saved) {
            project_file = generate_filename();
        }
        base.load(filename);
    }

    public override void save(string? filename) {
        if (!has_been_saved && filename != null) {
            move_audio_files(filename);
            GLib.FileUtils.remove(project_file);
            GLib.DirUtils.remove(Path.get_dirname(project_file));
        }

        base.save(filename);
        has_been_saved = true;
    }

    void move_audio_files(string filename) {
        string audio_path = get_audio_path();
        string destination_path = Path.build_filename(Path.get_dirname(filename), "audio files");
        GLib.DirUtils.create(destination_path, 0777);
        GLib.Dir dir;
        try {
            dir = Dir.open(audio_path);
        } catch (FileError e) {
            return;
        }

        // First, move all of the files over, even if they aren't currently in the project
        weak string? base_name = null;
        do {
            base_name = dir.read_name();
            string destination = Path.build_filename(destination_path, base_name);
            FileUtils.rename(Path.build_filename(audio_path, base_name), destination);
        } while (base_name != null);

        // Next, update the model so that the project file is saved properly
        foreach (MediaFile media_file in mediafiles) {
            if (Path.get_dirname(media_file.filename) == audio_path) {
                string file_name = Path.get_basename(media_file.filename);
                string destination = Path.build_filename(destination_path, file_name);
                media_file.filename = destination;
            }
        }

        GLib.DirUtils.remove(audio_path);
    }

}
}
