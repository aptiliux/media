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
    Track track;
    Clip clip;
    int64 time;
    
    public ClipCommand(Track track, Clip clip, int64 time) {
        this.track = track;
        this.clip = clip;
        this.time = time;
    }
    
    public override void apply() {
        track._append_at_time(clip, time);
    }
    
    public override void undo() {
        track.delete_clip(clip, false);
    }
    
    public override bool merge(Command command) {
        return false;
    }
    
    public override string description() {
        return "Create Clip";
    }
}

public class TransactionCommand : Command {
    bool open;
    public TransactionCommand(bool open) {
        this.open = open;
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
        assert(false); // we should never display the description of a transaction
        return "";
    }
}
}
