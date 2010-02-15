/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class ProjectProperties : Gtk.Dialog {
    const int NUMBER_OF_SAMPLES = 4;
    const long G_USEC_PER_SEC = 1000000;

    TimeVal[] tap_time = new TimeVal[NUMBER_OF_SAMPLES];
    int tap_index = 0;
    bool sample_full = false;
    Gtk.Adjustment tempo_adjustment;
    Gtk.Adjustment volume_adjustment;
    Gtk.ComboBox timesignature_combo;
    Gtk.ToggleButton click_during_play;
    Gtk.ToggleButton click_during_record;

    public void setup(Model.Project project, Gtk.Builder builder) {
        tempo_adjustment = (Gtk.Adjustment) builder.get_object("tempo_adjustment");
        volume_adjustment = (Gtk.Adjustment) builder.get_object("volume_adjustment");
        timesignature_combo = (Gtk.ComboBox) builder.get_object("timesignature_combo");
        click_during_play = (Gtk.ToggleButton) builder.get_object("playback");
        click_during_record = (Gtk.ToggleButton) builder.get_object("record");
        set_tempo(project.get_bpm());
        set_volume(project.click_volume);
        set_during_play(project.click_during_play);
        set_during_record(project.click_during_record);
        set_time_signature(project.get_time_signature());
    }

    public void set_tempo(int tempo) {
        tempo_adjustment.set_value(tempo);
    }

    public int get_tempo() {
        return (int) tempo_adjustment.get_value();
    }

    public void set_volume(double volume) {
        volume_adjustment.set_value(volume);
    }

    public double get_click_volume() {
        return volume_adjustment.get_value();
    }

    public Fraction get_time_signature() {
        return Fraction.from_string(timesignature_combo.get_active_text());
    }

    void set_time_signature(Fraction time_signature) {
        string sig = time_signature.to_string();

        Gtk.TreeIter iter;
        if (timesignature_combo.model.get_iter_first(out iter)) {
            do {
                string s;
                timesignature_combo.model.get(iter, 0, out s, -1);
                if (s == sig) {
                    timesignature_combo.set_active_iter(iter);
                    return;
                }
            } while (timesignature_combo.model.iter_next(ref iter));
        }
    }

    void set_during_play(bool active) {
        click_during_play.active = active;
    }

    public bool during_play() {
        return click_during_play.active;
    }

    void set_during_record(bool active) {
        click_during_record.active = active;
    }

    public bool during_record() {
        return click_during_record.active;
    }

    public void on_tap() {
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
        tempo_adjustment.set_value((int)(60.0/average));
    }
}
