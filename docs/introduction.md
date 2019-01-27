# KNXnet/IP introduction

KNXnet/IP is a protocol for connecting to a KNX bus over an IP network (like
local LAN or the Internet). So let's start with taking a look at KNX.

## So what's KNX?

KNX is an open standard for building automation. Building automation is a
wide term that covers many use cases, including but not limited to:

- Turning off the heat when windows are opened.
- Controlling ventilation based on indoor air quality.
- Turning on or off all light sources with a single switch.
- Automatic adjustment of window shades based on light level (and open them
  when a fire alarm is triggered).

To enable all these different use cases, many different sensors and actuators
need to be able to communicate. The KNX standard specifies how to establish a
network with such devices, and how the devices must communicate to ensure
interoperability.

### The KNX network

To establish a KNX network, all the building automation devices are connected
to a bus, and they communicate by sending and receiving messages (called
telegrams) on the bus. An example network might look like this:

     +----------+        +----------+      +----------+
     |          |        |          |      |          |
     | Switch A |        | Switch B |      | Switch C |
     | 3.4.1    |        | 3.4.2    |      | 3.4.3    |
     | 4/1/1    |        | 4/1/2    |      | 4/1/3    |
     |          |        |          |      |          |
     +-----+----+        +-----+----+      +-----+----+     +----------+
           |                   |                 |          |          |
           |                   |                 |          | Switch X |
    -------+-------------------+-----------------+----------+ 3.4.4    |
           |                   |                 |          | 4/4/1    |
           |                   |                 |          |          |
     +-----+----+        +-----+----+       +----+-----+    +----------+
     |          |        |          |       |          |
     |  Lamp A  |        |  Lamp B  |       |  Lamp C  |
     |  2.4.1   |        |  2.4.2   |       |  2.4.3   |
     |  4/1/1   |        |  4/1/2   |       |  4/1/3   |
     |  4/4/1   |        |  4/4/1   |       |  4/4/1   |
     |          |        |          |       |          |
     +----------+        +----------+       +----------+

On this bus there are three lamps, and four switches.

Each device on the bus has one unique individual address (also called
physical address). Individual addresses are numbers separated by dots, e.g.
Switch A has individual address 3.4.1. Individual addresses are used when
programming the devices, and to identify the sender of a given telegram.

In addition to individual addresses, a device can also be associated with one
(or several) group addresses. Group addresses are numbers separated by
slashes, e.g. Switch A is associated with group address 4/1/1. Group
addresses are used when creating the logic of the network. When Switch A is
associated with 4/1/1, this means that pressing the switch will cause the
switch to send a telegram to the group address 4/1/1.

Lamp A is also associated with group address 4/1/1 - that means that this
actuator will listen for telegrams on this address. When it receives a
telegram, it will either turn on or off, depending on the content of the
telegram it receives.

So for this particular network, switches A to C are used to control lamps A
to C, as their group addresses match. In addition, all the lamps are
associated with 4/4/1, which Switch X is also associated with. This means
Switch X can be used to control all the lamps with a single press.

Group addresses can be thought of as global variables. Any device connected
to the network can write to and read from these variables. To do so only
requires the ability to send a telegram to the network. Let's take a closer
look at telegrams.

### KNX telegrams

When a switch (or some other sensor) needs to tell the network that it
changed state, it does so by sending a GroupValueWrite telegram to the
network. The telegram will contain a few different fields, the most important
of which are:

- Service: The type of telegram. GroupValueWrite in the case of group writes.
- Sender: The individual address of the device that sent the message.
- Destination: The group address that it is meant for.
- Value: The new value at the sensor.

If you press Switch A above when it is an off-state, it will send a telegram
like this:

- Service: GroupValueWrite.
- Sender: 3.4.1.
- Destination: 4/1/1.
- Value: On.

The telegram will be received by every device on the network, and those
programmed to listen on this group address can now act accordingly.

If a device needs to know the state of Switch A, it must send a
GroupValueRead telegram to the network. Let's say the microcontroller in Lamp
A rebooted and lost its state. It will send a telegram like this:

- Service: GroupValueRead.
- Sender: 2.4.1.
- Destination: 4/1/1.
- Value: N/A.

Again, all devices will receive the message. Since Switch A owns this group
address, it is responsible for responding. It will do so by sending a
GroupValueResponse:

- Service: GroupValueResponse.
- Sender: 3.4.1.
- Destination: 4/1/1.
- Value: On.

As mentioned, a group address can be thought of as a variable, and as such it
also has a type associated with it. This is called the datapoint type (DPTs
for short). All DPTs have a name and an ID (e.g. `DPT_TimePeriodMsec` has ID
`7.002`). DPTs describe a few different properties:

- The basic type (e.g. boolean, integer, float, character, etc. for simple
  types - can also be multi-valued for fields like datetimes).
- The valid range of values (e.g. `0 ms ... 65535 ms`).
- The unit (e.g. `ms`).
- The resolution (e.g. `1 ms`).
- How the value must be encoded.

The value of all GroupValueWrites and GroupValueResponses adressed at one
group address will be encoded with the same DPT. As the datapoint type is not
specified in the telegram, the correct decoding scheme for a telegram can
only be discovered by mapping the group address to a datapoint type.

## Back to KNXnet/IP

As mentioned, any device connected to the bus will receive all messages sent
on it. There are in fact multiple phyiscal mediums that can be used to create
a KNX bus. The bus is usually based on twisted pair cabling connecting all
the different devices, but it can also be augmented with powerline cabling,
medium-range radio waves, and IP networks. KNXnet/IP is the protocol used to
extend the KNX bus across an IP network.

To augment the KNX bus with an IP network, a KNX IP interface is connected to
the bus. This IP interface acts as a KNXnet/IP server. The server will listen
for connections via. UDP (optionally also TCP).

To communicate with the devices on the KNX bus, a client must establish a
connection to the IP interface. A client can request one of three types of
connections:

- Management, used for device configuration and management.
- Tunnelling, used by supervisory systems to communicate with the KNX network.
- Routing, used for relaying telegrams between two networks.

For all connection types, two communication channels are used - core and
data. The core channel is used for establishing the connection between client
and server, and maintaining it through regular heartbeats. This is common for
all connection types. The communication on the data channel is unique to each
connection type, and is used to transport messages between the client and the
KNX bus.
