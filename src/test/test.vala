/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */


void main(string[] args) {
    Test.init(ref args);
    TestSuite.get_root().add_suite(new ProjectLoaderSuite());
    Test.run();
}
