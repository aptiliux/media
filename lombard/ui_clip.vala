/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class GapView : Gtk.DrawingArea {
    public TrackView trackview;
    
    public Model.Gap gap;
    Gdk.Color fill_color;
    
    public GapView(int64 start, int64 length, TrackView owner) {
        trackview = owner;
        
        gap = new Model.Gap(start, start + length);         
        
        Gdk.Color.parse("#777", out fill_color);
        
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        
        int width = trackview.timeline.time_to_xpos(start + length) -
                    trackview.timeline.time_to_xpos(start);            
        set_size_request(width + 1, TrackView.clip_height);
    }  
    
    public override bool expose_event(Gdk.EventExpose e) {
        draw_rounded_rectangle(window, fill_color, true, allocation.x, allocation.y, 
                                allocation.width - 1, allocation.height - 1);
        return true;
    }
}

class ClipView : Gtk.DrawingArea {
    public Model.Clip clip;
    public TrackView trackview;
    public bool ghost;

    Gdk.Color color_black;    
    Gdk.Color color_normal;
    Gdk.Color color_selected;
    
    public ClipView(Model.Clip clip, TrackView owner) {
        this.clip = clip;
        trackview = owner;
        ghost = false;
        
        clip.moved += on_clip_moved;

        Gdk.Color.parse("000", out color_black);
        Gdk.Color.parse(clip.type == Model.MediaType.VIDEO ? "#d82" : "#84a", out color_selected);
        Gdk.Color.parse(clip.type == Model.MediaType.VIDEO ? "#da5" : "#b9d", out color_normal);
        
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
              
        adjust_size();
    }

    // Note that a view's size may vary slightly (by a single pixel) depending on its
    // starting position.  This is because the clip's length may not be an integer number of
    // pixels, and may get rounded either up or down depending on the clip position.
    public void adjust_size() {       
        int width = trackview.timeline.time_to_xpos(clip.start + clip.length) -
                    trackview.timeline.time_to_xpos(clip.start);                  
        set_size_request(width + 1, TrackView.clip_height);
    }
    
    public void on_clip_moved() {
        adjust_size();
        trackview.set_clip_pos(this);
    }

    public void draw() {
        if (ghost) {
            window.draw_rectangle(style.white_gc, false, allocation.x, 
                                    allocation.y, allocation.width - 1, allocation.height - 1);
        } else {
            weak Gdk.Color fill = trackview.timeline.selected_clip == 
                                    this ? color_selected : color_normal;
                                                                             
            bool left_trimmed = clip.media_start != 0;
            bool right_trimmed = clip.media_start + clip.length != clip.clipfile.length;
                
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

            Pango.Layout layout = create_pango_layout(clip.name);
            
            Gdk.GC gc = new Gdk.GC(window);
            Gdk.Rectangle r = { 0, 0, 0, 0 };

            // Due to a Vala compiler bug, we have to do this initialization here...
            r.x = allocation.x;
            r.y = allocation.y;
            r.width = allocation.width;
            r.height = allocation.height;
            
            gc.set_clip_rectangle(r);
            Gdk.draw_layout(window, gc, allocation.x + 10, allocation.y + 14, layout);
        }   
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        draw();
        return true;
    }
}
