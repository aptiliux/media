/* Copyright 2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface TransportDelegate : Object {
    public abstract bool is_playing();
    public abstract bool is_recording();
    public abstract bool is_stopped();
}
