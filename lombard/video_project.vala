/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
class VideoProject : Project {

    public VideoProject() {
        base();
    }
    
    protected override void do_append(ClipFile clipfile, string name, int64 insert_time) {
        if (clipfile.video_caps != null) {
            Clip clip = new Clip(clipfile, MediaType.VIDEO, name, 0, 0, clipfile.length);
            Track? track = find_video_track();
            if (track != null) {
                track.append_at_time(clip, insert_time);
            }
        }
        base.do_append(clipfile, name, insert_time);
    }
    
    public void set_output_widget(Gtk.Widget widget) {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            video_track.set_output_widget(widget); 
        }
    }

    public int get_current_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            return video_track.get_current_frame(position);
        }
        return 0;
    }

    public void go_previous_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            go(video_track.previous_frame(position));
        }
    }
    
    public void go_next_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            go(video_track.next_frame(position));
        }
    }

    public bool get_framerate_fraction(out Fraction rate) {
        bool return_value = false;
        foreach (Track track in tracks) {
            if (track.get_framerate(out rate))
                return_value = true;
        }
        return return_value;
    }
    
    public int get_framerate() {
        Fraction r;
        if (!get_framerate_fraction(out r))
            return 0;
        
        if (r.numerator == 2997 &&
            r.denominator == 100)
            return 30;
        return r.numerator / r.denominator;
    }
}
}