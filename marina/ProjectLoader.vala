/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

namespace Model {

public class LoaderHandler : Object {
    public signal void load_error(string error_message);
    public signal void complete();
    
    public LoaderHandler() {
    }
    
    public virtual bool commit_library(string[] attr_names, string[] attr_values) {
        return true;
    }
    
    public virtual bool commit_marina(string[] attr_names, string[] attr_values) {
        return true;
    }
    
    public virtual bool commit_track(string[] attr_names, string[] attr_values) {
        return true;
    }
    
    public virtual bool commit_clip(string[] attr_names, string[] attr_values) {
        return true;
    }
    
    public virtual bool commit_clipfile(string[] attr_names, string[] attr_values) {
        return true;
    }

    public virtual void leave_library() {
    }

    public virtual void leave_marina() {
    }    

    public virtual void leave_track() {
    }
    
    public virtual void leave_clip() {
    }
    
    public virtual void leave_clipfile() {
        
    }
}

// TODO: Move these classes into separate file
public class XmlTreeLoader {
    XmlElement current_element = null;
    public XmlElement root = null;

    public XmlTreeLoader(string document) {
        MarkupParser parser = { xml_start_element, xml_end_element, null, null };
        MarkupParseContext context =
            new MarkupParseContext(parser, (MarkupParseFlags) 0, this, null);
        try {
            context.parse(document, document.length);
        } catch (MarkupError e) {
        }
    
    }    
    
    void xml_start_element(GLib.MarkupParseContext c, string name, 
                           string[] attr_names, string[] attr_values) {
        Model.XmlElement new_element = new Model.XmlElement(name, attr_names, attr_values, current_element);
        if (root == null) {
            root = new_element;
        } else {
            assert(current_element != null);
            current_element.add_child(new_element);
        }
        
        current_element = new_element;
    }

    void xml_end_element(GLib.MarkupParseContext c, string name) {
        assert(current_element != null);
        current_element = current_element.parent;
    }
}

// ProjectBuilder is responsible for verifying the structure of the XML document.
// Subclasses of this class will be responsible for checking the attributes of 
// any particular element.
class ProjectBuilder : Object {
    LoaderHandler handler;

    public signal void error_occurred(string error);
    
    public ProjectBuilder(LoaderHandler handler) {
        this.handler = handler;
    }

    bool check_name(string expected_name, XmlElement node) {
        if (node.name == expected_name) {
            return true;
        }
        
        error_occurred("expected %s, got %s".printf(expected_name, node.name));
        return false;
    }
    
    void handle_clip(XmlElement clip) {
        if (check_name("clip", clip)) {
            if (handler.commit_clip(clip.attribute_names, clip.attribute_values)) {
                if (clip.children.size != 0) {
                    error_occurred("clip cannot have children");
                }
                handler.leave_clip();
            }
        }
    }

    void handle_track(XmlElement track) {
        if (check_name("track", track)) {
            emit(this, Facility.LOADING, Level.VERBOSE, "loading track");
            if (handler.commit_track(track.attribute_names, track.attribute_values)) {
                foreach (XmlElement child in track.children) {
                    handle_clip(child);
                }
                handler.leave_track();
            }
        }
    }

    void handle_library(XmlElement library) {
        if (handler.commit_library(library.attribute_names, library.attribute_values)) {
            foreach (XmlElement child in library.children) {
                if (!handler.commit_clipfile(child.attribute_names, child.attribute_values))
                    error_occurred("Improper library node");
            } 
            handler.leave_library();
        }
    }
    
    void handle_tracks(XmlElement tracks) {
        foreach (XmlElement child in tracks.children) {
            handle_track(child);
        }
    }

    public bool check_project(XmlElement? root) {
        if (root == null) {
            error_occurred("Invalid XML file!");
            return false;
        }
        
        if (check_name("marina", root) &&
            handler.commit_marina(root.attribute_names, root.attribute_values)) {
            if (root.children.size != 2) {
                error_occurred("Improper number of children!");
                return false;
            }
            
            if (!check_name("library", root.children[0]) ||
                !check_name("tracks", root.children[1]))
                return false;
        } else
            return false;
        return true;
    }

    public void build_project(XmlElement? root) {
        handle_library(root.children[0]);
        handle_tracks(root.children[1]);
        
        handler.leave_marina();
    }
}

public class XmlElement {
    public string name { get; private set; }
    
    public string[] attribute_names;
    
    public string[] attribute_values;
    
    public Gee.ArrayList<XmlElement> children { get { return _children; } }
    
    public weak XmlElement? parent { get; private set; }
    
    private Gee.ArrayList<XmlElement> _children;
    public XmlElement(string name, string[] attribute_names, string[] attribute_values, 
                        XmlElement? parent) {
        this.name = name;

        this.attribute_names = copy_array(attribute_names);
        this.attribute_values = copy_array(attribute_values);
        this.parent = parent;
        this._children = new Gee.ArrayList<XmlElement>();
    }
    
    public void add_child(XmlElement child_element) {
        _children.add(child_element);
    }
}

public class ProjectLoader : Object {
    string? file_name;
    LoaderHandler loader_handler;
    string text;
    size_t text_len;

    public signal void load_started(string filename);
    public signal void load_complete();
    public signal void load_error(string error);
    
    public ProjectLoader(LoaderHandler loader_handler, string? file_name) {
        this.file_name = file_name;
        this.loader_handler = loader_handler;
        loader_handler.load_error += on_load_error;
        loader_handler.complete += on_handler_complete;
    }
    
    void on_load_error(string error) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_load_error");
        load_error(error);
    }
    
    void on_handler_complete() {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_handler_complete");
        load_complete();    
    }
    
    public void load() {
        try {
            FileUtils.get_contents(file_name, out text, out text_len);
        } catch (FileError e) {
            emit(this, Facility.LOADING, Level.MEDIUM, 
                "error loading %s: %s".printf(file_name, e.message));
            load_error(e.message);
            load_complete();
            return;
        }
        
        emit(this, Facility.LOADING, Level.VERBOSE, "Building tree for %s".printf(file_name));
        XmlTreeLoader tree_loader = new XmlTreeLoader(text);
        
        ProjectBuilder builder = new ProjectBuilder(loader_handler);
        builder.error_occurred += on_load_error;
        
        if (builder.check_project(tree_loader.root)) {
            emit(this, Facility.LOADING, Level.VERBOSE, "project checked out.  starting load");
            load_started(file_name);
            builder.build_project(tree_loader.root);
        }
        else {
            emit(this, Facility.LOADING, Level.INFO, "project did not check out.  stopping.");
            load_complete(); 
        }
    }
}
}
