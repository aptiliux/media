/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
namespace Model {

public enum MediaType {
    AUDIO,
    VIDEO
}

public abstract class MediaFile : Object {
    public abstract string filename {
        get;
        set;
    }

    public abstract int64 length {
        get;
        set;
    }

    public abstract Gst.Caps? get_caps(MediaType type);
    public abstract void set_caps(MediaType type, Gst.Caps caps);
    public abstract Gdk.Pixbuf? get_thumbnail();

    public signal void updated();

    public abstract bool is_online();
    public abstract void set_online(bool o);
    public abstract void set_thumbnail(Gdk.Pixbuf b);

    public abstract bool get_frame_rate(out Fraction rate);
    public abstract bool get_dimensions(out int w, out int h);
    public abstract bool get_sample_rate(out int rate);
    public abstract bool get_video_format(out uint32 fourcc);
    public abstract bool get_num_channels(out int channels);
    public abstract bool get_num_channels_string(out string s);
}
}
