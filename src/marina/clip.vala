/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace Model {

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

public abstract class Fetcher : Object {
    protected Gst.Element filesrc;
    protected Gst.Element decodebin;
    protected Gst.Pipeline pipeline;

    public MediaFile mediafile;
    public string error_string;

    protected abstract void on_pad_added(Gst.Pad pad);
    protected abstract void on_state_change(Gst.Bus bus, Gst.Message message);

    public signal void ready(Fetcher fetcher);

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
    public signal void mediafile_online(bool online);

    public ClipFetcher(string filename) throws Error {
        ClassFactory class_factory = ClassFactory.get_class_factory();
        mediafile = class_factory.get_media_file(filename, 0);

        mediafile_online.connect(mediafile.set_online);

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
        decodebin.pad_added.connect(on_pad_added);

        Gst.Bus bus = pipeline.get_bus();

        bus.add_signal_watch();
        bus.message["state-changed"] += on_state_change;
        bus.message["error"] += on_error;
        bus.message["warning"] += on_warning;

        error_string = null;
        pipeline.set_state(Gst.State.PLAYING);
    }

    public string get_filename() { return mediafile.filename; }

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
                mediafile.set_caps(MediaType.VIDEO, pad.caps);
            }

            pad = get_pad("audio");
            if (pad != null) {
                mediafile.set_caps(MediaType.AUDIO, pad.caps);
            }

            Gst.Format format = Gst.Format.TIME;
            int64 length;
            if (!pipeline.query_duration(ref format, out length) ||
                    format != Gst.Format.TIME) {
                do_error("Can't fetch length");
                return;
            }
            mediafile.length = length;

            mediafile_online(true);
            pipeline.set_state(Gst.State.NULL);
        } else if (new_state == Gst.State.NULL) {
            ready(this);
        }
    }
}

public class ThumbnailFetcher : Fetcher {
    ThumbnailSink thumbnail_sink;
    Gst.Element colorspace;
    int64 seek_position;
    bool done_seek;
    bool have_thumbnail;

    public ThumbnailFetcher(MediaFile f, int64 time) throws Error {
        mediafile = f;
        seek_position = time;

        SingleDecodeBin single_bin = new SingleDecodeBin (
                                        Gst.Caps.from_string ("video/x-raw-rgb; video/x-raw-yuv"),
                                        "singledecoder", f.filename);

        pipeline = new Gst.Pipeline("pipeline");
        pipeline.set_auto_flush_bus(false);

        thumbnail_sink = new ThumbnailSink();
        thumbnail_sink.have_thumbnail.connect(on_have_thumbnail);

        colorspace = make_element("ffmpegcolorspace");

        pipeline.add_many(single_bin, thumbnail_sink, colorspace);

        single_bin.pad_added.connect(on_pad_added);

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
            mediafile.set_thumbnail(buf);
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
            ready(this);
        }
    }
}

public class Clip : Object {
    public MediaFile mediafile;
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
                if (value + _media_start > mediafile.length) {
                    // saturating the duration
                    value = mediafile.length - media_start;
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

    public Clip(MediaFile mediafile, MediaType t, string name,
                int64 start, int64 media_start, int64 duration, bool is_recording) {
        this.is_recording = is_recording;
        this.mediafile = mediafile;
        this.type = t;
        this.name = name;
        this.connected = mediafile.is_online();
        this.set_media_start_duration(media_start, duration);
        this.start = start;
        mediafile.updated.connect(on_mediafile_updated);
    }

    public void gnonlin_connect() { connected = true; }
    public void gnonlin_disconnect() { connected = false; }

    void on_mediafile_updated(MediaFile f) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_mediafile_updated");
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
        return new Clip(mediafile, type, name, start, media_start, duration, false);
    }

    public bool is_trimmed() {
        if (!mediafile.is_online()) 
            return false;
        return duration != mediafile.length;
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

        if (mediafile.is_online() && media_start + duration > mediafile.length) {
            // We are saturating the value
            media_start = mediafile.length - duration;
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

    public virtual void complete(Fetcher fetcher) {
    }
}
}
