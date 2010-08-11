/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {

public class ClipFetcher {
    public string error_string;
    public MediaFile mediafile;
    string filename;
    
    public ClipFetcher(string filename) {
        this.filename = filename;
    }
    public string get_filename() {
        return filename;
    }
    public signal void ready(ClipFetcher fetcher);
}
}
// Describes an XML Document and if the test should consider it a valid or an invalid document
struct ValidDocument {
    public bool valid;
    public string document;
    public ValidDocument(bool valid, string document) {
        this.valid = valid;
        this.document = document;
    }
}

ValidDocument[] project_documents; // The set of documents for building the test suite
int current_document; // Index of the document for the test we are currently building

// StateChangeFixture holds the root of an XML tree describing a project, the TreeBuilder
// and if the XML tree is expected to be valid or not
struct StateChangeFixture {
    public Model.XmlElement root;
    public Model.ProjectBuilder project_builder;
    public bool valid;
}

void state_change_fixture_buildup(void *fixture) {
    StateChangeFixture* state_change_fixture = (StateChangeFixture*)fixture;
    Model.XmlTreeLoader tree_loader = new Model.XmlTreeLoader(project_documents[current_document].document);
    state_change_fixture->root = tree_loader.root;
    state_change_fixture->project_builder = new Model.ProjectBuilder(new Model.LoaderHandler());
    state_change_fixture->valid = project_documents[current_document].valid;
    ++current_document;
}

void state_change_fixture_teardown(void *fixture) {
    StateChangeFixture* state_change_fixture = (StateChangeFixture*)fixture;
    state_change_fixture->root = null;
    state_change_fixture->project_builder = null;
}

bool document_valid; // if a document is invalid, on_error_occurred will set this variable to false

void on_error_occurred(Model.ErrorClass error_class, string? message) {
    Test.message("received error: %s", message);
    document_valid = false;
}

// The actual test code.  It builds the given document and then asserts that the result is what
// was expected.
void check_document(void *fixture) {
    StateChangeFixture* state_change_fixture = (StateChangeFixture*)fixture;

    Test.message("checking document expecting to be %s", 
        state_change_fixture->valid ? "valid" : "invalid");

    Model.XmlElement root = state_change_fixture->root;
    Model.ProjectBuilder project_builder = state_change_fixture->project_builder;

    document_valid = true;
    project_builder.error_occurred.connect(on_error_occurred);
    
    // We call check project to check the integrity of the file skeleton.
    // If it's good, then we can load all the pieces of the file (library, tracks).
    if (project_builder.check_project(root))
        project_builder.build_project(root);
    assert(document_valid == state_change_fixture->valid);
    Test.message("finished executing check document");
}


class ProjectLoaderSuite : TestSuite {
    public ProjectLoaderSuite() {
        base("ProjectLoaderSuite");

        current_document = 0;
        project_documents = {
            ValidDocument(true, "<marina><library></library><tracks><track><clip /><clip /></track>"
                    + "<track><clip /></track></tracks><preferences /></marina>"),
            ValidDocument(true, "<marina><library /><tracks /><preferences/>"
                    + "<maps><tempo /><time_signature /></marina>"),
            ValidDocument(true, "<marina><library /><tracks /><preferences/><maps><tempo />"
                    + "</marina>"),
            ValidDocument(true, "<marina><library /><tracks /><preferences/>"
                    + "<maps><time_signature /></marina>"),
            ValidDocument(true, "<marina><library></library><tracks><track /></tracks>"
                    + "<preferences/></marina>"),
            ValidDocument(true, "<marina><library></library><tracks><track><clip /></track>"
                    + "</tracks><preferences/></marina>"),
            ValidDocument(true, "<marina><library/><tracks/><preferences/>"
                    + "<maps><tempo><entry></tempo></maps></marina>"),
            ValidDocument(true, "<marina><library/><tracks/><preferences/>"
                    +"<maps><time_signature><entry></time_signature></maps></marina>"),
            ValidDocument(true, "<marina><library/><tracks/><preferences/></marina>"),
            ValidDocument(true, "<marina><library/><tracks/><preferences><click/></preferences>"
                + "</marina>"),
            ValidDocument(true, "<marina><library/><tracks/><preferences><library/>" + 
                "</preferences></marina>"),
            ValidDocument(true, "<marina><library/><tracks/><preferences><click/><library/>" +
                "</preferences></marina>"),
            ValidDocument(false, "<marina><tracks></tracks><library></library></marina>"),
            ValidDocument(false, "<marina><library></library><track></track></marina>"),
            ValidDocument(false, "<marina><library><clip /></library><tracks><clipfile />"
                    + "</tracks></marina>"),
            ValidDocument(false, "<marina />"),            
            ValidDocument(false, "<library />"),
            ValidDocument(false, "<track />"),
            ValidDocument(false, "<clip />"),
            ValidDocument(false, "<entry />"),
            ValidDocument(false, "<tempo />"),
            ValidDocument(false, "<maps />"),
            ValidDocument(false, "<preferences />"),
            ValidDocument(false, "<click />"),
            ValidDocument(false, "<time_signature />"),
            ValidDocument(false, "<marina><clip /></marina>"),
            ValidDocument(false, "<marina><track><clip><track /></clip></track></marina>"),
            ValidDocument(false, "<unknown />"),
            ValidDocument(false, "<marina><foo /></marina>"),
            ValidDocument(false, "<marina><track><foo /></track></track></marina>"),
            ValidDocument(false, "<marina><track><clip><foo /></clip></track></marina>"),
            ValidDocument(false, "<marina><library/><tracks/><maps><foo/></maps></marina>"),
            ValidDocument(false, "<marina><library/><tracks/><maps><time_signature>"
                    + "<tempo/></time_signature></marina>"),
            ValidDocument(false, "<marina><library/><tracks/><click/></marina>"),
            ValidDocument(false, "<marina><library/><tracks/><preferences><tracks/>"
                    +"</preferences></marina>"),
            ValidDocument(false, "<marina><library/><tracks/><maps/><preferences/></marina>")
        };
        
        int length = project_documents.length;
        
        for (int i = 0; i < length; ++i) {
            if (Test.thorough() || project_documents[i].valid) {
                add(new TestCase("Document%d".printf(i), state_change_fixture_buildup, 
                    check_document, state_change_fixture_teardown, sizeof(StateChangeFixture)));
            }
        }
    }
}

