#include "kythe/cxx/indexer/cxx/testdata/proto/testdata.pb.h"

void test_function() {
    //- @Message ref CcMessage
    proto::Message msg;
    //- @set_string_field ref CcSetStringField
    msg.set_string_field("blah")
}

//- Message generates CcMessage
//- StringField generates CcSetStringField
 


 