/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class ProjectProperties : Gtk.Dialog {
    const int NUMBER_OF_SAMPLES = 4;
    const long G_USEC_PER_SEC = 1000000;
    Fraction[] times = {
        Fraction(2,4), Fraction(3,4), Fraction(4,4), Fraction(6,8)
    };
    
    TimeVal[] tap_time = new TimeVal[NUMBER_OF_SAMPLES];
    Gtk.ComboBox time_signature;
    Gtk.HScale tempo;
    int tap_index = 0;
    bool sample_full = false;
    
    public ProjectProperties(int bpm, Fraction signature_fraction) {
        set_modal(true);
        set_title("Project Properties");
        set_size_request(300, 140);
        resizable = false;

        add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_APPLY, Gtk.ResponseType.APPLY,
            null);
        set_default_response(Gtk.ResponseType.APPLY);

        Gtk.SizeGroup size_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);

        time_signature = new Gtk.ComboBox.text();
        foreach (Fraction time in times) {
            time_signature.append_text(time.to_string());        
        }
        time_signature.set_active(fraction_to_index(signature_fraction));

        add_row(size_group, "Time _Signature", time_signature);

        tempo = new Gtk.HScale.with_range(30, 240, 1);
        tempo.set_value(bpm);
        Gtk.HBox row = add_row(size_group, "Tem_po", tempo);

        Gtk.Button button = new Gtk.Button.with_mnemonic("_Tap");
        button.clicked += on_tap;
        row.pack_start(button, false, false, 0);

        vbox.show_all();    
    }
    
    public int get_tempo() {
        return (int) tempo.get_value();
    }
    
    public Fraction get_time_signature() {
        return index_to_fraction(time_signature.get_active());
    }
    
    Fraction index_to_fraction(int index) {
        return times[index];
    }

    int fraction_to_index(Fraction signature_fraction) {
        for (int i = 0; i < times.length; ++i) {
            if (times[i].denominator == signature_fraction.denominator &&
                times[i].numerator == signature_fraction.numerator) {
                    return i;
                }
        }
        
        return 0;        
    }
    
    void on_tap() {
        TimeVal time_val = TimeVal();
        time_val.get_current_time();
        tap_time[tap_index] = time_val;
        ++tap_index;
        if (tap_index == NUMBER_OF_SAMPLES) {
            sample_full = true;
            tap_index = 0;
        }
        calculate_bpm();
    }
    
    void calculate_bpm() {
        int number_of_samples = sample_full ? NUMBER_OF_SAMPLES : tap_index;
        if (number_of_samples < 2) {
            return;
        }
        
        int start_index = sample_full ? tap_index : 0;

        double delta_sum = 0;
        for (int i = 0; i < number_of_samples - 1; ++i) {
            int current_index = (i + start_index) % NUMBER_OF_SAMPLES;
            int next_index = (current_index + 1) % NUMBER_OF_SAMPLES;
            long difference = 
                (tap_time[next_index].tv_sec - tap_time[current_index].tv_sec) * G_USEC_PER_SEC +
                tap_time[next_index].tv_usec - tap_time[current_index].tv_usec;
                
            if (difference > 5 * G_USEC_PER_SEC) {
                // User waited too long.  Save the time and start over
                tap_time[0] = tap_time[tap_index - 1];
                sample_full = false;
                tap_index = 1;
                return;
            }
            delta_sum += difference;
        }
        double average = delta_sum/(number_of_samples - 1)/G_USEC_PER_SEC;
        tempo.set_value((int)(60.0/average));
    }

    Gtk.HBox add_row(Gtk.SizeGroup size_group, string label, Gtk.Widget element) {
        Gtk.HBox row = new Gtk.HBox(false, 0);
        Gtk.Label element_label = new Gtk.Label.with_mnemonic(label);

        Gtk.Alignment align = new Gtk.Alignment(1.0f, 0.5f, 0.0f, 0.0f);
        align.add(element_label);
        size_group.add_widget(align);

        row.pack_start(align, false, false, 12);
        row.pack_start(element, true, true, 0);
        element_label.set_mnemonic_widget(element);
        vbox.pack_start(row, false, false, 6);
        return row;
    }
}
