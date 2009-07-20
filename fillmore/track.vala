/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Gee;

class Track {
    public string name;
    ArrayList<Region> regions = new ArrayList<Region>();
    
    public Gst.Bin composition;
    
    public TrackHeader header;
    
    public signal void region_added(Region r);
    public signal void region_removed(Region r);
    public signal void track_renamed();
    
    public Track(string name) {
        this.name = name;
        composition = (Gst.Bin) make_element("gnlcomposition");
        
        Gst.Element silence = Gst.ElementFactory.make("audiotestsrc", "audiotestsrc_default");
        if (silence == null)
            error("can't create element");
        silence.set("wave", 4);     // 4 is silence
        
        Gst.Element default_source = make_element("gnlsource");
        Gst.Bin default_source_bin = (Gst.Bin) default_source;
        if (!default_source_bin.add(silence))
            error("can't add");

        // If we set the priority to 0xffffffff, then Gnonlin will treat this source as
        // a default and we won't be able to seek past the end of the last region.
        // We want to be able to seek into empty space, so we use a fixed priority instead.
        default_source.set("priority", 1);
        default_source.set("start", 0 * Gst.SECOND);
        default_source.set("duration", 1000000 * Gst.SECOND);
        default_source.set("media-start", 0 * Gst.SECOND);
        default_source.set("media-duration", 1000000 * Gst.SECOND);
        if (!composition.add(default_source))
            error("can't add");
    }
    
    public int64 end() {
        int64 end = 0;
        
        foreach (Region r in regions)
            end = int64.max(end, r.end());
        return end;
    }
    
    public void add_source(Region r) {
        if (!composition.add(r.file_source))
            error("can't add");
    }
    
    public void add(Region r) {
        regions.add(r);
        r.track = this;
        
        if (r.file_source != null)
            add_source(r);

        region_added(r);
    }
    
    public void remove(Region r) {
        if (r.file_source != null && !composition.remove(r.file_source))
            error("can't remove");
        
        if (!regions.remove(r))
            error("can't remove");
        r.track = null;
        
        region_removed(r);
    }
    
    
    public void rename(string new_name) {
        name = new_name;
        track_renamed();
    }
}

