/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace DialogUtils {
    public struct filter_description_struct {
        public string name;
        public string extension;
    }

    Gtk.FileFilter add_filter(Gtk.FileChooserDialog d, string name, string? extension) {
        Gtk.FileFilter filter = new Gtk.FileFilter();
        filter.set_name(name);
        if (extension != null) {
            filter.add_pattern("*." + extension);
        } else {
            filter.add_pattern("*");
        }
        d.add_filter(filter);
        return filter;
    }

    void add_filters(filter_description_struct[] filter_descriptions, Gtk.FileChooserDialog d,
        Gee.ArrayList<Gtk.FileFilter> filters, bool allow_all) {

        int length = filter_descriptions.length;
        for (int i=0;i<length;++i) {
            Gtk.FileFilter filter = add_filter(d, filter_descriptions[i].name,
                                                filter_descriptions[i].extension);
            filters.add(filter);
        }
        
        if (allow_all) {
            add_filter(d, "All files", null);
            //don't add to filters.  filters should have same number of items as filter_descriptions
        }
        
        assert(filter_descriptions.length == filters.size);
        
        d.set_filter(filters[0]);
    }

    public bool open(Gtk.Window parent, filter_description_struct[] filter_descriptions,
        bool allow_multiple, bool allow_all, out GLib.SList<string> filenames) {
        bool return_value = false;

        Gtk.FileChooserDialog d = new Gtk.FileChooserDialog("Open Files", parent, 
                                                            Gtk.FileChooserAction.OPEN,
                                                            Gtk.STOCK_CANCEL, 
                                                            Gtk.ResponseType.CANCEL,
                                                            Gtk.STOCK_OPEN, 
                                                            Gtk.ResponseType.ACCEPT, null);
        d.set_current_folder(GLib.Environment.get_home_dir());
        Gee.ArrayList<Gtk.FileFilter> filters = new Gee.ArrayList<Gtk.FileFilter>();    
        add_filters(filter_descriptions, d, filters, allow_all);
        d.set_select_multiple(allow_multiple);
        if (d.run() == Gtk.ResponseType.ACCEPT) {
            return_value = true;
            filenames = d.get_filenames();
        }                                                    
        d.destroy();
        return return_value;
    }

    public bool save(Gtk.Window parent, string title, bool create_directory,
            filter_description_struct[] filter_descriptions, ref string filename) {
        bool return_value = false;
        Gtk.FileChooserDialog d = new Gtk.FileChooserDialog(title, parent, 
            Gtk.FileChooserAction.SAVE, Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_SAVE, Gtk.ResponseType.ACCEPT, null);
        if (filename != null) {
            d.set_current_folder(Path.get_dirname(filename));
        } else {
            d.set_current_folder(GLib.Environment.get_home_dir());
        }
        int length = filter_descriptions.length;
        Gee.ArrayList<Gtk.FileFilter> filters = new Gee.ArrayList<Gtk.FileFilter>();    

        add_filters(filter_descriptions, d, filters, false);
        
        //all this extra code is because the dialog doesn't append the extension for us
        //in the filename, so we can't use d.set_do_overwrite_confirmation
        
        while (d.run() == Gtk.ResponseType.ACCEPT) {
            string local_filename = d.get_filename();
            if (create_directory) {
                GLib.DirUtils.create(local_filename, 0777);
                local_filename = Path.build_filename(local_filename, 
                    Path.get_basename(local_filename));
            }
            
            unowned Gtk.FileFilter selected_filter = d.get_filter();

            int i = 0;
            foreach (Gtk.FileFilter file_filter in filters) {
                if (file_filter == selected_filter) {
                    break;
                }
                ++i;
            }
            
            assert(i < length);

            local_filename = append_extension(local_filename, filter_descriptions[i].extension);
            if (!FileUtils.test(local_filename, FileTest.EXISTS) || 
                confirm_replace(parent, local_filename)) {
                return_value = true;
                filename = local_filename;
                break;
            }
            else {
                d.present();
            }
        }
        d.destroy();
        return return_value;
    }

    string bold_message(string message) {
        return "<span weight=\"bold\" size=\"larger\">" + message +
            "</span>";    
    }

    public void error(string major_message, string? minor_message) {
        string message = bold_message(major_message);
        if (minor_message != null) {
            message = message + "\n\n" + minor_message;
        }
        
        Gtk.MessageDialog d = new Gtk.MessageDialog.with_markup(null, Gtk.DialogFlags.MODAL, 
                                Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, message, null);
        d.run();
        d.destroy();
    }

    Gtk.ResponseType run_dialog(Gtk.Window? parent, Gtk.MessageType type, 
        string? title, string message, ButtonStruct[] buttons) {
        string the_message = bold_message(message);
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup(parent, Gtk.DialogFlags.MODAL,
                                        type, Gtk.ButtonsType.NONE, the_message, null);
        if (title != null) {
            dialog.set_title(title);
        }
        
        int length = buttons.length;
        for (int i = 0; i < length; ++i) {
            dialog.add_button(buttons[i].title, buttons[i].type);
        }
        
        Gtk.ResponseType response = (Gtk.ResponseType) dialog.run();
        dialog.destroy();
        
        return response;
    }
    
    public Gtk.ResponseType delete_cancel(string message) {
        Gtk.MessageDialog d = new Gtk.MessageDialog(null, Gtk.DialogFlags.MODAL, 
                                        Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, message,
                                        null);                                                
        
        d.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.NO,
                      Gtk.STOCK_DELETE, Gtk.ResponseType.YES);
        
        Gtk.ResponseType r = (Gtk.ResponseType) d.run();
        d.destroy();
        
        return r;
    }

    public bool confirm_replace(Gtk.Window? parent, string filename) {
        Gtk.MessageDialog md = new Gtk.MessageDialog.with_markup(
            parent, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE,
            "<big><b>A file named \"%s\" already exists.  Do you want to replace it?</b></big>",
            Path.get_basename(filename));
        md.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                       "Replace", Gtk.ResponseType.ACCEPT);
        int response = md.run();
        md.destroy();
        return response == Gtk.ResponseType.ACCEPT;
    }
    
    struct ButtonStruct {
        public ButtonStruct(string title, Gtk.ResponseType type) {
            this.title = title;
            this.type = type;
        }
        
        public string title;
        public Gtk.ResponseType type;
    }
    
    public Gtk.ResponseType save_close_cancel(Gtk.Window? parent, string? title, string message) {
        ButtonStruct[] buttons = {
            ButtonStruct("Close _without saving", Gtk.ResponseType.CLOSE),
            ButtonStruct(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL),
            ButtonStruct(Gtk.STOCK_SAVE, Gtk.ResponseType.ACCEPT)
        };
        
        return run_dialog(parent, Gtk.MessageType.WARNING, title, message, buttons);
    }
    
    public void show_clip_properties(Gtk.Window parent, ClipView selected_clip, 
            Fraction? frames_per_second) {
        Gtk.Dialog d = new Gtk.Dialog.with_buttons("Clip Properties", parent, 
                                    Gtk.DialogFlags.MODAL, Gtk.STOCK_OK, Gtk.ResponseType.ACCEPT);
        d.set("has-separator", false);
        
        Gtk.Table t = new Gtk.Table(10, 2, false);
        int row = 0;
        int tab_padding = 25;
        
        for (int i = 0; i < 10; i++)
            t.set_row_spacing(i, 10);
            
        row = 1;
        add_label_to_table(t, "<b>Clip</b>", 0, row++, 5, 0);
        
        add_label_to_table(t, "<i>Name:</i>", 0, row, tab_padding, 0);
        add_label_to_table(t, "%s".printf(selected_clip.clip.name), 1, row++, 5, 0);
    
        add_label_to_table(t, "<i>Location:</i>", 0, row, tab_padding, 0);
        add_label_to_table(t, "%s".printf(selected_clip.clip.clipfile.filename), 1, row++, 5, 0); 
    
        add_label_to_table(t, "<i>Timeline length:</i>", 0, row, tab_padding, 0);
    
        string length_string = "";
        string actual_length = "";
        
        if (frames_per_second != null) {
            TimeCode time = frame_to_time (time_to_frame_with_rate(selected_clip.clip.duration, 
                frames_per_second), frames_per_second);
            length_string = time.to_string();
            time = frame_to_time(time_to_frame_with_rate(
                selected_clip.clip.clipfile.length, frames_per_second), frames_per_second);
            actual_length = time.to_string();
        } else {
            length_string = time_to_string(selected_clip.clip.duration);
            actual_length = time_to_string(selected_clip.clip.clipfile.length);
        }
        
        add_label_to_table(t, "%s".printf(length_string), 1, row++, 5, 0);
    
        if (selected_clip.clip.is_trimmed()) {
            add_label_to_table(t, "<i>Actual length:</i>", 0, row, tab_padding, 0);
            add_label_to_table(t, "%s".printf(actual_length), 1, row++, 5, 0);
        }

        if (selected_clip.clip.clipfile.has_caps_structure(Model.MediaType.VIDEO)) {   
            add_label_to_table(t, "<b>Video</b>", 0, row++, 5, 0);

            int w, h;
            if (selected_clip.clip.clipfile.get_dimensions(out w, out h)) {
                add_label_to_table(t, "<i>Dimensions:</i>", 0, row, tab_padding, 0);
                add_label_to_table(t, "%d x %d".printf(w, h), 1, row++, 5, 0);
            }

            Fraction r;
            if (selected_clip.clip.clipfile.get_frame_rate(out r)) {
                add_label_to_table(t, "<i>Frame rate:</i>", 0, row, tab_padding, 0);
                
                if (r.numerator % r.denominator != 0)
                    add_label_to_table(t, 
                               "%.2f frames per second".printf(r.numerator / (float)r.denominator), 
                               1, row++, 5, 0);
                else
                    add_label_to_table(t, 
                                "%d frames per second".printf(r.numerator / r.denominator), 
                                1, row++, 5, 0);
            }
        }

        if (selected_clip.clip.clipfile.has_caps_structure(Model.MediaType.AUDIO)) {
            add_label_to_table(t, "<b>Audio</b>", 0, row++, 5, 0);
           
            int rate;
            if (selected_clip.clip.clipfile.get_sample_rate(out rate)) {
                add_label_to_table(t, "<i>Sample Rate:</i>", 0, row, tab_padding, 0);
                add_label_to_table(t, "%d Hz".printf(rate), 1, row++, 5, 0);
            }

            string s;
            if (selected_clip.clip.clipfile.get_num_channels_string(out s)) {
                add_label_to_table(t, "<i>Number of channels:</i>", 0, row, tab_padding, 0);
                add_label_to_table(t, "%s".printf(s), 1, row++, 5, 0);
            }
        } 
    
        d.vbox.pack_start(t, false, false, 0);
    
        d.show_all();
        d.run();
        d.destroy();
    }
    
}
