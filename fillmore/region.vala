/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class Region {
    public string name;
    
    public string filename;
    public int64 start;     // start time in ns
    public int64 length;    // in ns
    
    public Gst.Element file_source;
    
    public Track track;
    public RegionView view;
    
    Gst.Pipeline pipeline;  // used only for determining region length
    
    public Region(string filename, int64 start, bool record) {
        this.filename = filename;
        this.start = start;
        
        name = GLib.Path.get_basename(filename);
        name = name.split(".")[0];  // exclude suffix such as .wav
        
        if (!record)
            load();
    }
    
    public int64 end() { return start + length; }
    
    public void load() {
        file_source = make_element("gnlfilesource");
        file_source.set("location", filename);
        file_source.set("priority", 0);
        file_source.set("start", start);
        file_source.set("media-start", 0 * Gst.SECOND);
        
        string pipe = "filesrc location=%s ! decodebin ! fakesink".printf(filename);
        pipeline = (Gst.Pipeline) Gst.parse_launch(pipe);
        if (pipeline == null)
            error("can't construct pipeline");
        
        Gst.Bus bus = pipeline.get_bus();
        bus.add_signal_watch();
        bus.message["state-changed"] += on_state_change;
        
        pipeline.set_state(Gst.State.PAUSED);
    }
    
    void on_state_change(Gst.Bus bus, Gst.Message message) {
        Gst.Format format = Gst.Format.TIME;
        int64 duration;
        if (pipeline.query_duration(ref format, out duration) &&
            format == Gst.Format.TIME) {
            pipeline.set_state(Gst.State.NULL);
            pipeline = null;
            
            length = duration;
            file_source.set("duration", length);
            file_source.set("media-duration", length);
            if (view != null)
                view.update();
        }
    }
    
    public void move(int64 new_start) {
        start = new_start;
        file_source.set("start", start);
        view.update();
    }
    
    public void update_end(int64 end) {
        length = end - start;
        view.update();
    }
}

