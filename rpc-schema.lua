

local schema = require './schema'
local schema_schema = require './schema_bootstrap'


local S = schema.newschema("rpc", "the primary schema for rpc connections", "658d7e89c7bce12f")

local questionId = S:newtype("questionId", schema.u32)
local exportId = S:newtype("exportId", schema.u32)


S:struct "question" "The actual data sent in a question describing what to do. This deliberately doesn't include the actual id of the question. The systems"
{
  union "kind" (0) "What the system is asking to be done"
  {
    variant "method" (1) "The question is calling a method on a specific interface on a known object"
    {
      schema.anycap "receiver" (2) "the object to call a method on";
      schema_schema.export.typeid "interface" (3) "what interface type to treat the object as";
      schema.variantid "method" (4) "which method from the interface to call";
      schema.anypointer "args" (5) "the arguments for the method, encoded as a struct";
    };
    variant "bootstrap" (6) "Try to retrieve an initial public capability from the vat if one exists" {};
    variant "accept"
  };
}

S:struct "exception" "A description of a failure"
{

}

S:struct "refdescriptor" "A description of a capability reference in the scope of a connection"
{
  union "kind" (0) "What the domain of the reference is"
  {
    variant "none" (1) "An empty reference, just in case something is assembling a message in place and needs to remove something from a fixed size list without rewriting other pointers. There should be no pointers referring to this slot." {};
    variant "recieverHosted" (2) "This is a reference to something exported in the reciever's exports table"
    {
      exportId "idx" (3);
    };
    variant "senderHosted" (4) "This reference refers to something that the sender has exported to the reciever, and thus may be found in the reciever's import table"
    {
      exportId "idx" (5);
    };
    variant "recieverAnswer" (6) "This reference refers to something the sender expects to be provided as an answer to a question"
    {
      questionId "idx" (7) "which answer to start with";
      list(schema.u16) "path" (8) "offsets into the pointer sections to request the actual cap, this is temporary and should be replaced with a more versatile request patching system to allow pipelining on non-pointer types. Due to the complexity of that solution, this very inadequate approach is being taken as a simple alternative that will force a proper implementation to happen later";
    };
    variant "senderPromise" (9) "This reference refers to something which the sender has a promise to which it is making available to the reciever. It may be invoked as if it were hosted and the sender takes responsibility for buffering or forwarding messages as appropriate. The sender will send zero or one resolve messages to replace this promise with something else."
    {
      exportId "idx" (10);
    };
    variant "thirdPartyHosted" (11) "This reference refers to something hosted by a third party and which the receiver is expected to directly connect to make use of if possible."
    {
      exportId "proxy" (12) "A proxy for the remote capability hosted on the sender to ensure pinning for the duration of the three way handshake and to allow a fallback for clients that don't know how to connect to the actual host to make calls on";
      list(schema.anydoc) "source" (13) "A list of ways that we or the third party host believe that the host of this object can be reached, the receiver may discard any that it doesn't understand and try the remainder in any strategy it pleases and may reuse an existing connection to the host, but must only accept the provided cap once.";
      schema.blob "nonce" (14) "a cryptographic nonce to present to the third party as proof of being the intended recipient of the transfer";
    };
  };
}

payload = S:genericstruct "refwrapper" (function(descriptor, payload)
    return {
      list(descriptor) "references" (0) "The backing reference descriptions which cap-pointers in the payload refer to";
      payload "payload" (1) "the data which may contain cap-pointers that should be resolved by the references described here.";
      })

local call = S:struct "methodcall" "A description of the information required to perform a method call"
{

}

local message = S:addstruct("message",
[[ An RPC connection is a bidirectional DAG of messages. Messages are packed into a packet and sent over the wire in a prioritized topographical order.
When packets arrive, their contents are deserialized and the dag is reconstructed, possiby including holes from missing packets.
The acknowledgement system must retransmit any dropped packets so that eventually all holes are filled or the connection fails and subsequent calls error.
The reciever will take deserialized messages in prioritized topographical order, delaying any holes until they are filled and holding messages until their dependencies are dispatched.

These properties are fulfilled if the packets are a simple ordered reliable stream, however the performance decreases dramatically, so building on top of a protocol that permits unordered and/or unreliable transport is desirable.
Thus, the main implementation of this protocol will be UDP based.
]])

message:define {
  union "kind" (0) "what operation the message specifies to perform"
  {
    variant "unimplemented" (1) "The message isn't understood, and the message content is being echoed back in the hopes that the other side can recover from the missing feature"
    {
      message "echo" (2) "the message which this vat didn't understand";
    };
    variant "abort" (3) "the connection is being terminated deliberately for a reason"
    {
      S.exports.exception "error" (4) "the error causing the termination";
    };
    variant "bootstrap" (5) "retrieve the public bootstrap interface. Not all systems need to provide a public bootstrap interface, or include methods on it. However, it can be good for debugability to implement the introspection and schema sharing interfaces on this."
    {
      questionId "question" (6) "what question id slot this operation was assigned";
    };
    variant "call" (7) "Want to call a method on a thing"
    {
      questionId "question" (8) "what question id slot this operation was assigned";
    }
  }
}
