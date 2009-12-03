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
    Gtk.CheckButton click_during_play;
    Gtk.CheckButton click_during_record;
    VolumeSlider click_volume;
    
    int tap_index = 0;
    bool sample_full = false;
    
    public ProjectProperties(Model.Project project) {
        set_modal(true);
        set_title("Project Properties");
        resizable = false;

        add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_APPLY, Gtk.ResponseType.APPLY,
            null);
        set_default_response(Gtk.ResponseType.APPLY);

        time_signature = new Gtk.ComboBox.text();
        foreach (Fraction time in times) {
            time_signature.append_text(time.to_string());        
        }
        time_signature.set_active(fraction_to_index(project.time_signature));

        add_row("Time _Signature", time_signature);

        tempo = new Gtk.HScale.with_range(30, 240, 1);
        tempo.set_size_request(100, -1);
        tempo.set_value(project.tempo);
        Gtk.HBox row = add_row("Temp_o", tempo);

        Gtk.Button button = new Gtk.Button.with_mnemonic("_Tap");
        button.clicked += on_tap;
        row.pack_start(button, false, false, 0);
        
        Gtk.HBox hbox = new Gtk.HBox(false, 0);

        click_volume = new VolumeSlider();
        click_volume.set_adjustment(
            new Gtk.Adjustment(project.click_volume, 0.0, 1.0, 0.01, 0.1, 0.1));
        click_volume.set_size_request(100, 20);

        add_row("_Metronome", click_volume);
        
        hbox = new Gtk.HBox(false, 0);
        click_during_play = new Gtk.CheckButton.with_mnemonic("During _playback");
        click_during_play.set_active(project.click_during_play);
        hbox.pack_start(click_during_play, false, false, 18);
        vbox.pack_start(hbox, false, false, 3);

        hbox = new Gtk.HBox(false, 0);
        click_during_record = new Gtk.CheckButton.with_mnemonic("During _record");
        click_during_record.set_active(project.click_during_record);
        hbox.pack_start(click_during_record, false, false, 18);
        vbox.pack_start(hbox, false, false, 3);
        vbox.show_all();
    }
    
    public int get_tempo() {
        return (int) tempo.get_value();
    }
    
    public Fraction get_time_signature() {
        return index_to_fraction(time_signature.get_active());
    }
    
    public bool during_play() {
        return click_during_play.get_active();
    }
    
    public bool during_record() {
        return click_during_record.get_active();
    }
    
    public double get_click_volume() {
        return click_volume.get_value();
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

    Gtk.HBox add_row(string label, Gtk.Widget element) {
        string markup = "<span weight=\"bold\">" + label + "</span>";
        Gtk.HBox row = new Gtk.HBox(false, 0);
        Gtk.Label element_label = new Gtk.Label(null);
        element_label.set_markup_with_mnemonic(markup);
        row.pack_start(element_label, false, false, 12);
        vbox.pack_start(row, false, false, 6);
        row = new Gtk.HBox(false, 0);
        row.pack_start(element, true, true, 18);
        element_label.set_mnemonic_widget(element);
        vbox.pack_start(row, false, false, 3);
        return row;
    }
}
