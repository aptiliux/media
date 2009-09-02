/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {

public class LoaderHandler {
    public signal void load_error(string error_message);

    public LoaderHandler() {
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

    public virtual void leave_marina() {
    }    

    public virtual void leave_track() {
    }
    
    public virtual void leave_clip() {
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
class ProjectBuilder {
    LoaderHandler handler;

    public signal void error_occurred(string? error);
    
    public ProjectBuilder(LoaderHandler handler) {
        this.handler = handler;
    }

    bool check_name(string expected_name, XmlElement node) {
        if (node.name == expected_name) {
            return true;
        }
        
        error_occurred("expected %s, got %s".printf(node.name, node.name));
        return false;
    }
    
    void handle_clip(XmlElement clip) {
        if (check_name("clip", clip)) {
            if (handler.commit_clip(clip.attribute_names, clip.attribute_values)) {
                if (clip.children.size != 0) {
                    error_occurred("clip cannot have children");
                }
                handler.leave_clip();
            } else {
                error_occurred("improper clip node");
            }
        }
    }

    void handle_track(XmlElement track) {
        if (check_name("track", track)) {
            if (handler.commit_track(track.attribute_names, track.attribute_values)) {
                foreach (XmlElement child in track.children) {
                    handle_clip(child);
                }
                handler.leave_track();
            } else {
                error_occurred("improper track node");
            }
        }
    }

    public void build_project(XmlElement root) {
        if (check_name("marina", root)) {
            if (handler.commit_marina(root.attribute_names, root.attribute_values)) {
                foreach (XmlElement child in root.children) {
                    handle_track(child);
                }
                handler.leave_marina();
            } else {
                error_occurred("improper marina node");
            }
        }
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

public class ProjectLoader {
    string? file_name;
    LoaderHandler loader_handler;
    string text;
    ulong text_len;

    bool loaded_file_header;
    string error;

    Gee.HashSet<ClipFetcher> pending = new Gee.HashSet<ClipFetcher>();

    public signal void clip_ready(ClipFile clip_file);
    public signal void load_started(string filename);
    public signal void load_complete(string? error);
    
    public ProjectLoader(LoaderHandler loader_handler, string? file_name) {
        this.file_name = file_name;
        this.loader_handler = loader_handler;
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

    void fetcher_callback(ClipFetcher f) {
        if (f.error_string != null && error == null)
            error = "%s: %s".printf(f.clipfile.filename, f.error_string);
        else clip_ready(f.clipfile);
        pending.remove(f);
        
        if (pending.size == 0) {
            load_ready();
        }
    }

    void load_ready() {
        if (error == null) {
            // Now that all ClipFetchers have completed, parse the XML again and
            // create Clip objects.
            XmlTreeLoader tree_loader = new XmlTreeLoader(text);
            
            ProjectBuilder builder = new ProjectBuilder(loader_handler);
            builder.build_project(tree_loader.root);
        }
        
        load_complete(error);
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
            load_ready();
        }

        if (error != null || pending.size == 0)
            load_complete(error);
    }
}
}
