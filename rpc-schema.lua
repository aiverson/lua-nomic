

local schema = require './schema'
local schema_schema = require './schema_bootstrap'


local S = schema.newschema("rpc", "the primary schema for rpc connections", "658d7e89c7bce12f")

local questionId = S:newtype("questionId", schema.u32)
local exportId = S:newtype("exportId", schema.u32)

S:struct "Ins" "A single instruction of the rpc calls"
{
  union "op" (0) "Which operation is being requested. These variants should have at most 16 bits of fields in order to fit them in tightly packed lists. These instructions form a stack based language used to patch and assemble calls for the RPC protocol. It shouldn't be turing complete, or even capable of superlinear behavior. It is needed to patch calls in order to pipeline primitives. If bytes in a message will be a target of an assignment they must be present, even if normalization rules would otherwise permit them to be elided."
  {
    variant "nop" (1) "Because every instruction format must have a nop" {};
    variant "get1s" (2) "Retrieve a one bit data value from a struct. Expects the pointer to the struct to be on the top of the stack"
    {
      u16 "offset" (3);
    };
    variant "get8s" (4) "Retrieve an eight bit data value from a struct. Expects the pointer to the struct to be on the top of the stack"
    {
      u16 "offset" (5);
    };
    variant "get16s" (6) "Retrieve a sixteen bit data value from a struct. Expects the pointer to the struct to be on the top of the stack"
    {
      u16 "offset" (7);
    };
    variant "get32s" (8) "Retrieve a 32 bit data value from a struct. Expects the pointer to the struct to be on the top of the stack"
    {
      u16 "offset" (9);
    };
    variant "get64s" (10) "Retrieve a 64 bit data value from a struct. Expects the pointer to the struct to be on the top of the stack"
    {
      u16 "offset" (11);
    };
    variant "getps" (12) "Retrieve a pointer value from a struct. Expects the pointer to the struct to be on the top of the stack"
    {
      u16 "offset" (13);
    };
    variant "set1s" (14) "Assign a one bit data value into a struct. Expects the value to be assigned to be on the top of the stack with the pointer to the struct beneath it"
    {
      u16 "offset" (15);
    };
    variant "set8s" (16) "Assign an eight bit data value into a struct. Expects the value to be assigned to be on the top of the stack with the pointer to the struct beneath it"
    {
      u16 "offset" (17);
    };
    variant "set16s" (18) "Assign a sixteen bit data value into a struct. Expects the value to be assigned to be on the top of the stack with the pointer to the struct beneath it"
    {
      u16 "offset" (19);
    };
    variant "set32s" (20) "Assign a 32 bit data value into a struct. Expects the value to be assigned to be on the top of the stack with the pointer to the struct beneath it"
    {
      u16 "offset" (21);
    };
    variant "set64s" (22) "Assign a 64 bit data value into a struct. Expects the value to be assigned to be on the top of the stack with the pointer to the struct beneath it"
    {
      u16 "offset" (23);
    };
    variant "setps" (24) "Assign a pointer value into a struct. Expects the value to be assigned to be on the top of the stack with the pointer to the struct beneath it"
    {
      u16 "offset" (25);
    };
    variant "dup" (26) "duplicate a value onto the top of the stack"
    {
      u16 "offset" (41) "The offset from the top of the stack of the item to duplicate";
    };
    variant "drop" (27) "remove the value on the top of the stack" {};
    variant "pushref" (28) "push a reference from the reference pool associated with this call onto the stack"
    {
      u16 "loc" (29);
    };
    variant "pushimm" (30) "push an immediate 16 bit value onto the stack"
    {
      u16 "val" (31);
    };
    variant "imm32" (32) "write an immediate 16 bit value into bits 17-32 of the top of the stack"
    {
      u16 "val" (33);
    };
    variant "imm48" (34) "write an immediate 16 bit value into bits 33-48 of the top of the stack"
    {
      u16 "val" (35);
    };
    variant "imm64" (36) "write an immediate 16 bit value into bits 49-64 of the top of the stack"
    {
      u16 "val" (37);
    };
    variant "bootstrap" (38) "push the bootstrap capability exposed by the host vat onto the stack, if any. Not all vats must expose a bootstrap capability." {};
    variant "call" (39) "Call a method on a capability. The top of the stack should be the struct pointer of the arguments to send to the call, followed by the capability pointer on which the method is being called. The interface id and method id for the call are retrieved from the interface pool associated with the rpc call at the index provided with the instruction."
    {
      u16 "method" (40) "which method this call is calling on.";
    };
    variant "assertvariant" (42) "require that the top of the stack has a particular variant id, allowing implementing a simple guard clause that fails the call if the value isn't the expected variant."
    {
      u16 "variant" (43) "the variant it must match. To check the variant use get16s to retrieve the variant code then an assertvariant instruction to ensure the value."
    }
  };
}

S:struct "methodid" "The interface and method id that identify a specific method in an rpc session"
{
  u64 "interface" (0);
  u16 "method" (1);
}

S:struct "question" "The actual data sent in a question describing what to do. This deliberately doesn't include the actual id of the question. The systems"
{
  union "kind" (0) "What the system is asking to be done"
  {
    variant "invoke" (1) "This question is a call of an interface method. The instructions may patch the "
    {
      list(S.export.Ins) "prog" (2) "The instructions composing this rpc call";
      schema.anypointer "initial" (8) "The struct used for the initial value on the stack";
      list(S.export.refdescriptor) "refpool" (3) "The references which this rpc call considers data dependencies";
      list(S.export.methodid) "methods" (4) "The methods which this rpc call intends to invoke";
    };
  };
  list(S.export.refdescriptor) "causaldeps" (5) "The references which this question considers to be required to resolve before it.";
  bool "dontreturn" (6) "Whether or not this question should have its answer sent over the wire to the originator. If a value will only be used for pipelined calls before being dropped, setting this flag will reduce network traffic";
  bool "dontpipeline" (7) "If this flag is set, the answer will not be used for pipelining. This doesn't do much, because the value must be retained for retransmission in case of packet loss anyways, but maybe this provides an optimization.";

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
