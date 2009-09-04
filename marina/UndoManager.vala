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
        saved_index = command_list.size - 1;
        dirty_changed(false);
    }
    
    public void start_transaction() {
        TransactionCommand command = new TransactionCommand(false);
        command_list.add(command);
    }
    
    public void end_transaction() {
        TransactionCommand command = new TransactionCommand(true);
        command_list.add(command);
    }
    
    public void do_command(Command the_command) {
        the_command.apply();
        Command? current_command = get_current_command(true);
        if (current_command == null || !current_command.merge(the_command)) {
            command_list.add(the_command);
        }
        dirty_changed(true);
        undo_changed(can_undo);
    }

    Command? get_current_command(bool allow_transaction) {
        int index = command_list.size - 1;
        if (index >= 0) {
            if (!allow_transaction) {
                Command command = command_list[index];
                if (command is TransactionCommand) {
                    --index;
                    command = command_list[index];
                    assert(index >= 0);//transactions should always be closed and non-empty
                    assert(!(command is TransactionCommand));
                }
            }
            return command_list[index];
        } else {
            return null;
        }
    }

    public void undo() {
        bool in_transaction = false;
        do {
            Command? the_command = get_current_command(true);
            if (the_command != null) {
                command_list.remove(the_command);
                TransactionCommand transaction_command = the_command as TransactionCommand;
                if (transaction_command != null) {
                    in_transaction = transaction_command.in_transaction();
                } else {
                    the_command.undo();
                }
            } else {
                break;
            }
        } while (in_transaction);
        dirty_changed(is_dirty);
        undo_changed(can_undo);
    }
    
    public string get_undo_title() {
        Command? the_command = get_current_command(false);
        if (the_command != null) {
            return the_command.description();
        } else {
            return "";
        }
    }
    
}
}
