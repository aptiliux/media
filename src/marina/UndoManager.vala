/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {
public class UndoManager {
    int saved_index = 0;
    Gee.ArrayList<Command> command_list = new Gee.ArrayList<Command>();    
    public bool is_dirty { get { return saved_index != command_list.size; } }
    public bool can_undo { get { return command_list.size > 0; } }

    public signal void undo_changed(bool can_undo);
    public signal void dirty_changed(bool is_dirty);

    public class UndoManager() {
    }
    
    public void reset() {
        command_list.clear();
        saved_index = 0;
        undo_changed(false);
    }
    
    public void mark_clean() {
        saved_index = command_list.size;
        dirty_changed(false);
    }
    
    public void start_transaction(string description) {
        TransactionCommand command = new TransactionCommand(false, description);
        command_list.add(command);
        undo_changed(true);
    }
    
    public void end_transaction(string description) {
        TransactionCommand command = new TransactionCommand(true, description);
        command_list.add(command);
        undo_changed(true);
    }
    
    public void do_command(Command the_command) {
        the_command.apply();
        Command? current_command = get_current_command();
        if (current_command == null || !current_command.merge(the_command)) {
            command_list.add(the_command);
        }
        dirty_changed(true);
        undo_changed(can_undo);
    }

    Command? get_current_command() {
        int index = command_list.size - 1;
        if (index >= 0) {
            return command_list[index];
        } else {
            return null;
        }
    }

    public void undo() {
        int in_transaction = 0;
        do {
            Command? the_command = get_current_command();
            if (the_command != null) {
                command_list.remove(the_command);
                TransactionCommand transaction_command = the_command as TransactionCommand;
                if (transaction_command != null) {
                    if (transaction_command.in_transaction()) {
                        in_transaction++;
                    } else {
                        in_transaction--;
                    }
                } else {
                    the_command.undo();
                }
            } else {
                break;
            }
        } while (in_transaction > 0);
        dirty_changed(is_dirty);
        undo_changed(can_undo);
    }
    
    public string get_undo_title() {
        Command? the_command = get_current_command();
        if (the_command != null) {
            return the_command.description();
        } else {
            return "";
        }
    }
    
}
}
