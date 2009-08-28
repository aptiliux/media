/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {

public class ClipFetcher {
    public string error_string;
    public ClipFile clipfile;
    string filename;
    
    public ClipFetcher(string filename) {
        this.filename = filename;
    }
    public string get_filename() {
        return filename;
    }
    public signal void ready();
}

public class ClipFile {
    public string filename;
}
}


Model.ProjectLoader.Actions[,] bad_transitions;

struct IncorrectStartFixture {
    public Model.ProjectLoader loader;
    public Gee.ArrayList<Model.ProjectLoader.Actions?> actions;
}

int current_action = 0;

string action_to_string(Model.ProjectLoader.Actions action) {
    string[] strings = {"PROJ", "TRACK", "ORPHAN_T", "CLIP", "INV"};
    return strings[action];
}

void incorrect_buildup(void *fixture) {
    Test.message("incorrect_buildup");
    IncorrectStartFixture* incorrect_start_fixture = (IncorrectStartFixture *) fixture;
    incorrect_start_fixture->actions = new Gee.ArrayList<Model.ProjectLoader.Actions?>();
    int index = 0;
    while (bad_transitions[current_action, index] != Model.ProjectLoader.Actions.INV) {
        Test.message("Action %s", action_to_string(bad_transitions[current_action, index]));
        incorrect_start_fixture->actions.add(bad_transitions[current_action, index]);
        ++index;
    }
    ++current_action;
    incorrect_start_fixture->loader = new Model.ProjectLoader(new Model.LoaderHandler(), "");
    Test.message("incorrect_buildup done");
}

void incorrect_teardown(void *fixture) {
    IncorrectStartFixture* incorrect_start_fixture = (IncorrectStartFixture *) fixture;
    incorrect_start_fixture->loader = null;
    incorrect_start_fixture->actions = null;
}

void incorrect_order(void *fixture) {
    Test.message("executing incorrect_order");
    IncorrectStartFixture* incorrect_start_fixture = (IncorrectStartFixture*)fixture;
    Model.ProjectLoader loader = incorrect_start_fixture->loader;

    int number_of_elements = incorrect_start_fixture->actions.size;
    Test.message("%d elements", number_of_elements);
    
    for (int i=0;i<number_of_elements - 1;++i) {
        Test.message("Starting transition %d", i);
        loader.state_transition(true, incorrect_start_fixture->actions[i], {""}, {""});
        assert(loader.loading_state != Model.ProjectLoader.States.INV);
    }
    Test.message("Executing final transition");
    loader.state_transition(true, incorrect_start_fixture->actions[number_of_elements - 1], {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.INV);
    Test.message("finished executing incorrect_order");
}

struct StateChangeFixture {
    public Model.ProjectLoader loader;    
}

void state_change_fixture_buildup(void *fixture) {
    StateChangeFixture* state_change_fixture = (StateChangeFixture*)fixture;
    state_change_fixture->loader = new Model.ProjectLoader(new Model.LoaderHandler(), "");
}

void state_change_fixture_teardown(void *fixture) {
    StateChangeFixture* state_change_fixture = (StateChangeFixture*)fixture;
    state_change_fixture->loader = null;
}

void correct_order(void *fixture) {
    Test.message("executing correct order");
    
    StateChangeFixture* state_change_fixture = (StateChangeFixture*)fixture;
    Model.ProjectLoader loader = state_change_fixture->loader;

    //entering and leaving in correct order
    loader.state_transition(true, Model.ProjectLoader.Actions.PROJ, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.PROJ);
    
    loader.state_transition(true, Model.ProjectLoader.Actions.TRACK, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.TRACK);
    
    loader.state_transition(true, Model.ProjectLoader.Actions.CLIP, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.CLIP);
    
    loader.state_transition(false, Model.ProjectLoader.Actions.CLIP, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.TRACK);

    loader.state_transition(false, Model.ProjectLoader.Actions.TRACK, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.PROJ);
    
    loader.state_transition(true, Model.ProjectLoader.Actions.ORPHAN_T, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.ORPHAN_T);
    
    loader.state_transition(true, Model.ProjectLoader.Actions.CLIP, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.ORPHAN_C);
    
    loader.state_transition(false, Model.ProjectLoader.Actions.CLIP, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.ORPHAN_T);
    
    loader.state_transition(false, Model.ProjectLoader.Actions.TRACK, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.PROJ);
    
    loader.state_transition(true, Model.ProjectLoader.Actions.TRACK, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.TRACK);
    
    loader.state_transition(false, Model.ProjectLoader.Actions.TRACK, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.PROJ);
    
    loader.state_transition(false, Model.ProjectLoader.Actions.PROJ, {""}, {""});
    assert(loader.loading_state == Model.ProjectLoader.States.NULL);
    Test.message("finished executing correct order");
}

class ProjectLoaderSuite : TestSuite {
    public ProjectLoaderSuite() {
        base("ProjectLoaderSuite");
        add(new TestCase("CorrectOrder", sizeof(StateChangeFixture), state_change_fixture_buildup, 
            correct_order, state_change_fixture_teardown));

        Model.ProjectLoader.Actions eol = Model.ProjectLoader.Actions.INV;
        Model.ProjectLoader.Actions proj = Model.ProjectLoader.Actions.PROJ;
        Model.ProjectLoader.Actions track = Model.ProjectLoader.Actions.TRACK;
        Model.ProjectLoader.Actions ot = Model.ProjectLoader.Actions.ORPHAN_T;
        Model.ProjectLoader.Actions clip = Model.ProjectLoader.Actions.CLIP;
        
        bad_transitions = {
            {clip, eol, eol, eol, eol}, 
            {ot, eol, eol, eol, eol}, 
            {track, eol, eol, eol, eol},
            {proj, clip, eol, eol, eol},
            {proj, track, track, eol, eol},
            {proj, track, ot, eol, eol},
            {proj, track, proj, eol, eol},
            {proj, track, clip, track, eol},
            {proj, track, clip, proj, eol},
            {proj, track, clip, ot, eol},
            {proj, track, clip, clip, eol},
            {proj, ot, track, eol, eol},
            {proj, ot, ot, eol, eol},
            {proj, ot, proj, eol, eol},
            {proj, ot, clip, proj, eol},
            {eol, eol, eol, eol, eol}
        };

        if (Test.thorough()) {
            int i=0;
            while (bad_transitions[i,0] != eol) {
                add(new TestCase("IncorrectStart %d".printf(i), sizeof(IncorrectStartFixture),
                    incorrect_buildup, incorrect_order, incorrect_teardown));
                ++i;
            }
        }
    }
}

