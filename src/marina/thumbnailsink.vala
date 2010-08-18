class ThumbnailSink : Gst.BaseSink {
    int width;
    int height;

    const string caps_string = """video/x-raw-rgb,bpp = (int) 32, depth = (int) 32,
                                  endianness = (int) BIG_ENDIAN,
                                  blue_mask = (int)  0xFF000000,
                                  green_mask = (int) 0x00FF0000,
                                  red_mask = (int)   0x0000FF00,
                                  width = (int) [ 1, max ],
                                  height = (int) [ 1, max ],
                                  framerate = (fraction) [ 0, max ]""";

    public signal void have_thumbnail(Gdk.Pixbuf b);

    class construct {
        Gst.StaticPadTemplate pad;
        pad.name_template = "sink";
        pad.direction = Gst.PadDirection.SINK;
        pad.presence = Gst.PadPresence.ALWAYS;
        pad.static_caps.str = caps_string;

        add_pad_template(pad.get());
    }

    public ThumbnailSink() {
        Object();
        set_sync(false);
    }

    public override bool set_caps(Gst.Caps c) {
        if (c.get_size() < 1)
            return false;

        Gst.Structure s = c.get_structure(0);

        if (!s.get_int("width", out width) ||
            !s.get_int("height", out height))
            return false;
        return true;
    }

    void convert_pixbuf_to_rgb(Gdk.Pixbuf buf) {
        uchar* data = buf.get_pixels();
        int limit = buf.get_width() * buf.get_height();

        while (limit-- != 0) {
            uchar temp = data[0];
            data[0] = data[2];
            data[2] = temp;

            data += 4;
        }
    }

    public override Gst.FlowReturn preroll(Gst.Buffer b) {
        Gdk.Pixbuf buf = new Gdk.Pixbuf.from_data(b.data, Gdk.Colorspace.RGB, 
                                                    true, 8, width, height, width * 4, null);
        convert_pixbuf_to_rgb(buf);

        have_thumbnail(buf);
        return Gst.FlowReturn.OK;
    }
}
