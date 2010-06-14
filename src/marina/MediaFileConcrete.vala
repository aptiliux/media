/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
 using Logging;
 
namespace Model {
public class MediaFileConcrete : MediaFile {
    public string _filename;
    public override string filename {
        public get {
            return _filename;
        }
        public set {
            _filename = value;
        }
    }

    int64 _length;
    public override int64 length {
        public get {
            if (!online) {
                warning("retrieving length while clip offline");
            }
            return _length;
        }
        
        public set {
            _length = value;
        }
    }

    bool online;

    public Gst.Caps video_caps;    // or null if no video
    public Gst.Caps audio_caps;    // or null if no audio
    public Gdk.Pixbuf thumbnail = null;

    public MediaFileConcrete(string filename, int64 length = 0) {
        this.filename = filename;
        this.length = length;
        online = false;
    }

    public override Gst.Caps? get_caps(MediaType media_type) {
        switch (media_type) {
            case MediaType.AUDIO:
                return audio_caps;
            case MediaType.VIDEO:
                return video_caps;
        }
        return null;
    }

    public override void set_caps(MediaType media_type, Gst.Caps caps) {
        switch (media_type) {
            case MediaType.AUDIO:
                audio_caps = caps;
            break;
            case MediaType.VIDEO:
                video_caps = caps;
            break;
        }
    }

    public override Gdk.Pixbuf? get_thumbnail() {
        return thumbnail;
    }

    public override bool is_online() {
        return online;
    }

    public override void set_online(bool o) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "set_online");
        online = o;
        updated();
    }

    public override void set_thumbnail(Gdk.Pixbuf b) {
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

    public override bool get_frame_rate(out Fraction rate) {
        Gst.Structure structure;
        if (!get_caps_structure(MediaType.VIDEO, out structure))
            return false;
        return structure.get_fraction("framerate", out rate.numerator, out rate.denominator);
    }

    public override bool get_dimensions(out int w, out int h) {
        Gst.Structure s;

        if (!get_caps_structure(MediaType.VIDEO, out s))
            return false;

        return s.get_int("width", out w) && s.get_int("height", out h);
    }

    public override bool get_sample_rate(out int rate) {
        Gst.Structure s;
        if (!get_caps_structure(MediaType.AUDIO, out s))
            return false;

        return s.get_int("rate", out rate);
    }

    public override bool get_video_format(out uint32 fourcc) {
        Gst.Structure s;

        if (!get_caps_structure(MediaType.VIDEO, out s))
            return false;

        return s.get_fourcc("format", out fourcc);
    }

    public override bool get_num_channels(out int channels) {
        Gst.Structure s;
        if (!get_caps_structure(MediaType.AUDIO, out s)) {
            return false;
        }

        return s.get_int("channels", out channels);
    }

    public override bool get_num_channels_string(out string s) {
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
}
