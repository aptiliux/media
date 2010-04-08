/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace Model {

public enum MediaType {
    AUDIO,
    VIDEO
}

public class Gap {
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

public class ClipFile : Object {
    public string filename;
    public int64 length;

    bool online;

    public Gst.Caps video_caps;    // or null if no video
    public Gst.Caps audio_caps;    // or null if no audio
    public Gdk.Pixbuf thumbnail = null;

    public signal void updated();

    public ClipFile(string filename, int64 length = 0) {
        this.filename = filename;
        this.length = length;
        online = false;
    }

    public bool is_online() {
        return online;
    }

    public void set_online(bool o) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "set_online");
        online = o;
        updated();
    }

    public void set_thumbnail(Gdk.Pixbuf b) {
        // TODO: Investigate this
        // 56x56 - 62x62 icon size does not work for some reason when
        // we display the thumbnail while dragging the clip.

        thumbnail = b.scale_simple(64, 44, Gdk.InterpType.BILINEAR);
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

    public bool is_of_type(MediaType t) {
        if (t == MediaType.VIDEO)
            return video_caps != null;
        return audio_caps != null;
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

    public bool get_video_format(out uint32 fourcc) {
        Gst.Structure s;

        if (!get_caps_structure(MediaType.VIDEO, out s))
            return false;

        return s.get_fourcc("format", out fourcc);
    }

    public bool get_num_channels(out int channels) {
        Gst.Structure s;
        if (!get_caps_structure(MediaType.AUDIO, out s)) {
            return false;
        }

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
            s = "Surround %d.1".printf(i - 1);
        else
            s = "%d".printf(i);
        return true;
    }
}

public abstract class Fetcher : Object {
    protected Gst.Element filesrc;
    protected Gst.Element decodebin;
    protected Gst.Pipeline pipeline;

    public ClipFile clipfile;
    public string error_string;

    protected abstract void on_pad_added(Gst.Pad pad);
    protected abstract void on_state_change(Gst.Bus bus, Gst.Message message);

    public signal void ready();

    protected void do_error(string error) {
        error_string = error;
        pipeline.set_state(Gst.State.NULL);
    }

    protected void on_warning(Gst.Bus bus, Gst.Message message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_warning");
        Error error;
        string text;
        message.parse_warning(out error, out text);
        warning("%s", text);
    }

    protected void on_error(Gst.Bus bus, Gst.Message message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_error");
        Error error;
        string text;
        message.parse_error(out error, out text);
        do_error(text);
    }
}

public class ClipFetcher : Fetcher {  
    public signal void clipfile_online(bool online);

    public ClipFetcher(string filename) throws Error {
        clipfile = new ClipFile(filename);

        clipfile_online += clipfile.set_online;

        filesrc = make_element("filesrc");
        filesrc.set("location", filename);

        decodebin = (Gst.Bin) make_element("decodebin");
        pipeline = new Gst.Pipeline("pipeline");
        pipeline.set_auto_flush_bus(false);
        if (pipeline == null)
            error("can't construct pipeline");
        pipeline.add_many(filesrc, decodebin);

        if (!filesrc.link(decodebin))
            error("can't link filesrc");
        decodebin.pad_added += on_pad_added;

        Gst.Bus bus = pipeline.get_bus();

        bus.add_signal_watch();
        bus.message["state-changed"] += on_state_change;
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;

        error_string = null;
        pipeline.set_state(Gst.State.PLAYING);
    }

    public string get_filename() { return clipfile.filename; }

    protected override void on_pad_added(Gst.Pad pad) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_pad_added");
        Gst.Pad fake_pad;
        Gst.Element fake_sink;
        try {
            if (pad.caps.to_string().has_prefix("video")) {
                fake_sink = make_element("fakesink");
                pipeline.add(fake_sink);
                fake_pad = fake_sink.get_static_pad("sink");

                if (!fake_sink.sync_state_with_parent()) {
                    error("could not sync state with parent");
                }
            } else {
                fake_sink = make_element("fakesink");
                pipeline.add(fake_sink);
                fake_pad = fake_sink.get_static_pad("sink");

                if (!fake_sink.sync_state_with_parent()) {
                    error("could not sync state with parent");
                }
            }
            pad.link(fake_pad);
        }
        catch (Error e) {
        }
    }

    Gst.Pad? get_pad(string prefix) {
        foreach(Gst.Pad pad in decodebin.pads) {
            string caps = pad.caps.to_string();
            if (caps.has_prefix(prefix)) {
                return pad;
            }
        }
        return null;
    }

    protected override void on_state_change(Gst.Bus bus, Gst.Message message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_state_change");
        if (message.src != pipeline)
            return;

        Gst.State old_state;
        Gst.State new_state;
        Gst.State pending;

        message.parse_state_changed(out old_state, out new_state, out pending);
        if (new_state == old_state) 
            return;

        if (new_state == Gst.State.PLAYING) {
            Gst.Pad? pad = get_pad("video");
            if (pad != null) {
                clipfile.video_caps = pad.caps;
            }

            pad = get_pad("audio");
            if (pad != null) {
                clipfile.audio_caps = pad.caps;
            }

            Gst.Format format = Gst.Format.TIME;
            if (!pipeline.query_duration(ref format, out clipfile.length) ||
                    format != Gst.Format.TIME) {
                do_error("Can't fetch length");
                return;
            }

            clipfile_online(true);
            pipeline.set_state(Gst.State.NULL);
        } else if (new_state == Gst.State.NULL) {
            ready();
        }
    }
}

public class ThumbnailFetcher : Fetcher {
    ThumbnailSink thumbnail_sink;
    Gst.Element colorspace;
    int64 seek_position;
    bool done_seek;
    bool have_thumbnail;

    public ThumbnailFetcher(ClipFile f, int64 time) throws Error {
        clipfile = f;
        seek_position = time;

        SingleDecodeBin single_bin = new SingleDecodeBin (
                                        Gst.Caps.from_string ("video/x-raw-rgb; video/x-raw-yuv"),
                                        "singledecoder", f.filename);

        pipeline = new Gst.Pipeline("pipeline");
        pipeline.set_auto_flush_bus(false);

        thumbnail_sink = new ThumbnailSink();
        thumbnail_sink.have_thumbnail += on_have_thumbnail;

        colorspace = make_element("ffmpegcolorspace");

        pipeline.add_many(single_bin, thumbnail_sink, colorspace);

        single_bin.pad_added += on_pad_added;

        colorspace.link(thumbnail_sink);

        Gst.Bus bus = pipeline.get_bus();

        bus.add_signal_watch();
        bus.message["state-changed"] += on_state_change;
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;

        have_thumbnail = false;
        done_seek = false;
        pipeline.set_state(Gst.State.PAUSED);
    }

    void on_have_thumbnail(Gdk.Pixbuf buf) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_have_thumbnail");
        if (done_seek) {
            have_thumbnail = true;
            clipfile.set_thumbnail(buf);
        }
    }

    protected override void on_pad_added(Gst.Pad pad) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_pad_added");
        Gst.Caps c = pad.get_caps();

        if (c.to_string().has_prefix("video")) {
            pad.link(colorspace.get_static_pad("sink"));
        }
    }

    protected override void on_state_change(Gst.Bus bus, Gst.Message message) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_state_change");
        if (message.src != pipeline)
            return;

        Gst.State new_state;
        Gst.State old_state;
        Gst.State pending_state;

        message.parse_state_changed (out old_state, out new_state, out pending_state);
        if (new_state == old_state &&
            new_state != Gst.State.PAUSED)
            return;

        if (new_state == Gst.State.PAUSED) {
            if (!done_seek) {
                done_seek = true;
                pipeline.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, seek_position);
            } else {
                if (have_thumbnail)
                    pipeline.set_state(Gst.State.NULL);
            }
        } else if (new_state == Gst.State.NULL) {
            ready();
        }
    }
}

