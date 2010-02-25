/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace UI {
    class TrackInformation : Gtk.Dialog {
 
        Gtk.Entry entry;
            
        construct {
            set_title("New Track");
            set_modal(true);
            add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                        Gtk.STOCK_OK, Gtk.ResponseType.OK,
                        null);
            Gtk.Label label = new Gtk.Label("Track Name:");
            entry = new Gtk.Entry();
            entry.set_activates_default(true);
    
            Gtk.Table table = new Gtk.Table(1, 2, false);
            table.attach_defaults(label, 0, 1, 0, 1);
            table.attach_defaults(entry, 1, 2, 0, 1);
            table.set_col_spacing(0, 12);
            table.set_border_width(12);

            vbox.pack_start(table, true, true, 0);
            show_all();
            set_default_response(Gtk.ResponseType.OK);
        }

        public void set_track_name(string new_name) {
            entry.set_text(new_name);
            entry.select_region(0, -1);
        }
                    
        public string get_track_name() {
            return entry.get_text().strip();
        }
    }
}
