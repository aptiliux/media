/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

enum PlayState {
    STOPPED,
    PRE_PLAY, PLAYING,
    PRE_RECORD, RECORDING, POST_RECORD,
    PRE_EXPORT, EXPORTING
}

class AudioEngine {
    Gst.Pipeline pipeline;
    Gst.Caps fixed_caps;
    
    Gst.Element adder;
    Gst.Element capsfilter;
    Gst.Element audio_sink;
    public Gst.State gst_state;
    PlayState play_state;

    Gst.Element audio_in;
    Gst.Element record_capsfilter;
    Gst.Element wav_encoder;
    Gst.Element file_sink;

    public int64 position;
    uint callback_id;
    int64 export_begin;
    int64 export_end;

    public signal void fire_callback_pulse();
    public signal void fire_post_record();
    public signal void fire_state_changed(PlayState new_state);

    public AudioEngine() {
        pipeline = new Gst.Pipeline("pipeline");
        pipeline.set_auto_flush_bus(false);
        
        Gst.Element silence = make_element("audiotestsrc");
        silence.set("wave", 4);     // 4 is silence
        
        adder = make_element("adder");
        
        capsfilter = make_element("capsfilter");
        fixed_caps = Gst.Caps.from_string(
            "audio/x-raw-int,rate=44100,channels=1,width=16,depth=16,signed=true");
        capsfilter.set("caps", fixed_caps);
        
        audio_sink = make_element("gconfaudiosink");
    
        pipeline.add_many(silence, adder, capsfilter, audio_sink);
        if (!silence.link_many(adder, capsfilter, audio_sink))
            error("silence: couldn't link");

        Gst.Bus bus = pipeline.get_bus();
        bus.add_signal_watch();
        bus.message["eos"] += on_eos;
        bus.message["state-changed"] += on_state_changed;
        bus.message["warning"] += on_warning;
        bus.message["error"] += on_error;

        wav_encoder = make_element("wavenc");
        file_sink = make_element("filesink");
        
        gst_state = Gst.State.NULL;
        play_state = PlayState.STOPPED;
    }
    
    public void export(string filename, int64 begin, int64 end) {
        export_begin = begin;
        export_end = end;
        play_state = PlayState.PRE_EXPORT;
        set_gst_state(Gst.State.PAUSED);    // we must advanced to PAUSED before we can seek

        capsfilter.unlink(audio_sink);
        
        // We must remove the audio sink from the pipeline in order to receive an EOS
        // message when the export is complete.
        if (!pipeline.remove(audio_sink))
            error("couldn't remove audio sink");
    
        file_sink.set("location", filename);
        
        pipeline.add_many(wav_encoder, file_sink);
        if (!capsfilter.link_many(wav_encoder, file_sink))
            error("capsfilter: couldn't link");
    }

    void do_export() {
        assert(gst_state == Gst.State.PAUSED);

        pipeline.seek(1.0, Gst.Format.TIME, Gst.SeekFlags.FLUSH,
                      Gst.SeekType.SET, export_begin, Gst.SeekType.SET, export_end);

        play_state = PlayState.EXPORTING;
        set_gst_state(Gst.State.PLAYING);
    }

    void on_eos(Gst.Bus bus, Gst.Message message) {
        if (play_state == PlayState.EXPORTING)
            set_gst_state(Gst.State.NULL);
    }

    void on_state_changed(Gst.Bus bus, Gst.Message message) {
        Gst.State old_state;
        Gst.State new_state;
        Gst.State pending;
        message.parse_state_changed(out old_state, out new_state, out pending);
                       
        if (message.src != pipeline)
            return;
                       
        if (new_state != gst_state) {
            gst_state = new_state;
//            stderr.printf("recorder: state change: obj = %s, new = %s, pending = %s\n",
//                           message.src.name, new_state.to_string(), pending.to_string());

            if (gst_state == Gst.State.PAUSED) {
                if (play_state == PlayState.PRE_PLAY)
                    do_play(PlayState.PLAYING);
                else if (play_state == PlayState.PRE_RECORD)
                    do_play(PlayState.RECORDING);
                else if (play_state == PlayState.PRE_EXPORT)
                    do_export();
            } else if (gst_state == Gst.State.NULL) {
                if (play_state == PlayState.POST_RECORD)
                     post_record();
                 else if (play_state == PlayState.EXPORTING)
                     post_export();
             }
        }
    }

    void on_warning(Gst.Bus bus, Gst.Message message) {
        stdout.puts("warning\n");
    }    
    
    void on_error(Gst.Bus bus, Gst.Message message) {
        GLib.Error error;
        string debug;
        message.parse_error(out error, out debug);
        stdout.printf("error %s %s\n", error.message, debug);
    }    

