/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
namespace Logging {

public enum Facility {
    SIGNAL_HANDLERS,
    DEVELOPER_WARNINGS
}

public enum Level {
    CRITICAL,
    HIGH,
    MEDIUM,
    LOW,
    INFO,
    VERBOSE
}

const Level active_facility[] = {
    Level.CRITICAL, // SIGNAL_HANDLERS
    Level.CRITICAL // DEVELOPER_WARNINGS
};

const string facility_names[] = {
    "SIGNAL_HANDLERS",
    "DEVELOPER_WARNINGS"
};

Level current_level = Level.HIGH;

public void emit(Object object, Facility facility, Level level, string message) {
    if (level <= current_level || level <= active_facility[facility]) {
        stderr.printf("%s(%s): %s\n", object.get_type().name(), facility_names[facility], message);
    }
}
}
