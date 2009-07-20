/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

Gst.Element make_element(string name) {
    Gst.Element e = Gst.ElementFactory.make(name, null);
    if (e == null)
        error("can't create element: %s", name);
    return e;
}

Gdk.Color parse_color(string color) {
    Gdk.Color c;
    if (!Gdk.Color.parse(color, out c))
        error("can't parse color");
    return c;
}

