/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace Model {

class VideoProject : Project {
    public TimecodeTimeSystem time_provider;

    public override void load_complete() {
        if (find_video_track() == null) {
            add_track(new VideoTrack(this));
        }
    }

    public VideoProject(string? filename) throws Error {
        base(filename, true);
        // TODO: When vala supports throwing from base constructor remove this check
        if (this != null) {
            time_provider = new TimecodeTimeSystem();
        }
    }

    public override double get_version() {
        return 0.1;
    }

    public override string get_app_name() {
        return App.NAME;
    }

    public override TimeCode get_clip_time(ClipFile f) {
        TimeCode t = {};

        if (f.is_of_type(MediaType.VIDEO)) {
            Fraction rate;
            if (!get_framerate_fraction(out rate)) {
                rate.numerator = 2997;
                rate.denominator = 100;
            }
            t = frame_to_time(time_to_frame_with_rate(f.length, rate), rate);
        } else
            t.get_from_length(f.length);
            
        return t;
    }

    VideoTrack? find_video_track() {
        foreach (Track track in tracks) {
            if (track is VideoTrack) {
                return track as VideoTrack;
            }
        }
        return null;
    }

    protected override void do_append(Track track, ClipFile clipfile, string name, int64 insert_time) {
        string description = "Append Clip";
        undo_manager.start_transaction(description);
        if (clipfile.video_caps != null) {
            Track? video_track = find_video_track();
            if (video_track != null && track != video_track) {
                Clip clip = new Clip(clipfile, MediaType.VIDEO, name, 0, 0, clipfile.length, false);
                video_track.append_at_time(clip, insert_time, true);
            }
        }
        base.do_append(track, clipfile, name, insert_time);
        undo_manager.end_transaction(description);
    }

    public void go_previous_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            media_engine.go(video_track.previous_frame(transport_get_position()));
        }
    }

    public void go_next_frame() {
        VideoTrack? video_track = find_video_track();
        if (video_track != null) {
            media_engine.go(video_track.next_frame(transport_get_position()));
        }
    }

    public bool get_framerate_fraction(out Fraction rate) {
        foreach (Track track in tracks) {
            VideoTrack video_track = track as VideoTrack;
            if (video_track != null && video_track.get_framerate(out rate))
                return true;
        }
        return false;
    }
}
}
