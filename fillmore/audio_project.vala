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

    public override void complete(Model.ClipFetcher fetch) {
        base.complete(fetch);
        Clip the_clip = new Clip(fetch.clipfile, MediaType.AUDIO, 
            isolate_filename(fetch.clipfile.filename), 0, 0, fetch.clipfile.length);
        track.add_new_clip(the_clip, position, true);
        project.pause();
    }
}

class AudioProject : Project {
    Track record_track;
    Clip record_region;
    Gst.Element audio_in;
    Gst.Element record_capsfilter;
    Gst.Element wav_encoder;
    Gst.Element record_sink;

    public AudioProject() {
        base(null);
        callback_pulse += on_callback_pulse;
    }
    
    void on_callback_pulse() {
        if (record_region != null) {
            record_region.set_duration(position - record_region.start);
        }
    }
    
    public override TimeCode get_clip_time(ClipFile f) {
        TimeCode t = {};
        
        t.get_from_length(f.length);
        return t;
    }
    
    void post_record() {
        assert(gst_state == Gst.State.NULL);
        create_clip_fetcher(new RecordFetcherCompletion(this, record_track, record_region.start),
            record_region.clipfile.filename);

        int clip_index = record_track.get_clip_index(record_region);
        record_track.remove_clip(clip_index);
        
        audio_in.unlink_many(record_capsfilter, wav_encoder, record_sink);
        pipeline.remove_many(audio_in, record_capsfilter, wav_encoder, record_sink);

        record_region = null;
        record_track = null;
        audio_in = record_capsfilter = null;
        
        play_state = PlayState.STOPPED;
    }

    override double get_version() {
        return 0.01;
    }

    public bool is_recording() {
        return play_state == PlayState.PRE_RECORD ||
               play_state == PlayState.RECORDING ||
               play_state == PlayState.POST_RECORD;
    }
    
    public override void pause() {
        if (is_recording()) {
            set_gst_state(Gst.State.NULL);
            play_state = PlayState.POST_RECORD;
        }
        else {
            base.pause();
        }
    }
    
    public void record(Track track) {
        play_state = PlayState.PRE_RECORD_NULL;
        set_gst_state(Gst.State.NULL);
        record_track = track;

        string filename = new_audio_filename(track);
        ClipFile clip_file = new ClipFile(filename);
        record_region = new Clip(clip_file, MediaType.AUDIO, "", position, 0, 1);
    }

    public void start_record(Clip region) {
        if (is_recording())
            return;
        
        if (is_playing())
            error("can't switch from playing to recording");
            
        if (gst_state != Gst.State.NULL)
            error("can't record now: %s", gst_state.to_string());

        record_track.add_clip_at(record_region, position, false);
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
    
    string new_audio_filename(Track track) {
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
        string base_name = name;
        base_name.down();
        base_name.canon("abcdefghijklmnopqrstuvwxyz1234567890", '_');
        return base_name;
    }

    protected override bool do_state_change() {
        if (!base.do_state_change()) {
            if (play_state == PlayState.PRE_RECORD_NULL) {
                if (gst_state == Gst.State.NULL) {
                    start_record(record_region);
                }
            }
            else if (play_state == PlayState.PRE_RECORD) {
                if (gst_state == Gst.State.PAUSED) {
                    do_play(PlayState.RECORDING);
                    return true;
                }
            }
            else if (play_state == PlayState.POST_RECORD) {
                if (gst_state != Gst.State.NULL) {
                    set_gst_state(Gst.State.NULL);
                } else {
                    post_record();
                }
                return true;
            }
        }
        return false;
    }
}
}
