/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {

public class LoaderHandler {
    delegate bool CommitDelegate(string[]? attr_names, string[]? attr_values);
    delegate void LeaveDelegate();
    
    public signal void load_error(string error_message);
    
    ProjectLoader.States execute_state(CommitDelegate commit_delegate, LeaveDelegate leave_delegate,
                    ProjectLoader.States enter_state, ProjectLoader.States leave_state,
                    bool entering, string[]? attr_names, string[]? attr_values) {
        if (entering) {
            if (commit_delegate(attr_names, attr_values)) {
                return enter_state;
            } else {
                return ProjectLoader.States.INV;
            }
        } else {
            leave_delegate();
            return leave_state;
        }
    }

    public ProjectLoader.States project(bool entering, 
                                    string[]? attr_names, string[]? attr_values) {
        return execute_state(commit_project, leave_project, 
            ProjectLoader.States.PROJ, ProjectLoader.States.NULL,
            entering, attr_names, attr_values);
    }
    
    public virtual void leave_project() {
    }

    public virtual bool commit_project(string[]? attr_names, string[]? attr_values) {
        return true;
    }
    
    public ProjectLoader.States track(bool entering, 
                                    string[]? attr_names, string[]? attr_values) {
        return execute_state(commit_track, leave_track,
            ProjectLoader.States.TRACK, ProjectLoader.States.PROJ,
            entering, attr_names, attr_values);
    }

    public virtual void leave_track() {
    }

    public virtual bool commit_track(string[]? attr_names, string[]? attr_values) {
        return true;
    }
    
    public virtual ProjectLoader.States orphan_track(bool entering, 
                                    string[]? attr_names, string[]? attr_values) {
        return execute_state(commit_orphan_track, leave_orphan_track,
            ProjectLoader.States.ORPHAN_T, ProjectLoader.States.PROJ,
            entering, attr_names, attr_values);
    }
    
    public virtual void leave_orphan_track() {
    }
    
    public virtual bool commit_orphan_track(string[]? attr_names, string[]? attr_values) {
        return true;
    }

    public virtual ProjectLoader.States clip(bool entering, 
                                    string[]? attr_names, string[]? attr_values) {
        return execute_state(commit_clip, leave_clip,
            ProjectLoader.States.CLIP, ProjectLoader.States.TRACK,
            entering, attr_names, attr_values);
    }
    
    public virtual void leave_clip() {
    }
    
    public virtual bool commit_clip(string[]? attr_names, string[]? attr_values) {
        return true;
    }
    
    public virtual ProjectLoader.States orphan_clip(bool entering, 
                                    string[]? attr_names, string[]? attr_values) {
        return execute_state(commit_orphan_clip, leave_orphan_clip,
            ProjectLoader.States.ORPHAN_C, ProjectLoader.States.ORPHAN_T,
            entering, attr_names, attr_values);
    }
    
    public virtual void leave_orphan_clip() {
    }
    
    public virtual bool commit_orphan_clip(string[]? attr_names, string[]? attr_values) {
        return true;
    }
    
    public virtual ProjectLoader.States nullstate(bool entering, 
        string[]? attr_names, string[]? attr_values) {
        if (entering) {
            return ProjectLoader.States.INV;
        } else {
            return ProjectLoader.States.NULL;
        }
    }

    protected virtual bool can_handle_track(string[] attrs, string[] values) {
        for (int i = 0;i < attrs.length; ++i) {
            if (attrs[i] == "type") {
                return values[i] == "audio";
            }
        }
        return false;
    }
}

public class ProjectLoader {
    public enum States {
        NULL, PROJ /* == PROJECT */, TRACK, ORPHAN_T /* == ORPHAN_TRACK */, CLIP, 
        ORPHAN_C /* == ORPHAN_CLIP */, INV /* == INVALID*/
    }
    
    public enum Actions {
        PROJ /* == PROJECT*/, TRACK, ORPHAN_T /* == ORPHAN_TRACK*/, CLIP, INV /* == INVALID */
    }

    public States loading_state = States.NULL;
    
    string? file_name;
    string text;
    ulong text_len;
        
    bool loaded_file_header;
    string error;
    LoaderHandler loader_handler;

    Gee.HashSet<ClipFetcher> pending = new Gee.HashSet<ClipFetcher>();

    public signal void clip_ready(ClipFile clip_file);
    public signal void load_started(string filename);
    public signal void load_complete(string? error);
    
    public ProjectLoader(LoaderHandler loader_handler, string? file_name) {
        this.loader_handler = loader_handler;
        this.file_name = file_name;
        loader_handler.load_error += on_load_error;
    }
    
    void on_load_error(string error) {
        load_complete(error);
    }
    
    void parse(MarkupParser parser) {
        MarkupParseContext context =
            new MarkupParseContext(parser, (MarkupParseFlags) 0, this, null);
            
        try {
            context.parse(text, (long) text_len);
        } catch (MarkupError e) {
            error = e.message;
        }
    }
    
    Actions get_action(string name, string[]? attr_names, string[]? attr_values) {
        switch(name) {
            case "marina":
                return Actions.PROJ;
            case "track":
                if (attr_names != null && attr_values != null && 
                    !loader_handler.can_handle_track(attr_names, attr_values)) {
                    return Actions.ORPHAN_T;
                } else {
                    return Actions.TRACK;
                }
            case "clip":
                return Actions.CLIP;
        }
        return Actions.INV;
    }

    public void state_transition(bool entering, Actions action, 
                                string[]? attr_names, string[]? attr_values) {
// States go across the screen
// Actions go down the screen
// When an action is applied, determine the state function to call

        States[6, 5] enter_state_transitions = {
             /*NULL         PROJ             TRACK        ORPHAN_T         CLIP        ORPHAN_C */
/*PROJ*/     { States.PROJ, States.INV,      States.INV,  States.INV,      States.INV, States.INV },
/*TRACK*/    { States.INV,  States.TRACK,    States.INV,  States.INV,      States.INV, States.INV },
/*ORPHAN_T*/ { States.INV,  States.ORPHAN_T, States.INV,  States.INV,      States.INV, States.INV },
/*CLIP*/     { States.INV,  States.INV,      States.CLIP, States.ORPHAN_C, States.INV, States.INV },
/*INV*/      { States.INV,  States.INV,      States.INV,  States.INV,      States.INV, States.INV }
        };
        
        States[6, 5] exit_state_transitions = {
             /*NULL        PROJ         TRACK         ORPHAN_T         CLIP         ORPHAN_C*/
/*PROJ*/     { States.INV, States.PROJ, States.INV,   States.INV,      States.INV,  States.INV },
/*TRACK*/    { States.INV, States.INV,  States.TRACK, States.ORPHAN_T, States.INV,  States.INV },
/*ORPHAN_T*/ { States.INV, States.INV,  States.INV,   States.INV,      States.INV,  States.INV },
/*CLIP*/     { States.INV, States.INV,  States.INV,   States.INV,      States.CLIP, States.ORPHAN_C},
/*INV*/      { States.INV, States.INV,  States.INV,   States.INV,      States.INV,  States.INV  }
        };
        States[6, 5] transitions = entering ? enter_state_transitions : exit_state_transitions;
        
        States transition_state = transitions[action, loading_state];
        
        switch(transition_state) {
        case States.CLIP:
            loading_state = loader_handler.clip(entering, attr_names, attr_values);
            break;
        case States.INV:
            loading_state = States.INV;
            break;
        case States.NULL:
            loading_state = loader_handler.nullstate(entering, attr_names, attr_values);
            break;
        case States.ORPHAN_C:
            loading_state = loader_handler.orphan_clip(entering, attr_names, attr_values);
            break;
        case States.ORPHAN_T:
            loading_state = loader_handler.orphan_track(entering, attr_names, attr_values);
            break;
        case States.PROJ:
            loading_state = loader_handler.project(entering, attr_names, attr_values);
            break;
        case States.TRACK:
            loading_state = loader_handler.track(entering, attr_names, attr_values);
            break;
        default:
            assert(false);
            break;
        }
    }

    void do_xml_element(bool entering, string name, string[]? attr_names, string[]? attr_values)
        throws MarkupError {

        Actions action = get_action(name, attr_names, attr_values);
        state_transition(entering, action, attr_names, attr_values);
        
        if (loading_state == States.INV) {
            throw new MarkupError.INVALID_CONTENT("error on %s".printf(name));        
        }
    }
    
    void xml_start_element(GLib.MarkupParseContext c, string name, 
                           string[] attr_names, string[] attr_values) throws MarkupError {
        do_xml_element(true, name, attr_names, attr_values);
    }
    
    void xml_end_element(GLib.MarkupParseContext c, string name) throws MarkupError {
        do_xml_element(false, name, null, null);
    }
    
    void fetcher_callback(ClipFetcher f) {
        if (f.error_string != null && error == null)
            error = "%s: %s".printf(f.clipfile.filename, f.error_string);
        else clip_ready(f.clipfile);
        pending.remove(f);
        
        if (pending.size == 0) {
            if (error == null) {
                // Now that all ClipFetchers have completed, parse the XML again and
                // create Clip objects.
                MarkupParser parser = { xml_start_element, xml_end_element, null, null };
                parse(parser);
            }
            load_complete(error);
        }
    }
    
    void xml_start_clipfile(GLib.MarkupParseContext c, string name, 
                            string[] attr_names, string[] attr_values) throws MarkupError {
        
        if (!loaded_file_header) {
            if (name != "marina")
                throw new MarkupError.INVALID_CONTENT("Missing header!");
                
            if (attr_names.length < 1 ||
                attr_names[0] != "version") {
                throw new MarkupError.INVALID_CONTENT("Corrupted header!");
            }
         
            loaded_file_header = true;
        } else if (name == "clip")
            for (int i = 0; i < attr_names.length; i++)
                if (attr_names[i] == "filename") {
                    string filename = attr_values[i];
                    foreach (ClipFetcher fetcher in pending)
                        if (fetcher.get_filename() == filename)
                            return;     // we're already fetching this clipfile

                    ClipFetcher fetcher = new ClipFetcher(filename);
                    pending.add(fetcher);
                    fetcher.ready += fetcher_callback;
                    return;
                }
    }
    
    public void load() {
        try {
            FileUtils.get_contents(file_name, out text, out text_len);
        } catch (FileError e) {
            load_complete(e.message);
            return;
        }
        load_started(file_name);

        // Parse the XML and start a ClipFetcher for each clip referenced.
        MarkupParser parser = { xml_start_clipfile, null, null, null };
        parse(parser);

        // TODO: this is for the degenerate case where there are no clips to be fetched
        // should be handled more gracefully
        if (error == null && pending.size == 0) {
            MarkupParser parser2 = { xml_start_element, xml_end_element, null, null };
            parse(parser2);
        }

        if (error != null || pending.size == 0)
            load_complete(error);
    }
}
}
