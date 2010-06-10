/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface TrackView : Gtk.Widget {
    public signal void clip_view_added(ClipView clip_view);
    public abstract void move_to_top(ClipView clip_view);
    public abstract void resize();
    public abstract Model.Track get_track();
    public abstract int get_track_height();
    public abstract Gtk.Widget? find_child(double x, double y);
    public abstract void select_all();
}

public class ClassFactory {
    static ClassFactory class_factory = null;
    static TransportDelegate transport_delegate = null;

    public static ClassFactory get_class_factory() {
        return class_factory;
    }

    public virtual TrackView get_track_view(Model.Track track, TimeLine timeline) {
        assert(transport_delegate != null);
        return new TrackViewConcrete(transport_delegate, track, timeline);
    }

    public virtual Model.ClipFile get_clip_file(string filename, int64 duration) {
        return new Model.ClipFileConcrete(filename, duration);
    }

    public static void set_class_factory(ClassFactory class_factory) {
        ClassFactory.class_factory = class_factory;
    }

    public static void set_transport_delegate(TransportDelegate transport_delegate) {
        ClassFactory.transport_delegate = transport_delegate;
    }
}