public class Clip : Object {
    public ClipFile clipfile;
    public MediaType type;
    // TODO: If a clip is being recorded, we don't want to set duration in the MediaClip file.
    // Address when handling multiple track recording.  This is an ugly hack.
    public bool is_recording;
    public string name;
    int64 _start;
    public int64 start { 
        get {
            return _start;
        }

        set {
            _start = value;
            if (connected) {
                start_changed(_start);
            }
            moved(this);
        }
    }

    int64 _media_start;
    public int64 media_start { 
        get {
            return _media_start;
        }
    }

    int64 _duration;
    public int64 duration {
        get {
            return _duration;
        }

        set {
            if (value < 0) {
                // saturating the duration
                value = 0;
            }

            if (!is_recording) {
                if (value + _media_start > clipfile.length) {
                    // saturating the duration
                    value = clipfile.length - media_start;
                }
            }

            _duration = value;
            if (connected) {
                duration_changed(_duration);
            }
            moved(this);
        }
    }

    bool connected;

    public int64 end {
        get { return start + duration; }
    }

    public signal void moved(Clip clip);
    public signal void updated(Clip clip);
    public signal void media_start_changed(int64 media_start);
    public signal void duration_changed(int64 duration);
    public signal void start_changed(int64 start);
    public signal void removed(Clip clip);

