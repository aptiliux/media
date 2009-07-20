/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class Project {
    public Gee.ArrayList<Track> tracks = new Gee.ArrayList<Track>();

    Track record_track;
    Region record_region;
    public AudioEngine audio_engine;
    
    string project_path;
    
    public signal void track_added(Track track);
    public signal void track_removed(Track track);
    
    public Project() {
        audio_engine = new AudioEngine();
        audio_engine.fire_callback_pulse += notify;
        audio_engine.fire_post_record += on_post_record;
        track_added += audio_engine.on_track_added;
        
        add_track();    // start with a single track
        
        project_path = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".fillmore");
        if (!FileUtils.test( project_path, FileTest.EXISTS)) {
            GLib.DirUtils.create(project_path, 0777);
        }
    }
    
    
    int64 end() {
        int64 end = 0;
        
        foreach (Track track in tracks)
            end = int64.max(end, track.end());
        return end;
    }
    
    
    void notify() {
        if (record_region != null)
            record_region.update_end(audio_engine.position);

    }
    
    void on_post_record() {
        record_region.load();
        record_track.add_source(record_region);
        
        record_region = null;
        record_track = null;
    }


    string generate_base(string name) {
        string base_name = name;
        base_name.down();
        base_name.canon("abcdefghijklmnopqrstuvwxyz1234567890", '_');
        return base_name;
    }
    
    string new_audio_filename(Track track) {
        int i = 1;
        string base_name = Path.build_filename(get_project_path(), generate_base(track.name));
        while (true) {
            string name = "%s_%d.wav".printf(base_name, i);
            if (!FileUtils.test(name, FileTest.EXISTS)) {
                return name;
            }
            ++i;
        }
    }
    
    public void add_named_track(string name) {
        Track track = new Track(name);
        tracks.add(track);
        
        track_added(track);
    }        

    public void add_track() {
        string name = get_default_track_name();
        add_named_track(name);
    }

    public void rename_track(string newName, Track? track) {
        if (track != null) {
            track.rename(newName);
        }
    }
    
    public string get_default_track_name() {
        int i = tracks.size + 1;
        return "track %d".printf(i);
    }
    
    public void play() {
        audio_engine.play();
    }

    public void stop() {
        audio_engine.stop();
    }
    
    string get_project_path() {
        return project_path;
    }
    
    public void set_project_path(string new_project_path) {
        project_path = new_project_path;
    }
    
    public void record(Track track) {
        record_track = track;

        string filename = new_audio_filename(track);
        record_region = new Region(filename, audio_engine.position, true);
        track.add(record_region);

        audio_engine.record(record_region);
    }
    
    public void rewind() {
        stop();
        audio_engine.set_position(0);
    }

    public bool recording() {
        return audio_engine.recording();
    }    
    
    public bool playing() {
        return audio_engine.playing();
    }
    
    public void export(string filename) {
        audio_engine.export(filename, 0, end());
    }
    
    public void close() {
        audio_engine.close();
    }
    
}

