/* Ported to Vala from singledecodebin.py in Pitivi:
 *
 * Copyright (c) 2005, Edward Hervey <bilboed@bilboed.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

using Gee;
using Logging;

extern void qsort(void *p, size_t num, size_t size, GLib.CompareFunc func);

// Single-stream queue-less decodebin

// returns true if the caps are RAW
bool is_raw(Gst.Caps caps) {
    string rep = caps.to_string();
    string[] valid = { "video/x-raw", "audio/x-raw", "text/plain", "text/x-pango-markup" };
    foreach (string val in valid)
        if (rep.has_prefix(val))
            return true;
    return false;
}

// A variant of decodebin.
// Only outputs one stream; doesn't contain any internal queue.
class SingleDecodeBin : Gst.Bin {
    Gst.Caps caps;
    Gst.Element typefind;
    Gst.GhostPad srcpad;
    
    ArrayList<Gst.Element> dynamics = new ArrayList<Gst.Element>();
    ArrayList<Gst.Element> validelements = new ArrayList<Gst.Element>();   // added elements
    Gst.ElementFactory[] factories;

    const int64 QUEUE_SIZE = 1 * Gst.SECOND;
  
    class construct {
        Gst.PadTemplate sink_pad = new Gst.PadTemplate("sinkpadtemplate", Gst.PadDirection.SINK, 
                                                        Gst.PadPresence.ALWAYS, new Gst.Caps.any());
        Gst.PadTemplate src_pad = new Gst.PadTemplate("srcpadtemplate", Gst.PadDirection.SINK, 
                                                        Gst.PadPresence.ALWAYS, new Gst.Caps.any());

        add_pad_template (src_pad);
        add_pad_template (sink_pad);
    }

    public SingleDecodeBin(Gst.Caps? caps, string name, string? uri) throws Error {
        this.caps = caps == null ? new Gst.Caps.any() : caps;

        typefind = Gst.ElementFactory.make("typefind", "internal-typefind");
        add(typefind);

        if (uri != null) {
            Gst.Element file_src = make_element("filesrc");

            file_src.set("location", uri);
            add(file_src);

            file_src.link(typefind);
        } else {
            Gst.GhostPad sinkpad = new Gst.GhostPad("sink", typefind.get_pad("sink"));
            sinkpad.set_active(true);
            add_pad(sinkpad);
        }
        Signal.connect(typefind, "have-type", (Callback) typefindHaveTypeCb, this);

        factories = getSortedFactoryList();
    }

    // internal methods

    void controlDynamicElement(Gst.Element element) {
        dynamics.add(element);
        element.pad_added += dynamicPadAddedCb;
        element.no_more_pads += dynamicNoMorePadsCb;
    }

    static int factory_compare(Gst.ElementFactory** a, Gst.ElementFactory** b) {
        Gst.PluginFeature* p1 = *(Gst.PluginFeature**)a;
        Gst.PluginFeature* p2 = *(Gst.PluginFeature**)b;
        return (int) (((Gst.PluginFeature) p2).get_rank() - ((Gst.PluginFeature) p1).get_rank());
    }

    // Returns the list of demuxers, decoders and parsers available, sorted by rank
    Gst.ElementFactory[] getSortedFactoryList() {
        Gst.Registry registry = Gst.Registry.get_default();
        Gst.ElementFactory[] factories = new Gst.ElementFactory[0];

        foreach (Gst.PluginFeature plugin_feature in 
            registry.get_feature_list(typeof(Gst.ElementFactory)) ) {

            Gst.ElementFactory factory = plugin_feature as Gst.ElementFactory;
            if (factory == null || factory.get_rank() < 64)
                continue;
            string klass = factory.get_klass();
            if (klass.contains("Demuxer") || klass.contains("Decoder") || klass.contains("Parse"))
                factories += factory;
        }

        qsort(factories, factories.length, sizeof(Gst.ElementFactory *), 
            (GLib.CompareFunc) factory_compare);
        return factories;
    }

    /* Returns a list of factories (sorted by rank) which can take caps as
     * input. Returns empty list if none are compatible. */
    Gee.ArrayList<Gst.ElementFactory> findCompatibleFactory(Gst.Caps caps) {
        Gee.ArrayList<Gst.ElementFactory> res = new Gee.ArrayList<Gst.ElementFactory>();

        foreach (Gst.ElementFactory factory in factories) {
            weak GLib.List<Gst.StaticPadTemplate?> templates = factory.get_static_pad_templates();
            foreach (Gst.StaticPadTemplate template in templates)
                if (template.direction == Gst.PadDirection.SINK) {
                    Gst.Caps intersect = caps.intersect(template.static_caps.get());
                    if (!intersect.is_empty()) {
                        res.add(factory);
                        break;
                    }
                }
        }

        return res;
    }

    // Inspect element and try to connect something on the srcpads.
    // If there are dynamic pads, set up a signal handler to
    // continue autoplugging when they become available.
    void closeLink(Gst.Element element) {
        Gst.Pad[] to_connect = new Gst.Pad[0];
        bool is_dynamic = false;

        foreach (Gst.PadTemplate template in element.get_pad_template_list ()) {
            if (template.direction != Gst.PadDirection.SRC)
                continue;
            if (template.presence == Gst.PadPresence.ALWAYS) {
                Gst.Pad pad = element.get_pad(template.name_template);
                to_connect += pad;
            } else if (template.presence == Gst.PadPresence.SOMETIMES) {
                Gst.Pad pad = element.get_pad(template.name_template);
                if (pad != null)
                    to_connect += pad;
                else is_dynamic = true;
            }
        }

        if (is_dynamic) {
            emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE,
                "%s is a dynamic element".printf(element.get_name()));
            controlDynamicElement(element);
        }

        foreach (Gst.Pad pad in to_connect)
            closePadLink(element, pad, pad.get_caps());
    }

    bool isDemuxer(Gst.Element element) {
        if (!element.get_factory().get_klass().contains("Demux"))
            return false;

        int potential_src_pads = 0;
        foreach (Gst.PadTemplate template in element.get_pad_template_list()) {
            if (template.direction != Gst.PadDirection.SRC)
                continue;

            if (template.presence == Gst.PadPresence.REQUEST ||
                template.name_template.contains("%")) {
                potential_src_pads += 2;
                break;
            } else potential_src_pads += 1;
        }

        return potential_src_pads > 1;
    }

    Gst.Pad plugDecodingQueue(Gst.Pad pad) {
        Gst.Element queue = Gst.ElementFactory.make("queue", null);
        queue.set_property("max_size_time", QUEUE_SIZE);
        add(queue);
        queue.sync_state_with_parent();
        pad.link(queue.get_pad("sink"));
        pad = queue.get_pad("src");

        return pad;
    }

    // Tries to link one of the factories' element to the given pad.
    // Returns the element that was successfully linked to the pad.
    Gst.Element tryToLink1(Gst.Element source, Gst.Pad in_pad, 
        Gee.ArrayList<Gst.ElementFactory> factories) {
        Gst.Pad? pad = in_pad;
        if (isDemuxer(source))
            pad = plugDecodingQueue(in_pad);

        Gst.Element result = null;
        foreach (Gst.ElementFactory factory in factories) {
            Gst.Element element = factory.create(null);
            if (element == null) {
                warning("couldn't create element from factory");
                continue;
            }

            Gst.Pad sinkpad = element.get_pad("sink");
            if (sinkpad == null)
                continue;

            add(element);
            element.set_state(Gst.State.READY);
            if (pad.link(sinkpad) != Gst.PadLinkReturn.OK) {
                element.set_state(Gst.State.NULL);
                remove(element);
                continue;
            }

            closeLink(element);
            element.set_state(Gst.State.PAUSED);

            result = element;
            break;
        }

        return result;
    }

    // Finds the list of elements that could connect to the pad.
    // If the pad has the desired caps, it will create a ghostpad.
    // If no compatible elements could be found, the search will stop.
    void closePadLink(Gst.Element element, Gst.Pad pad, Gst.Caps caps) {
        emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
            "element:%s, pad:%s, caps:%s".printf(element.get_name(),
                pad.get_name(),
                caps.to_string()));
        if (caps.is_empty()) {
            emit(this, Facility.SINGLEDECODEBIN, Level.INFO, "unknown type");
            return;
        }
        if (caps.is_any()) {
            emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, "type is not known yet, waiting");
            return;
        }

        pad.get_direction ();

        if (!caps.intersect(this.caps).is_empty()) {
            // This is the desired caps
            if (srcpad == null)
                wrapUp(element, pad);
        } else if (is_raw(caps)) {
            emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
                "We hit a raw caps which isn't the wanted one");
            // TODO : recursively remove everything until demux/typefind
        } else {
            // Find something
            if (caps.get_size() > 1) {
                emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
                    "many possible types, delaying");
                return;
            }
            Gee.ArrayList<Gst.ElementFactory> facts = findCompatibleFactory(caps);
            if (facts.size == 0) {
                emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
                    "unknown type");
                return;
            }
            tryToLink1(element, pad, facts);
       }
    }

    // Ghost the given pad of element.
    // Remove non-used elements.
    void wrapUp(Gst.Element element, Gst.Pad pad) {
        if (srcpad != null)
            return;
        markValidElements(element);
        removeUnusedElements(typefind);
        emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
            "ghosting pad %s".printf(pad.get_name()));
        srcpad = new Gst.GhostPad("src", pad);
        if (caps.is_fixed()) {
            srcpad.set_caps(caps);
        }
        srcpad.set_active(true);
        
        add_pad(srcpad);
        post_message(new Gst.Message.state_dirty(this));
    }

    // Mark this element and upstreams as valid
    void markValidElements(Gst.Element element) {
        emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
            "element:%s".printf(element.get_name()));
        if (element == typefind)
            return;
        validelements.add(element);

        // find upstream element
        Gst.Pad pad = (Gst.Pad) element.sinkpads.first().data;
        Gst.Element parent = pad.get_peer().get_parent_element();
        markValidElements(parent);
    }

    //  Remove unused elements connected to srcpad(s) of element
    void removeUnusedElements(Gst.Element element) {
        foreach (Gst.Pad pad in element.srcpads)
            if (pad.is_linked()) {
                Gst.Element peer = pad.get_peer().get_parent_element();
                removeUnusedElements(peer);
                if (!(peer in validelements)) {
                    emit(this, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
                        "removing %s".printf(peer.get_name()));
                    pad.unlink(pad.get_peer());
                    peer.set_state(Gst.State.NULL);
                    remove(peer);
                }
            }
    }

    void cleanUp() {
        if (srcpad != null)
            remove_pad(srcpad);
        srcpad = null;
        foreach (Gst.Element element in validelements) {
            element.set_state(Gst.State.NULL);
            remove(element);
        }
        validelements = new Gee.ArrayList<Gst.Element>();
    }

    // Overrides

    public override Gst.StateChangeReturn change_state(Gst.StateChange transition) {
        Gst.StateChangeReturn res = base.change_state(transition);
        if (transition == Gst.StateChange.PAUSED_TO_READY)
            cleanUp();
        return res;
    }

    // Signal callbacks

    static void typefindHaveTypeCb(Gst.Element t, int probability, Gst.Caps caps, 
                                                                            SingleDecodeBin data) {
        emit(data, Facility.SINGLEDECODEBIN, Level.VERBOSE, 
            "probability:%d, caps:%s".printf(probability, caps.to_string()));
        data.closePadLink(t, t.get_pad("src"), caps);
    }

    // Dynamic element Callbacks

    void dynamicPadAddedCb(Gst.Element element, Gst.Pad pad) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "dynamicPadAddedCb");
        if (srcpad == null)
            closePadLink(element, pad, pad.get_caps());
    }

    void dynamicNoMorePadsCb(Gst.Element element) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "dynamicNoMorePadsCb");
    }
}

