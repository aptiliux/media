/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace Model {

public abstract class Track : Object {
    protected weak Project project;
    public Gee.ArrayList<Clip> clips = new Gee.ArrayList<Clip>();  // all clips, sorted by time
    public string display_name;
    bool is_selected;

    public signal void clip_added(Clip clip, bool select);
    public signal void clip_removed(Clip clip);

    public signal void track_renamed(Track track);
    public signal void track_selection_changed(Track track);
    public signal void track_hidden(Track track);
    public signal void track_removed(Track track);
    public signal void error_occurred(string major_error, string? minor_error);

    public Track(Project project, string display_name) {
        this.project = project;
        this.display_name = display_name;
    }

    protected abstract string name();
    public abstract MediaType media_type();

    public void hide() {
        track_hidden(this);
    }

    public bool contains_clipfile(ClipFile f) {
        foreach (Clip c in clips) {
            if (c.clipfile == f)
                return true;
        }
        return false;
    }

    protected abstract bool check(Clip clip);

    public int64 get_time_from_pos(Clip clip, bool after) {
        if (after)
            return clip.start + clip.duration;
        else
            return clip.start;
    }

    int get_clip_from_time(int64 time) {
        for (int i = 0; i < clips.size; i++) {
            if (time >= clips[i].start &&
                time < clips[i].end)
                return i;
        }
        return -1;
    }

    public int64 snap_clip(Clip c, int64 span) {
        foreach (Clip cl in clips) {
            int64 new_start = c.snap(cl, span);
            if (new_start != c.start) {
                return new_start;
            }
        }
        return c.start;
    }

    public bool snap_coord(out int64 coord, int64 span) {
        foreach (Clip c in clips) {
            if (c.snap_coord(out coord, span))
                return true;
        }
        return false;
    }

    public bool clip_is_near(Model.Clip clip, int64 range, out int64 adjustment) {
        foreach (Clip potential_clip in clips) {
            if (potential_clip != clip) {
                int64 difference = clip.start - potential_clip.end;
                if (difference.abs() < range) {
                    adjustment = -difference;
                    return true;
                }

                difference = potential_clip.start - clip.end;
                if (difference.abs() < range) {
                    adjustment = difference;
                    return true;
                }
            }
        }
        return false;
    }

    int get_insert_index(int64 time) {
        int end_ret = 0;
        for (int i = 0; i < clips.size; i++) {
            Clip c = clips[i];

            if (time >= c.start) {
                if (time < c.start + c.duration/2)
                    return i;
                else if (time < c.start + c.duration)
                    return i + 1;
                else
                    end_ret ++;
            }
        }
        return end_ret;
    }

    // This is called to find the first gap after a start time
    public Gap find_first_gap(int64 start) {
        int64 new_start = 0;
        int64 new_end = int64.MAX;

        foreach (Clip c in clips) {
            if (c.start > new_start &&
                c.start > start) {
                new_end = c.start;
                break;
            }
            new_start = c.end;
        }
        return new Gap(new_start, new_end);
    }

    // This is always called with the assumption that we are not on a clip
    int get_gap_index(int64 time) {
        int i = 0;
        while (i < clips.size) {
            if (time <= clips[i].start)
                break;
            i++;
        }
        return i;
    }

    // If we are not on a valid gap (as in, a space between two clips or between the start
    // and the first clip), we return an empty (and invalid) gap
    public void find_containing_gap(int64 time, out Gap g) {
        g = new Gap(0, 0);

        int index = get_gap_index(time);
        if (index < clips.size) {
            g.start = index > 0 ? clips[index - 1].end : 0;
            g.end = clips[index].start;
        }
    }

    public Clip? find_overlapping_clip(int64 start, int64 length) {
        for (int i = 0; i < clips.size; i++) {
            Clip c = clips[i];
            if (c.overlap_pos(start, length))
                return c;
        }
        return null;
    }

    public Clip? find_nearest_clip_edge(int64 time, out bool after) {
        int limit = clips.size * 2;
        int64 prev_time = clips[0].start;

        for (int i = 1; i < limit; i++) {
            Clip c = clips[i / 2];
            int64 t;

            if (i % 2 == 0)
                t = c.start;
            else
                t = c.end;

            if (t > time) {
                if (t - time < time - prev_time) {
                    after = ((i % 2) != 0);
                    return clips[i / 2];
                } else {
                    after = ((i % 2) == 0);
                    return clips[(i - 1) / 2];
                }
            }
            prev_time = t;
        }

        after = true;
        return clips[clips.size - 1];
    }

    void do_clip_overwrite(Clip c) {
        int start_index = get_clip_from_time(c.start);
        int end_index = get_clip_from_time(c.end);

        if (end_index >= 0) {
            int64 diff = c.end - clips[end_index].start;
            if (end_index == start_index) {
                if (c == clips[end_index]) {
                    return;
                }

                if (diff > 0) {
                    Clip cl = new Clip(clips[end_index].clipfile, clips[end_index].type, 
                                    clips[end_index].name, c.end, 
                                    clips[end_index].media_start + diff,
                                    clips[end_index].duration - diff, false);
                    add(cl, cl.start, false);
                }
            } else {
                clips[end_index].set_media_start_duration(
                    clips[end_index].media_start + diff,
                    clips[end_index].duration - diff);
                clips[end_index].start = c.end;
            }
        }
        if (start_index >= 0 && clips[start_index] != c) {
            clips[start_index].duration = c.start - clips[start_index].start;
        }

        int i = 0;
        while (i < clips.size) {
            if (clips[i] != c && 
                clips[i].start >= c.start &&
                clips[i].end <= c.end) {
                _delete_clip(clips[i]);
            }
            else
                i++;
        }
    }

    public void move(Clip c, int64 pos, int64 original_time) {
        Command command = new ClipAddCommand(this, c, original_time, pos);
        project.do_command(command);
    }

    public void _move(Clip c, int64 pos) {
        if (pos < 0) {
            pos = 0;
        }
        c.start = pos;
        do_clip_overwrite(c);

        insert_clip_into_array(c, get_insert_index(c.start));
        project.reseek();
    }

    public void add(Clip c, int64 pos, bool select) {
        if (!check(c))
            return;

        _move(c, pos);
        clip_added(c, select);
    }

    public virtual void on_clip_updated(Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_updated");    
    }

    public void do_clip_paste(Clip clip, int64 position, bool new_clip) {
        if (new_clip)
            add(clip, position, true);
        else
            _move(clip, position);
    }

    public Clip? get_clip(int i) {
        if (i < 0 || i >= clips.size)
            error("get_clip: Invalid index! %d (%d)", i, clips.size);
        return clips[i];
    }

    public int get_clip_index(Clip c) {
        for (int i = 0; i < clips.size; i++) {
            if (clips[i] == c) {
                return i;
            }
        }
        return -1;
    }

    public Clip? get_clip_by_position(int64 pos) {
        int length = clips.size;

        for (int i = length - 1; i >= 0; i--)
            if (clips[i].start < pos)
                return pos >= clips[i].end ? null : clips[i];
        return null;
    }

    public int64 get_length() {
        return clips.size == 0 ? 0 : clips[clips.size - 1].start + clips[clips.size - 1].duration;
    }

    public void _append_at_time(Clip c, int64 time, bool select) {
        add(c, time, select);
    }

    public void append_at_time(Clip c, int64 time, bool select) {
        Command command = new ClipCommand(ClipCommand.Action.APPEND, this, c, time, select);
        project.do_command(command);
    }

    public void delete_clip(Clip clip) {
        Command clip_command = new ClipCommand(ClipCommand.Action.DELETE, 
            this, clip, clip.start, false);
        project.do_command(clip_command);
    }

    public void _delete_clip(Clip clip) {
        int index = get_clip_index(clip);
        assert(index != -1);
        clips.remove_at(index);

        clip.removed(clip);
        clip_removed(clip);
    }

    public void delete_gap(Gap g) {
        project.reseek();
    }

    public void remove_clip_from_array(Clip pos) {
        clips.remove(pos);
    }

    void insert_clip_into_array(Clip c, int pos) {
        c.updated += on_clip_updated;
        clips.insert(pos, c);
    }

    public void delete_all_clips() {
        uint size = clips.size;
        for (int i = 0; i < size; i++) { 
            delete_clip(clips[0]);
        }
        project.media_engine.go(0);
    }

    public void revert_to_original(Clip clip) {
        Command command = new ClipRevertCommand(this, clip);
        project.do_command(command);
    }

    public void _revert_to_original(Clip c) {
        int index = get_clip_index(c);
        if (index == -1)
            error("revert_to_original: Clip not in track array!");

        c.set_media_start_duration(0, c.clipfile.length);

        project.media_engine.go(c.start);
    }

    public bool are_contiguous_clips(int64 position) {
        Clip right_clip = get_clip_by_position(position + 1);
        Clip left_clip = get_clip_by_position(position - 1);

        return left_clip != null && right_clip != null && 
            left_clip != right_clip &&
            left_clip.clipfile == right_clip.clipfile &&
            left_clip.end == right_clip.start;
    }

    public void split_at(int64 position) {
        Command command = new ClipSplitCommand(ClipSplitCommand.Action.SPLIT, this, position);
        project.do_command(command);
    }

    public void _split_at(int64 position) {
        Clip c = get_clip_by_position(position);
        if (c == null)
            return;

        Clip cn = new Clip(c.clipfile, c.type, c.name, position,
                           (position - c.start) + c.media_start, 
                           c.start + c.duration - position, false);

        c.duration = position - c.start;

        add(cn, position, false);
    }

    public void join(int64 position) {
        Command command = new ClipSplitCommand(ClipSplitCommand.Action.JOIN, this, position);
        project.do_command(command);
    }

    public void _join(int64 position) {
        assert(are_contiguous_clips(position));
        if (are_contiguous_clips(position)) {
            Clip right_clip = get_clip_by_position(position + 1);
            assert(right_clip != null);

            int right_clip_index = get_clip_index(right_clip);
            assert(right_clip_index > 0);

            int left_clip_index = right_clip_index - 1;
            Clip left_clip = get_clip(left_clip_index);
            assert(left_clip != null);
            left_clip.duration = right_clip.end - left_clip.start;
            _delete_clip(right_clip);
        }
    }

    public void trim(Clip clip, int64 delta, Gdk.WindowEdge edge) {
        Command command = new ClipTrimCommand(this, clip, delta, edge);
        project.do_command(command);
    }

    public void _trim(Clip clip, int64 delta, Gdk.WindowEdge edge) {
        clip.trim(delta, edge);
        do_clip_overwrite(clip);
    }

    public int64 previous_edit(int64 pos) {
        for (int i = clips.size - 1; i >= 0 ; --i) {
            Clip c = clips[i];
            if (c.end < pos)
                return c.end;
            if (c.start < pos)
                return c.start;
        }
        return 0;
    }

    public int64 next_edit(int64 pos) {
        foreach (Clip c in clips)
            if (c.start > pos)
                return c.start;
            else if (c.end > pos)
                return c.end;
        return get_length();
    }

    public virtual void write_attributes(FileStream f) {
        f.printf("type=\"%s\" name=\"%s\" ", name(), get_display_name());
    }

    public void save(FileStream f) {
        f.printf("    <track ");
        write_attributes(f);
        f.printf(">\n");
        for (int i = 0; i < clips.size; i++)
            clips[i].save(f, project.get_clipfile_index(clips[i].clipfile));
        f.puts("    </track>\n");
    }

    public string get_display_name() {
        return display_name;
    }

    public void set_display_name(string new_display_name) {
        if (display_name != new_display_name) {
            display_name = new_display_name;
            track_renamed(this);
        }
    }

    public void set_selected(bool is_selected) {
        if (this.is_selected != is_selected) {
            this.is_selected = is_selected;
            track_selection_changed(this);
        }
    }

    public bool get_is_selected() {
        return is_selected;
    }
}

public class AudioTrack : Track {
    double pan;
    double volume;

    int default_num_channels;
    public static const int INVALID_CHANNEL_COUNT = -1;

    public signal void parameter_changed(Parameter parameter, double new_value);
    public signal void level_changed(double level_left, double level_right);
    public signal void channel_count_changed(int channel_count);

    public AudioTrack(Project project, string display_name) {
        base(project, display_name);

        set_default_num_channels(INVALID_CHANNEL_COUNT);
        _set_pan(0);
        _set_volume(1.0);
    }

    protected override string name() { return "audio"; }

    public override MediaType media_type() {
        return MediaType.AUDIO;
    }

    public override void write_attributes(FileStream f) {
        base.write_attributes(f);
        f.printf("volume=\"%f\" panorama=\"%f\" ", get_volume(), get_pan());

        int channels;
        if (get_num_channels(out channels) &&
            channels != INVALID_CHANNEL_COUNT)
            f.printf("channels=\"%d\" ", channels);
    }

    public void set_pan(double new_value) {
        double old_value = get_pan();
        if (!float_within(new_value - old_value, 0.05)) {
            ParameterCommand parameter_command = 
                new ParameterCommand(this, Parameter.PAN, new_value, old_value);
            project.do_command(parameter_command);
        }
    }

    public void _set_pan(double new_value) {
        assert(new_value <= 1.0 && new_value >= -1.0);
        double old_value = get_pan();
        if (!float_within(old_value - new_value, 0.05)) {
            pan = new_value;
            parameter_changed(Parameter.PAN, new_value);
        }
    }

    public double get_pan() {
        return pan;
    }

    public void set_volume(double new_volume) {
        double old_volume = get_volume();
        if (!float_within(old_volume - new_volume, 0.005)) {
            ParameterCommand parameter_command =
                new ParameterCommand(this, Parameter.VOLUME, new_volume, old_volume);
            project.do_command(parameter_command);
        }
    }

    public void _set_volume(double new_volume) {
        assert(new_volume >= 0.0 && new_volume <= 10.0);
        double old_volume = get_volume();
        if (!float_within(old_volume - new_volume, 0.005)) {
            volume = new_volume;
            parameter_changed(Parameter.VOLUME, new_volume);
        }
    }

    public double get_volume() {
        return volume;
    }

    public void set_default_num_channels(int num) {
        default_num_channels = num;
    }

    public bool get_num_channels(out int num) {
        if (clips.size == 0)
            return false;

        foreach (Clip c in clips) {
            if (c.clipfile.is_online()) {
                bool can = c.clipfile.get_num_channels(out num);
                assert(can);

                return can;
            }
        }

        if (default_num_channels == INVALID_CHANNEL_COUNT)
            return false;

        num = default_num_channels;
        return true;
    }

    public override bool check(Clip clip) {
        if (!clip.clipfile.is_online()) {
            return true;
        }

        if (clips.size == 0) {
            int number_of_channels = 0;
            if (clip.clipfile.get_num_channels(out number_of_channels)) {
                channel_count_changed(number_of_channels);
            }
            return true;
        }

        bool good = false;
        int number_of_channels;
        if (clip.clipfile.get_num_channels(out number_of_channels)) {
            int track_channel_count;
            if (get_num_channels(out track_channel_count)) {
                good = track_channel_count == number_of_channels;
            }
        }

        if (!good) {
            string sub_error = number_of_channels == 1 ?
                "Mono clips cannot go on stereo tracks." :
                "Stereo clips cannot go on mono tracks.";
            error_occurred("Cannot add clip to track", sub_error);
        }
        return good;
    }

    public void on_level_changed(double level_left, double level_right) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_level_changed");
        level_changed(level_left, level_right);
    }

    public override void on_clip_updated(Clip clip) {
        if (clip.clipfile.is_online()) {
            int number_of_channels = 0;
            if (get_num_channels(out number_of_channels)) {
                channel_count_changed(number_of_channels);
            }
        }
    }
}
}
