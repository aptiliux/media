/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
class AudioProject : Project {
    Track record_track;
    Clip record_region;
    Gst.Element audio_in;
    Gst.Element record_capsfilter;
//    Gst.Element wav_encoder;

    int64 export_begin;
    int64 export_end;

    public signal void fire_callback_pulse();
    public signal void fire_post_record();
    public signal void fire_state_changed(PlayState new_state);

    public AudioProject() {
        base(null);
        Gst.Bus bus = pipeline.get_bus();
        bus.message["eos"] += on_eos;
        
    }
    
    void on_eos(Gst.Bus bus, Gst.Message message) {
        if (play_state == PlayState.EXPORTING)
            set_gst_state(Gst.State.NULL);
    }

    void do_export() {
        assert(gst_state == Gst.State.PAUSED);

        pipeline.seek(1.0, Gst.Format.TIME, Gst.SeekFlags.FLUSH,
                      Gst.SeekType.SET, export_begin, Gst.SeekType.SET, export_end);

        play_state = PlayState.EXPORTING;
        set_gst_state(Gst.State.PLAYING);
    }

    void post_record() {
/*        audio_in.unlink_many(record_capsfilter, wav_encoder, file_sink);
        pipeline.remove_many(audio_in, record_capsfilter, wav_encoder, file_sink);
        audio_in = record_capsfilter = null;
        fire_post_record();
        play_state = PlayState.STOPPED;
        */
    }

    override double get_version() {
        return 0.01;
    }

    public bool is_recording() {
        return play_state == PlayState.PRE_RECORD ||
               play_state == PlayState.RECORDING ||
               play_state == PlayState.POST_RECORD;
    }
    
    public void record(Track track) {
        record_track = track;

        string filename = new_audio_filename(track);
        ClipFile clip_file = new ClipFile(filename);
        record_region = new Clip(clip_file, MediaType.AUDIO, "", position, 0, 10000000000);
        track.add_clip_at(record_region, position, false);

        start_record(record_region);
    }

    public void start_record(Clip region) {
    /*
        if (is_recording())
            return;
        
        if (is_playing())
            error("can't switch from playing to recording");
            
        if (gst_state != Gst.State.NULL)
            error("can't record now");
        
        audio_in = make_element("gconfaudiosrc");
        record_capsfilter = make_element("capsfilter");
        record_capsfilter.set("caps", fixed_caps);
        stderr.printf("Location is %s\n", region.clipfile.filename);
        file_sink.set("location", region.clipfile.filename);
        
        pipeline.add_many(audio_in, record_capsfilter, wav_encoder, file_sink);
        if (!audio_in.link_many(record_capsfilter, wav_encoder, file_sink))
            error("audio_in: couldn't link");

        play_state = PlayState.PRE_RECORD;
        set_gst_state(Gst.State.PAUSED);    // we must advance to PAUSED before we can seek
        
        //fire_state_changed(PlayState.RECORDING);
        */
    }

    string new_audio_filename(Track track) {
        int i = 1;
        string base_name = Path.build_filename("/home/rob", generate_base(track.name()));
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

    override bool do_state_changed(Gst.State state, PlayState play_state) {
        if (!base.do_state_changed(state, play_state)) {
            if (gst_state == Gst.State.PAUSED) {
                if (play_state == PlayState.PRE_RECORD) {
                    do_play(PlayState.RECORDING);
                    return true;
                } else if (play_state == PlayState.PRE_EXPORT) {
                    do_export();
                    return true;
                }
            } else if (gst_state == Gst.State.NULL) {
                if (play_state == PlayState.POST_RECORD) {
                    post_record();
                    return true;
                } else if (play_state == PlayState.EXPORTING) {
                    post_export();
                    return true;
                }
            }
        }
        return false;
    }
}
}
