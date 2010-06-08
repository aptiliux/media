/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class TrackSeparator : Gtk.HSeparator {
//this class is referenced in the resource file
}

class FillmoreTrackView : Gtk.VBox, TrackView {
    TrackView track_view;
    public FillmoreTrackView(TrackView track_view) {
        this.track_view = track_view;
        track_view.clip_view_added.connect(on_clip_view_added);

        pack_start(track_view, true, true, 0);
        pack_start(new TrackSeparator(), false, false, 0);
        can_focus = false;
    }

    public void move_to_top(ClipView clip_view) {
        track_view.move_to_top(clip_view);
    }

    public void resize() {
        track_view.resize();
    }

    public Model.Track get_track() {
        return track_view.get_track();
    }

    public int get_track_height() {
        return track_view.get_track_height();
    }

    void on_clip_view_added(ClipView clip_view) {
        clip_view_added(clip_view);
    }

    Gtk.Widget? find_child(double x, double y) {
        return track_view.find_child(x, y);
    }

    void select_all() {
        track_view.select_all();
    }
}

public class FillmoreClassFactory : ClassFactory {
    public override TrackView get_track_view(Model.Track track, TimeLine timeline) {
        TrackView track_view = base.get_track_view(track, timeline);
        return new FillmoreTrackView(track_view);
    }
}
