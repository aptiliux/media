/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class AppDirs {
    static File exec_dir;
    
    public static void init(string arg0) {
        File exec_file = File.new_for_path(Environment.find_program_in_path(arg0));
        exec_dir = exec_file.get_parent();
    }
    
    public static void terminate() {
    }
    
    public static File get_exec_dir() {
        return exec_dir;
    }
    
    public static File get_resources_dir() {
        return get_exec_dir().get_child("resources");
    }    
}

