/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
public abstract class Command {
    public abstract void apply();
    public abstract void undo();
    public abstract bool merge(Command command);
    public abstract string description();
}

public enum Parameter { PAN, VOLUME }

public class ParameterCommand : Command {
    AudioTrack target;
    Parameter parameter;
    double delta;
    
    public ParameterCommand(AudioTrack target, Parameter parameter, 
        double new_value, double old_value) {
        this.target = target;
        this.parameter = parameter;
        this.delta = new_value - old_value;
    }

    void change_parameter(double amount) {
        switch (parameter) {
            case Parameter.PAN:
                target._set_pan(target.get_pan() + amount);
                break;
            case Parameter.VOLUME:
                target._set_volume(target.get_volume() + amount);
                break;
        }
    }
    
    public override void apply() {
        change_parameter(delta);
    }
    
    public override void undo() {
        change_parameter(-delta);
    }
    
    public override bool merge(Command command) {
        ParameterCommand parameter_command = command as ParameterCommand;
        if (parameter_command != null && parameter_command.parameter == parameter) {
            delta = delta + parameter_command.delta;
            return true;
        }
        return false;
    }
    
    public override string description() {
        switch (parameter) {
            case Parameter.PAN:
                return "Adjust Pan";
            case Parameter.VOLUME:
                return "Adjust Level";
            default:
                assert(false);
                return "";
        }
    }
}

public class ClipCommand : Command {
    public enum Action { APPEND, DELETE }
    Track track;
    Clip clip;
    int64 time;
    Action action;
    int index;
    bool select;
    
    public ClipCommand(Action action, Track track, Clip clip, int64 time, bool select) {
        this.track = track;
        this.clip = clip;
        this.time = time;
        this.action = action;
        this.select = select;
        this.index = track.get_clip_index(clip);
    }
    
    public override void apply() {
        switch(action) {
            case Action.APPEND:
                track._append_at_time(clip, time, select);
                break;
            case Action.DELETE:
                track._delete_clip(clip);
                break;
            default:
                assert(false);
                break;
        }
    }
    
    public override void undo() {
        switch(action) {
            case Action.APPEND:
                track._delete_clip(clip);
                break;
            case Action.DELETE:
                track.add(clip, time, false);
                break;
            default:
                assert(false);
                break;
        }
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        switch(action) {
            case Action.APPEND:
                return "Create Clip";
            case Action.DELETE:
                return "Delete Clip";
            default:
                assert(false);
                return "";
        }
    }
}

public class ClipAddCommand : Command {
    Track track;
    Clip clip;
    int64 delta;
    
    public ClipAddCommand(Track track, Clip clip, int64 original_time, 
        int64 new_start) {
        this.track = track;
        this.clip = clip;
        this.delta = new_start - original_time;
    }
    
    public override void apply() {
        track._move(clip, clip.start);
    }
    
    public override void undo() {
        track.remove_clip_from_array(clip);     
        track._move(clip, clip.start - delta);
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return "Move Clip";
    }
}

public class ClipSplitCommand : Command {
    Track track;
    int64 time;
    bool do_split;
    
    public enum Action { SPLIT, JOIN }

    public ClipSplitCommand(Action action, Track track, int64 time) {
        this.track = track;
        this.time = time;
        do_split = action == Action.SPLIT;
    }
    
    public override void apply() {
        if (do_split) {
            track._split_at(time);
        } else {
            track._join(time);
        }
    }
    
    public override void undo() {
        if (do_split) {
            track._join(time);
        } else {
            track._split_at(time);
        }
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        if (do_split) {
            return "Split Clip";
        } else {
            return "Join Clip";
        }
    }
}

public class ClipFileDeleteCommand : Command {
    ClipFile clipfile;
    Project project;
    
    public ClipFileDeleteCommand(Project p, ClipFile cf) {
        clipfile = cf;
        project = p;
    }
    
    public override void apply() {
        project._remove_clipfile(clipfile);
    }
    
    public override void undo() {
        project.add_clipfile(clipfile);
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return "Delete from Library";
    }
}

public class ClipTrimCommand : Command {
    Track track;
    Clip clip;
    int64 delta;
    Gdk.WindowEdge edge;
    
    public ClipTrimCommand(Track track, Clip clip, int64 delta, Gdk.WindowEdge edge) {
        this.track = track;
        this.clip = clip;
        this.delta = delta;
        this.edge = edge;
    }
    
    public override void apply() {
        track._trim(clip, delta, edge);
    }
    
    public override void undo() {
        track._trim(clip, -delta, edge);
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return "Trim To Playhead";
    }
}

public class ClipRevertCommand : Command {
    Track track;
    Clip clip;
    int64 left_delta;
    int64 right_delta;
    
    public ClipRevertCommand(Track track, Clip clip) {
        this.track = track;
        this.clip = clip;
    }

    public override void apply() {
        right_delta = clip.end;
        left_delta = clip.media_start;
        track._revert_to_original(clip);
        left_delta -= clip.media_start;
        right_delta = clip.end - right_delta - left_delta;
    }
    
    public override void undo() {
        track._trim(clip, -left_delta, Gdk.WindowEdge.WEST);
        track._trim(clip, -right_delta, Gdk.WindowEdge.EAST);
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return "Revert To Original";
    }
}

public class TimeSignatureCommand : Command {
    Fraction new_time_signature;
    Fraction old_time_signature;
    Project project;
    
    public TimeSignatureCommand(Project project, Fraction new_time_signature) {
        this.project = project;
        this.new_time_signature = new_time_signature;
        this.old_time_signature = project.get_time_signature();
    }

    public override void apply() {
        project._set_time_signature(new_time_signature);
    }

    public override void undo() {
        project._set_time_signature(old_time_signature);
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return "Set Time Signature";
    }
}

public class BpmCommand : Command {
    int delta;
    Project project;
    
    public BpmCommand(Project project, int new_bpm) {
        delta = new_bpm - project.get_bpm();
        this.project = project;
    }
    
    public override void apply() {
        project._set_bpm(project.get_bpm() + delta);
    }
    
    public override void undo() {
        project._set_bpm(project.get_bpm() - delta);
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return "Set Tempo";
    }
}

public class TransactionCommand : Command {
    bool open;
    string transaction_description;
    
    public TransactionCommand(bool open, string transaction_description) {
        this.open = open;
        this.transaction_description = transaction_description;
    }
    
    public bool in_transaction() {
        return open;
    }
    
    public override void apply() {
    }
    
    public override void undo() {
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return transaction_description;
    }
}
}
