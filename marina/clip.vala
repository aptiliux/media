/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
class Gap {
    public int64 start;
    public int64 end;

    public Gap(int64 start, int64 end) {
        this.start = start;
        this.end = end;
    }

    public bool is_empty() {
        return start >= end;
    }

    public Gap intersect(Gap g) {
        return new Gap(int64.max(start, g.start), int64.min(end, g.end));
    }
}

class ClipFile {
    public string filename;
    public int64 length;
    
    public Gst.Caps video_caps;    // or null if no video
    public Gst.Caps audio_caps;    // or null if no audio

    public ClipFile(string filename, int64 length = 0) {
        this.filename = filename;
        this.length = length;
    }
    
    public bool has_caps_structure(MediaType m) {
        if (m == MediaType.AUDIO) {
            if (audio_caps == null || audio_caps.get_size() < 1)
                return false;
        } else if (m == MediaType.VIDEO) {
            if (video_caps == null || video_caps.get_size() < 1)
                return false;
        }
        return true;
    }

    bool get_caps_structure(MediaType m, out Gst.Structure s) {
        
        if (!has_caps_structure(m))
            return false;
        if (m == MediaType.AUDIO) {
            s = audio_caps.get_structure(0);
        } else if (m == MediaType.VIDEO) {
            s = video_caps.get_structure(0);
        }
        return true;
    }
    
    public bool get_frame_rate(out Fraction rate) {
        Gst.Structure structure;
        if (!get_caps_structure(MediaType.VIDEO, out structure))
            return false;
        return structure.get_fraction("framerate", out rate.numerator, out rate.denominator);
    }
    
    public bool get_dimensions(out int w, out int h) {
        Gst.Structure s;
        
        if (!get_caps_structure(MediaType.VIDEO, out s))
            return false;
        
        return s.get_int("width", out w) && s.get_int("height", out h);
    }
    
    public bool get_sample_rate(out int rate) {
        Gst.Structure s;
        if (!get_caps_structure(MediaType.AUDIO, out s))
            return false;
        
        return s.get_int("rate", out rate);
    }
    
    public bool get_num_channels(out int channels) {
        Gst.Structure s;
        if (!get_caps_structure(MediaType.AUDIO, out s))
            return false;
        
        return s.get_int("channels", out channels);        
    }    
    
    public bool get_num_channels_string(out string s) {
        
        int i;
        if (!get_num_channels(out i))
            return false;
        
        if (i == 1)
            s = "Mono";
        else if (i == 2)
            s = "Stereo";
        else if ((i % 2) == 0)
            s = "Surround %.1".printf(i - 1);
        else
            s = "%d".printf(i);
        return true;
    }
}

class ClipFetcher {
    public ClipFile clipfile;
    
    Gst.Pad video_source;
    Gst.Pad audio_source;
    
    Gst.Element fakesink;
    Gst.Pipeline pipeline;
    public string error_string;
    bool linked;

    public signal void ready();
    
    public ClipFetcher(string filename) {
        clipfile = new ClipFile(filename);
        
        Gst.Element filesrc = make_element("filesrc");
        filesrc.set("location", filename);
        Gst.Bin decodebin = (Gst.Bin) make_element("decodebin");
        fakesink = make_element("fakesink");
        pipeline = new Gst.Pipeline("pipeline");
        if (pipeline == null)
            error("can't construct pipeline");
        pipeline.add_many(filesrc, decodebin, fakesink);
        if (!filesrc.link(decodebin))
            error("can't link filesrc");
        decodebin.pad_added += on_pad_added;
        
        Gst.Bus bus = pipeline.get_bus();

        bus.add_signal_watch();
        bus.message["state-changed"] += on_state_change;
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;
               
        error_string = null;
        pipeline.set_state(Gst.State.PAUSED);
    }
    
    public string get_filename() { return clipfile.filename; }
    
    void do_error(string error) {
        error_string = error;
        pipeline.set_state(Gst.State.NULL);
        ready();
    }
    
