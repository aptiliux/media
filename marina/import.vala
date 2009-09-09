namespace Model {

public class ClipImporter : MultiFileProgressInterface, Object {  
    enum ImportState {
        FETCHING,
        IMPORTING,
        CANCELLED
    }
    
    string import_directory;
    
    ImportState import_state;
    bool import_done;
    bool all_done;
    ClipFetcher our_fetcher;
    
    Gst.Pad video_pad;
    Gst.Pad audio_pad;
    
    Gst.Pipeline pipeline;
    Gst.Element filesink;
    Gst.Element video_convert;
    Gst.Element audio_convert;
    Gst.Element mux;
    
    Gst.Bin video_decoder;
    Gst.Bin audio_decoder;
    
    int current_file_importing = 0;
    
    int64 current_time;
    int64 total_time;
    int64 previous_time;
    
    Gee.ArrayList<string> filenames = new Gee.ArrayList<string>();
    Gee.ArrayList<ClipFetcher> queued_fetchers = new Gee.ArrayList<ClipFetcher>();
    Gee.ArrayList<string> queued_filenames = new Gee.ArrayList<string>();
    Gee.ArrayList<string> no_import_formats = new Gee.ArrayList<string>();
    
    public signal void clip_complete(ClipFile f);
    public signal void importing_started(int num_clips);
    public signal void error_occurred(string error);
    
    public ClipImporter() {
        import_directory = GLib.Environment.get_home_dir();
        import_directory += "/.lombard_fillmore_import/";
        
        GLib.DirUtils.create(import_directory, 0777);
        
        no_import_formats.add("YUY2");
        no_import_formats.add("Y41B");
        
        import_state = ImportState.FETCHING;
    }
    
    public void add_filename(string filename) {
        filenames.add(filename);
    }

    bool on_timer_callback() {
        int64 time;
        Gst.Format format = Gst.Format.TIME;

        if (all_done) 
            return false;

        if (pipeline.query_position(ref format, out time) &&
            format == Gst.Format.TIME) {
            if (time > previous_time)
                current_time += time - previous_time;
            previous_time = time;
            if (current_time >= total_time) {
                fraction_updated(1.0);
                return false;
            } else
                fraction_updated(current_time / (double)total_time);    
        }
        return true;
    }
    
    void start_import() {
        import_state = ImportState.IMPORTING;
        current_file_importing = 0;
        importing_started(queued_fetchers.size);
        Timeout.add(50, on_timer_callback);
    }
    
    void cancel() {
        all_done = true;
        import_state = ImportState.CANCELLED;
        pipeline.set_state(Gst.State.NULL);
    }
    
    public void start() {
        process_curr_file();
    }
    
    void process_curr_file() {
        if (import_state == ImportState.FETCHING) {
            if (current_file_importing == filenames.size) {
                if (queued_fetchers.size == 0)
                    done();
                else
                    start_import();               
            } else {
                print_debug("Fetching: %s\n".printf(filenames[current_file_importing]));
                our_fetcher = new Model.ClipFetcher(filenames[current_file_importing]);
                our_fetcher.ready += on_fetcher_ready;
            }
        }
        
        if (import_state == ImportState.IMPORTING) {
            if (current_file_importing == queued_fetchers.size) {
                fraction_updated(1.0);
                all_done = true;
            } else
                do_import(queued_fetchers[current_file_importing]);
        }
    }
    
    // TODO: Rework this
    void complete() {
        all_done = true;
    }
    
    void do_import_complete() {
        if (import_state == ImportState.IMPORTING) {
            our_fetcher.clipfile.filename = append_extension(
                                                   queued_filenames[current_file_importing], "mov");
            clip_complete(our_fetcher.clipfile);
        } else
            total_time += our_fetcher.clipfile.length;
  
        current_file_importing++;         
        process_curr_file();
    }
    
    bool need_to_import(ClipFetcher f) {
        if (f.clipfile.is_of_type(MediaType.VIDEO)) {
            uint32 format;
            if (f.clipfile.get_video_format(out format)) {
                foreach (string s in no_import_formats) {
                    if (format == *(uint32*)s)
                        return false;
                }
                return true;
            }
        }
        return false;
    }

    void on_fetcher_ready(ClipFetcher f) {
        if (f.error_string != null) {
            error_occurred(f.error_string);
            do_import_complete();
            return;
        }
        
        if (need_to_import(f)) {
            string checksum;
            if (md5_checksum_on_file(f.clipfile.filename, out checksum)) {
                string base_filename = import_directory + isolate_filename(f.clipfile.filename);
                
                int index = 0;
                string new_filename = base_filename;
                while (true) {
                    string existing_checksum;
                    if (get_file_md5_checksum(new_filename, out existing_checksum)) {
                        if (checksum == existing_checksum) {
                            // Re-fetch this clip to get the correct caps
                            filenames[current_file_importing] = 
                                                            append_extension(new_filename, "mov");
                            current_file_importing--;
                            total_time -= f.clipfile.length;
                            break;
                        }
                        index++;
                        new_filename = base_filename + index.to_string();
                    } else {
                        // Truly need to import
                        save_file_md5_checksum(new_filename, checksum);
                        queued_filenames.add(new_filename);
                        queued_fetchers.add(f);
                        break;
                    }
                }
            } else
                error("Cannot get md5 checksum for file %s!", f.clipfile.filename);
        } else {
            clip_complete(f.clipfile);
        }
        do_import_complete();
    }
    
    void do_import(ClipFetcher f) {
        file_updated(f.clipfile.filename, current_file_importing);
        previous_time = 0;
        
        our_fetcher = f;
        import_done = false;
        
        pipeline = new Gst.Pipeline("pipeline");
        pipeline.set_auto_flush_bus(false);
        
        Gst.Bus bus = pipeline.get_bus();
        bus.add_signal_watch();
        
        bus.message["state-changed"] += on_state_changed;
        bus.message["eos"] += on_eos;
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;
       
        mux = make_element("qtmux");
        
        filesink = make_element("filesink");
        filesink.set("location", append_extension(queued_filenames[current_file_importing], "mov"));
                
        pipeline.add_many(mux, filesink);
        
        if (f.clipfile.is_of_type(MediaType.VIDEO)) {
            video_convert = make_element("ffmpegcolorspace");
            pipeline.add(video_convert);
            
            video_decoder = new SingleDecodeBin(Gst.Caps.from_string(
                                                               "video/x-raw-yuv; video/x-raw-rgb"),
                                                               "videodecodebin", 
                                                               f.clipfile.filename);
            video_decoder.pad_added += on_pad_added;
            
            pipeline.add(video_decoder);
            
            if (!video_convert.link(mux))
                error("do_import: Cannot link video converter to mux!");
        }
        if (f.clipfile.is_of_type(MediaType.AUDIO)) {
            audio_convert = make_element("audioconvert");
            pipeline.add(audio_convert);

            audio_decoder = new SingleDecodeBin(Gst.Caps.from_string("audio/x-raw-int"), 
                                                    "audiodecodebin", f.clipfile.filename);
            audio_decoder.pad_added += on_pad_added;
            
            pipeline.add(audio_decoder);
            
            if (!audio_convert.link(mux))
                error("do_import: Cannot link audio convert to mux!");
        }

        if (!mux.link(filesink))
            error("do_import: Cannot link mux to filesink!");

        print_debug("Starting import to %s...".printf(queued_filenames[current_file_importing]));    
        pipeline.set_state(Gst.State.PLAYING);
    }
    
    void on_pad_added(Gst.Bin b, Gst.Pad p) {
        print_debug("Import Pad added!");
        string str = p.caps.to_string();
        Gst.Pad sink = null;
        
        if (str.has_prefix("video")) {
            video_pad = p;
            sink = video_convert.get_compatible_pad(p, p.caps);
        } else if (str.has_prefix("audio")) {
            audio_pad = p;
            sink = audio_convert.get_compatible_pad(p, p.caps);
        } else
            error("on_pad_added: Unknown prefix!");
        
        if (p.link(sink) != Gst.PadLinkReturn.OK)
            error("Cannot link pad in importer!");
    }
    
    void on_error(Gst.Bus bus, Gst.Message message) {
        Error e;
        string text;
        
        message.parse_error(out e, out text);
        error_occurred(text);
    }
    
    void on_warning(Gst.Bus bus, Gst.Message message) {
        Error e;
        string text;
        message.parse_warning(out e, out text);
        warning("%s", text);
    }
    
    void on_state_changed(Gst.Bus b, Gst.Message m) {
        if (m.src != pipeline) 
            return;
       
        Gst.State old_state;
        Gst.State new_state;
        Gst.State pending;
         
        m.parse_state_changed (out old_state, out new_state, out pending);
        
        if (old_state == new_state) 
            return;

        print_debug("Import State in %s".printf(new_state.to_string()));        
        if (new_state == Gst.State.PAUSED) {
            if (!import_done) {
                if (video_pad != null) {
                    our_fetcher.clipfile.video_caps = video_pad.caps;
                }
                if (audio_pad != null) {
                    our_fetcher.clipfile.audio_caps = audio_pad.caps;
                }
                print_debug("Got clipfile info for: %s\n".printf(our_fetcher.clipfile.filename));
            }    
        } else if (new_state == Gst.State.NULL) {
            if (import_state == ImportState.CANCELLED) {
                GLib.FileUtils.remove(append_extension(queued_filenames[current_file_importing], 
                                                                                            "mov"));
                GLib.FileUtils.remove(append_extension(queued_filenames[current_file_importing], 
                                                                                            "md5"));
            } else {
                if (import_done) 
                    do_import_complete();
            }
        }
    }
    
    void on_eos() {
        import_done = true;
        pipeline.set_state(Gst.State.NULL);
    }
}

public class LibraryImporter {
    protected Project project;
    protected ClipImporter importer;

    public signal void started(ClipImporter i, int num);
    
    public LibraryImporter(Project p) {
        project = p;
        
        importer = new ClipImporter();
        importer.clip_complete += on_clip_complete;
        importer.error_occurred += on_error_occurred;   
        importer.importing_started += on_importer_started;      
    }

    void on_importer_started(ClipImporter i, int num) {
        started(i, num);
    }
    
    void on_error_occurred(string error) {
        project.error_occurred("Error importing", error);
    }
    
    protected virtual void append_existing_clipfile(ClipFile f) {
        
    }
    
    protected virtual void on_clip_complete(ClipFile f) {
        ClipFile cf = project.find_clipfile(f.filename);
        if (cf == null)    
            project.add_clipfile(f);
    }
    
    public void add_file(string filename) {
        ClipFile cf = project.find_clipfile(filename);
        
        if (cf != null)
            append_existing_clipfile(cf);
        else
            importer.add_filename(filename);
    }
    
    public void start() {
        importer.start();
    }        
}

public class TimelineImporter : LibraryImporter {
    public TimelineImporter(Project p) {
        base(p);      
    }
    
    protected override void append_existing_clipfile(ClipFile f) {
        project.append(f);
    }
    
    protected override void on_clip_complete(ClipFile f) {
        base.on_clip_complete(f);
        project.append(f);
    }    
}
}
