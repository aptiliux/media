/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

extern const string _PREFIX;


public class AppDirs {
    static File exec_dir;
    static string program_name;

    public static void init(string arg0, string program_name) {
        File exec_file = File.new_for_path(Environment.find_program_in_path(arg0));
        exec_dir = exec_file.get_parent();
        AppDirs.program_name = program_name;
    }

    public static void terminate() {
    }

    public static File get_exec_dir() {
        return exec_dir;
    }

    public static File get_resources_dir() {
        File exec_dir = get_exec_dir();
        File install_dir = get_install_dir();
        File return_value;
        if (install_dir != null) {
            return_value = install_dir.get_child("share").get_child(program_name);
        } else {    // running locally
            return_value = exec_dir;
        }
        return return_value.get_child("resources");
    }

    static File? get_install_dir() {
        File prefix_dir = File.new_for_path(_PREFIX);
        return exec_dir.has_prefix(prefix_dir) ? prefix_dir : null;
    }
}