    void on_pad_added(Gst.Bin bin, Gst.Pad pad) {
        string caps = pad.caps.to_string();
        if (caps.has_prefix("video"))
            video_source = pad;
        else if (caps.has_prefix("audio"))
            audio_source = pad;
        
        if (!linked) {
            Gst.Pad sink = fakesink.get_static_pad("sink");
            if (pad.link(sink) != Gst.PadLinkReturn.OK)
                error("can't link pad");
            linked = true;
        }
    }
    
    void on_warning(Gst.Bus bus, Gst.Message message) {
        Error error;
        string text;
        message.parse_warning(out error, out text);
        warning(text);
    }
    
    void on_error(Gst.Bus bus, Gst.Message message) {
        Error error;
        string text;
        message.parse_error(out error, out text);
        do_error(text);
    }
    
    void on_state_change(Gst.Bus bus, Gst.Message message) {
        if (message.src != pipeline)
            return;
            
        Gst.State old_state;
        Gst.State new_state;
        Gst.State pending;
        
        message.parse_state_changed(out old_state, out new_state, out pending);
        if (new_state != Gst.State.PAUSED)
            return;
            
        Gst.Format format = Gst.Format.TIME;
        if (!pipeline.query_duration(ref format, out clipfile.length) ||
                format != Gst.Format.TIME) {
            do_error("Can't fetch length");
            return;
        }
        
        if (video_source != null)
            clipfile.video_caps = video_source.caps;
        if (audio_source != null)
            clipfile.audio_caps = audio_source.caps;
        
        pipeline.set_state(Gst.State.NULL);
        ready();
    }
}

class Clip {
    public ClipFile clipfile;
    public MediaType type;
    
    public string name;
    public int64 start;
    public int64 media_start;
    public int64 length;
    
    public Gst.Element file_source;
    
    bool connected;

    public int64 end {
        get { return start + length; }
    }
    
    public signal void moved();
    
    public Clip(ClipFile clipfile, MediaType t, string name,
                int64 start, int64 media_start, int64 duration) {
        this.clipfile = clipfile;
        this.type = t;
        this.name = name;
        this.connected = true;
        
        file_source = make_element("gnlfilesource");
        file_source.set("location", clipfile.filename);

        set_media_start(media_start);
        set_duration(duration);
        set_start(start);
        
        if (type == MediaType.AUDIO)
            file_source.set("caps", Gst.Caps.from_string("audio/x-raw-int"));
    }
    
    public void gnonlin_connect() { connected = true; }
    public void gnonlin_disconnect() { connected = false; }
    
    public bool overlap_pos(int64 start, int64 length) {
        return start < this.start + this.length &&
                this.start < start + length;
    }
    
    public bool snap(Clip other, int64 pad) {
        if (time_in_range(start, other.start, pad)) {
            set_start(other.start);
            return true;
        } else if (time_in_range(start, other.end, pad)) {
            set_start(other.end);
            return true;
        } else if (time_in_range(end, other.start, pad)) {
            set_start(other.start - length);
            return true;
        } else if (time_in_range(end, other.end, pad)) {
            set_start(other.end - length);
            return true;
        }
        return false;
    }
    
    public bool snap_coord(out int64 s, int64 span) {
        if (time_in_range(s, start, span)) {
            s = start;
            return true;
        } else if (time_in_range(s, end, span)) {
            s = end;
            return true;
        }
        return false;
    }
    
    public Clip copy() {
        return new Clip(clipfile, type, name, start, media_start, length);
    }

    public bool is_trimmed() {
        return length != clipfile.length;
    }

    public void set_media_start(int64 start) {
        if (connected)
            file_source.set("media-start", start);
        this.media_start = start;
    }
    
    public void set_duration(int64 len) {
        if (connected) {
            file_source.set("duration", len);
            file_source.set("media-duration", len);
        }
        
        this.length = len;
        moved();
    }
    
    public void set_start(int64 start) {
        if (connected)
            file_source.set("start", start);
        this.start = start;
        moved();
    }

    public void save(FileStream f) {
        f.printf(
            "  <clip filename=\"%s\" name=\"%s\" start=\"%" + int64.FORMAT + "\" " +
                    "media-start=\"%" + int64.FORMAT + "\" duration=\"%" + int64.FORMAT + "\"/>\n",
            clipfile.filename, name, start, media_start, length);
    }
}
}
