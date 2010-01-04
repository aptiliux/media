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
}

public class ClassFactory {
    static ClassFactory class_factory = null;

    public static ClassFactory get_class_factory() {
        return class_factory;
    }

    public virtual TrackView get_track_view(Model.Track track, TimeLine timeline) {
        return new TrackViewConcrete(track, timeline);
    }
    
    public static void set_class_factory(ClassFactory class_factory) {
        ClassFactory.class_factory = class_factory;
    }
}
