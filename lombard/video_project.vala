/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace Model {

class VideoProject : Project {
    public TimecodeTimeSystem time_provider;
    
    Gee.ArrayList<ThumbnailFetcher> pending = new Gee.ArrayList<ThumbnailFetcher>();

    public VideoProject(string? filename) {
        base(filename, true);
        time_provider = new TimecodeTimeSystem();
    }
    
    public override double get_version() {
        return 0.01;
    }
    
    public override string get_app_name() {
        return App.NAME;
    }

    public override void add_track(Track track) {
        foreach (Track existing_track in tracks) {
            if (track.media_type() == existing_track.media_type()) {
                add_inactive_track(track);
                return;
            }
        }
        
        base.add_track(track);
    }

    public override void add_clipfile(ClipFile f) {
        base.add_clipfile(f);
        if (f.is_online() &&
            f.is_of_type(MediaType.VIDEO)) {
            ThumbnailFetcher fetcher = new ThumbnailFetcher(f, 0);
            fetcher.ready += on_thumbnail_ready;
            pending.add(fetcher);
        } else
            clipfile_added(f);
    }

    void on_thumbnail_ready(ThumbnailFetcher f) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_thumbnail_ready");
        clipfile_added(f.clipfile);
        pending.remove(f);
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

    protected override void do_append(ClipFile clipfile, string name, int64 insert_time) {
        undo_manager.start_transaction();
        if (clipfile.video_caps != null) {
            Clip clip = new Clip(clipfile, MediaType.VIDEO, name, 0, 0, clipfile.length, false);
            Track? track = find_video_track();
            if (track != null) {
                track.append_at_time(clip, insert_time);
            }
        }
        base.do_append(clipfile, name, insert_time);
        undo_manager.end_transaction();
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
