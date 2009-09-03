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
}
