/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class GapView : Gtk.DrawingArea {
    public Model.Gap gap;
    Gdk.Color fill_color;
    
    public GapView(int64 start, int64 length, int width, int height) {

        gap = new Model.Gap(start, start + length);         
        
        Gdk.Color.parse("#777", out fill_color);
        
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        
        set_size_request(width, height);
    }  
    
    public signal void removed(GapView gap_view);
    public signal void unselected(GapView gap_view);
    
    public void remove() {
        removed(this);
    }
    
    public void unselect() {
        unselected(this);
    }
    
    public override bool expose_event(Gdk.EventExpose e) {
        draw_rounded_rectangle(window, fill_color, true, allocation.x, allocation.y, 
                                allocation.width - 1, allocation.height - 1);
        return true;
    }
}

public class ClipView : Gtk.DrawingArea {
    public Model.Clip clip;
    weak Model.TimeSystem time_provider;
    public bool ghost;
    public bool is_selected;
    public int height; // TODO: We request size of height, but we aren't allocated this height.
                       // We should be using the allocated height, not the requested height. 

    Gdk.Color color_black;    
    Gdk.Color color_normal;
    Gdk.Color color_selected;
    
    public signal void clip_deleted(Model.Clip clip, bool ripple);
    public signal void clip_moved(ClipView clip);
    public signal void drag_updated(ClipView clip);
    
    public ClipView(Model.Clip clip, Model.TimeSystem time_provider, int height) {
        this.clip = clip;
        this.time_provider = time_provider;
        this.height = height;
        ghost = false;
        is_selected = false;
        
        clip.moved += on_clip_moved;
        clip.updated += on_clip_updated;

        Gdk.Color.parse("000", out color_black);
        get_clip_colors();
        
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
              
        adjust_size(height);
    }

    void get_clip_colors() {
        Gdk.Color.parse(clip.type == Model.MediaType.VIDEO ? "#d82" : "#84a", 
            out color_selected);
        Gdk.Color.parse(clip.type == Model.MediaType.VIDEO ? "#da5" : "#b9d", 
            out color_normal);
    }
    
    void on_clip_updated() {
        queue_draw();
    }

    // Note that a view's size may vary slightly (by a single pixel) depending on its
    // starting position.  This is because the clip's length may not be an integer number of
    // pixels, and may get rounded either up or down depending on the clip position.
    public void adjust_size(int height) {       
        int width = time_provider.time_to_xpos(clip.start + clip.duration) -
                    time_provider.time_to_xpos(clip.start);                  
        set_size_request(width + 1, height);
    }
    
    public void on_clip_moved(Model.Clip clip) {
        adjust_size(height);
        clip_moved(this);
    }

    public void update_drag() {
        drag_updated(this);
    }
    
    public void delete_clip(bool ripple) {
        clip_deleted(clip, ripple);
    }
    
    public void draw() {
        if (ghost) {
            window.draw_rectangle(style.white_gc, false, allocation.x, 
                                    allocation.y, allocation.width - 1, allocation.height - 1);
        } else {
            weak Gdk.Color fill = is_selected ? color_selected : color_normal;
                                                                             
            bool left_trimmed = clip.media_start != 0;
            bool right_trimmed = clip.clipfile.is_online() ? 
                                  (clip.media_start + clip.duration != clip.clipfile.length) : false;
                
            if (!left_trimmed && !right_trimmed) {
                draw_rounded_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                       allocation.width - 2, allocation.height - 2);
                draw_rounded_rectangle(window, color_black, false, allocation.x, allocation.y,
                                       allocation.width - 1, allocation.height - 1);
                                       
            } else if (!left_trimmed && right_trimmed) {
                draw_left_rounded_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                            allocation.width - 2, allocation.height - 2);
                draw_left_rounded_rectangle(window, color_black, false, allocation.x, allocation.y,
                                       allocation.width - 1, allocation.height - 1);
                                       
            } else if (left_trimmed && !right_trimmed) {
                draw_right_rounded_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                             allocation.width - 2, allocation.height - 2);
                draw_right_rounded_rectangle(window, color_black, false, allocation.x, allocation.y,
                                             allocation.width - 1, allocation.height - 1);

            } else {
                draw_square_rectangle(window, fill, true, allocation.x + 1, allocation.y + 1,
                                      allocation.width - 2, allocation.height - 2);
                draw_square_rectangle(window, color_black, false, allocation.x, allocation.y,
                                      allocation.width - 1, allocation.height - 1);
            }
               
            Gdk.GC gc = new Gdk.GC(window);
            Gdk.Rectangle r = { 0, 0, 0, 0 };

            // Due to a Vala compiler bug, we have to do this initialization here...
            r.x = allocation.x;
            r.y = allocation.y;
            r.width = allocation.width;
            r.height = allocation.height;
            
            gc.set_clip_rectangle(r);

            Pango.Layout layout;
            if (!clip.clipfile.is_online()) {
                stderr.printf("offline\n");
                layout = create_pango_layout("%s (Offline)".printf(clip.name));
            }
            else {
                stderr.printf("online\n");
                layout = create_pango_layout("%s".printf(clip.name));
            }
            Gdk.draw_layout(window, gc, allocation.x + 10, allocation.y + 14, layout);
        }   
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        draw();
        return true;
    }
}
