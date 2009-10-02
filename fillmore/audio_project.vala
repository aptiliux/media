/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

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

    public override void complete(ClipFetcher fetch) {
        base.complete(fetch);
        Clip the_clip = new Clip(fetch.clipfile, MediaType.AUDIO, 
            isolate_filename(fetch.clipfile.filename), 0, 0, fetch.clipfile.length, false);
        track.add_new_clip(the_clip, position, true);
    }
}

class AudioProject : Project {
    public AudioProject() {
        base(null, false);
        media_engine.callback_pulse += media_engine.on_callback_pulse;
        media_engine.record_completed += on_record_completed;
    }
    
    public override TimeCode get_clip_time(ClipFile f) {
        TimeCode t = {};
        
        t.get_from_length(f.length);
        return t;
    }

    override double get_version() {
        return 0.01;
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
        create_clip_fetcher(new Model.RecordFetcherCompletion(this, media_engine.record_track,
            media_engine.record_region.start), media_engine.record_region.clipfile.filename);
    }

}
}