    public Clip(ClipFile clipfile, MediaType t, string name,
                int64 start, int64 media_start, int64 duration, bool is_recording) {
        this.is_recording = is_recording;
        this.clipfile = clipfile;
        this.type = t;
        this.name = name;
        this.connected = clipfile.is_online();
        this.set_media_start_duration(media_start, duration);
        this.start = start;

        clipfile.updated += on_clipfile_updated;
    }

    public void gnonlin_connect() { connected = true; }
    public void gnonlin_disconnect() { connected = false; }

    void on_clipfile_updated(ClipFile f) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clipfile_updated");
        if (f.is_online()) {
            if (!connected) {
                connected = true;
                // TODO: Assigning to oneself has the side-effect of firing signals. 
                // fire signals directly.  Make certain that loading a file still works
                // properly in this case.
                set_media_start_duration(media_start, duration);
                start = start;
            }
        } else {
            if (connected) {
                connected = false;
            }
        }
        updated(this);
    }

    public bool overlap_pos(int64 start, int64 length) {
        return start < this.start + this.duration &&
                this.start < start + length;
    }

    public int64 snap(Clip other, int64 pad) {
        if (time_in_range(start, other.start, pad)) {
            return other.start;
        } else if (time_in_range(start, other.end, pad)) {
            return other.end;
        } else if (time_in_range(end, other.start, pad)) {
            return other.start - duration;
        } else if (time_in_range(end, other.end, pad)) {
            return other.end - duration;
        }
        return start;
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
        return new Clip(clipfile, type, name, start, media_start, duration, false);
    }

    public bool is_trimmed() {
        if (!clipfile.is_online()) 
            return false;
        return duration != clipfile.length;
    }

    public void trim(int64 delta, Gdk.WindowEdge edge) {
        switch (edge) {
            case Gdk.WindowEdge.WEST:
                if (media_start + delta < 0) {
                    delta = -media_start;
                }

                if (duration - delta < 0) {
                    delta = duration;
                }

                start += delta;
                set_media_start_duration(media_start + delta, duration - delta);
                break;
            case Gdk.WindowEdge.EAST:
                duration += delta;
                break;
        }
    }

    public void set_media_start_duration(int64 media_start, int64 duration) {
        if (media_start < 0) {
            media_start = 0;
        }

        if (duration < 0) {
            duration = 0;
        }

        if (media_start + duration > clipfile.length) {
            // We are saturating the value
            media_start = clipfile.length - duration;
        }

        _media_start = media_start;
        _duration = duration;

        if (connected) {
            media_start_changed(_media_start);
            duration_changed(_duration);
        }

        moved(this);
    }

    public void save(FileStream f, int id) {
        f.printf(
            "      <clip id=\"%d\" name=\"%s\" start=\"%" + int64.FORMAT + "\" " +
                    "media-start=\"%" + int64.FORMAT + "\" duration=\"%" + int64.FORMAT + "\"/>\n",
                    id, name, start, media_start, duration);
    }
}

public class FetcherCompletion {
    public FetcherCompletion() {
    }

    public virtual void complete(ClipFetcher fetcher) {
    }
}
}