    void on_composition_pad_added(Gst.Bin composition, Gst.Pad pad) {
        Gst.Pad p = adder.get_compatible_pad(pad, pad.get_caps());
        if (pad.link(p) != Gst.PadLinkReturn.OK)
            error("pad_added: couldn't link");
    }

    void do_play(PlayState new_state) {
        assert(gst_state == Gst.State.PAUSED);

        seek(Gst.SeekFlags.FLUSH, position);

        play_state = new_state;
        set_gst_state(Gst.State.PLAYING);
        
        if (callback_id == 0)
            callback_id = Timeout.add(33, on_callback);
    }

    void post_record() {
        audio_in.unlink_many(record_capsfilter, wav_encoder, file_sink);
        pipeline.remove_many(audio_in, record_capsfilter, wav_encoder, file_sink);
        audio_in = record_capsfilter = null;
        fire_post_record();
        play_state = PlayState.STOPPED;
    }

    void post_export() {
        capsfilter.unlink_many(wav_encoder, file_sink);
        pipeline.remove_many(wav_encoder, file_sink);
        
        if (!pipeline.add(audio_sink))
            error("couldn't add");
        capsfilter.link(audio_sink);
        
        play_state = PlayState.STOPPED;
        stderr.puts("export complete\n");
    }

    public void play() {
        if (playing())
            return;
        if (recording())
            error("can't switch from recording to playing");
        
        if (gst_state == Gst.State.PAUSED)
            do_play(PlayState.PLAYING);
        else {
            play_state = PlayState.PRE_PLAY;
            set_gst_state(Gst.State.PAUSED);    // we must advance to PAUSED before we can seek
        }
        
        fire_state_changed(PlayState.PLAYING);
    }

    public void record(Region region) {
        if (recording())
            return;
        
        if (playing())
            error("can't switch from playing to recording");
            
        if (gst_state != Gst.State.NULL)
            error("can't record now");
        
        audio_in = make_element("gconfaudiosrc");
        record_capsfilter = make_element("capsfilter");
        record_capsfilter.set("caps", fixed_caps);
        stderr.printf("Location is %s\n", region.filename);
        file_sink.set("location", region.filename);
        
        pipeline.add_many(audio_in, record_capsfilter, wav_encoder, file_sink);
        if (!audio_in.link_many(record_capsfilter, wav_encoder, file_sink))
            error("audio_in: couldn't link");

        play_state = PlayState.PRE_RECORD;
        set_gst_state(Gst.State.PAUSED);    // we must advance to PAUSED before we can seek
        
        fire_state_changed(PlayState.RECORDING);
    }

    public void stop() {
        if (play_state == PlayState.STOPPED)
            return;
            
        if (playing()) {
            set_gst_state(Gst.State.NULL);
            play_state = PlayState.STOPPED;
        } else if (recording()) {
            set_gst_state(Gst.State.NULL);
            play_state = PlayState.POST_RECORD;
        }
        
        fire_state_changed(PlayState.STOPPED);
    }
    
    void seek(Gst.SeekFlags flags, int64 pos) {
        // We do *not* check the return value of seek_simple here: it will often
        // be false when seeking into a GnlSource which we have not yet played,
        // even though the seek appears to work fine in that case.
        pipeline.seek_simple(Gst.Format.TIME, flags, pos);
    }

    int64 get_position() {
        Gst.Format format = Gst.Format.TIME;
        int64 time;
        if (pipeline.query_position(ref format, out time) && format == Gst.Format.TIME)
            return time;
        error("can't query position");
        return 0;
    }

    public void set_position(int64 time) {
        if (play_state == PlayState.PLAYING || play_state == PlayState.RECORDING)
            seek(Gst.SeekFlags.FLUSH, time);
        else {
            position = time;
            fire_callback_pulse();
        }
    }

    void set_gst_state(Gst.State state) {
        if (pipeline.set_state(state) == Gst.StateChangeReturn.FAILURE)
            error("can't set state");
    }

    bool on_callback() {
        if (play_state != PlayState.PLAYING && play_state != PlayState.RECORDING) {
            callback_id = 0;
            return false;
        }
        
        if (gst_state != Gst.State.PLAYING)
            return true;    // not playing yet
        
        position = get_position();

        fire_callback_pulse();            
        
        return true;
    }
    
    public void on_track_added(Track track) {
        Gst.Bin composition = track.composition;
        composition.pad_added += on_composition_pad_added;
        pipeline.add(composition);
    }

    public void close() {
        set_gst_state(Gst.State.NULL);
    }

    public bool playing() {
        return play_state == PlayState.PRE_PLAY ||
               play_state == PlayState.PLAYING;
    }
    
    public bool recording() {
        return play_state == PlayState.PRE_RECORD ||
               play_state == PlayState.RECORDING ||
               play_state == PlayState.POST_RECORD;
    }

}

