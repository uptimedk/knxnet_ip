# KNXnetIP 
[![Build Status](https://circleci.com/gh/uptimedk/knxnet_ip.svg?style=shield)](https://circleci.com/gh/uptimedk/knxnet_ip)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/uptimedk/knxnet_ip/blob/master/LICENSE)
[![Hex version](https://img.shields.io/hexpm/v/knxnet_ip.svg "Hex version")](https://hex.pm/packages/knxnet_ip)
[![Coverage Status](https://codecov.io/gh/uptimedk/knxnet_ip/branch/master/graph/badge.svg)](https://codecov.io/gh/uptimedk/knxnet_ip)

KNXnetIP is an Elixir library for communicating with devices on a KNX network
using KNXnet/IP. The library enables its users to build applications which
integrate with devices on a KNX network. To achieve this, the library
provides:

- Encoding and decoding of KNXnet/IP frames.
- Encoding and decoding of KNX telegrams, to control the state of the KNX
  network (GroupValueRead and GroupValueWrite).
- Encoding and decoding of all common datatypes.
- A behaviour for KNXnet/IP tunnelling clients.

KNXnetIP was specifically written to provide a tunnelling client which is:

- Robust. The tunnelling connection must be maintained even on very lossy IP
  networks, and it must automatically reconnect when the connection drops.
- Isolated. One application must be able to have multiple concurrent
  tunnelling connections to different KNX networks.

If you're new to KNX, please check the [KNXnet/IP introduction][] page for an
overview of the most important parts.

[KNXnet/IP introduction]: https://hexdocs.pm/knxnet_ip/introduction.html

To create a KNXnet/IP tunnelling client, you'll need to implement a callback
module for the `KNXnetIP.Tunnel` behaviour. See the documentation for
`KNXnetIP.Tunnel` for a thorough example and in-depth descriptions.

## Maturity

The library has been used in production as part of the smart city energy lab
[EnergyLab Nordhavn](http://energylabnordhavn.weebly.com/) since August 2017.
It sends and receives telegrams to and from more than 30 apartments - and
every month it processes more than 70 million telegrams.

We are quite happy with its performance and fault tolerance, but parts of the
API are less than ideal. Fixing this will require breaking the API, so expect
changes.

The library implements encoding and decoding of the following data structures:

- KNXnet/IP services:
  - CONNECT_REQUEST
  - CONNECT_RESPONSE
  - DISCONNECT_REQUEST
  - DISCONNECT_RESPONSE
  - CONNECTIONSTATE_REQUEST
  - CONNECTIONSTATE_RESPONSE
  - TUNNELING_REQUEST
  - TUNNELING_ACK
- Telegrams (cEMI encoded):
  - L_Data.ind
  - L_Data.con
  - L_Data.req
- Application services:
  - A_GroupValue_Read
  - A_GroupValue_Response
  - A_GroupValue_Write
- Datapoint types 1-16, 18 and 20 (main group)

The KNXnetIP.Tunnel behaviour sports the following features:

- Connect to a KNXnet/IP tunnelling server via. UDP.
- Retry failed connection attempts using a backoff interval.
- Perform heartbeating according to the specification, and reconnect if the
  heartbeat fails due to timeouts or other errors.
- Disconnect and reconnect if the client receives a DISCONNECT_REQUEST from
  the tunnelling server.
- Handle duplicate TUNNELLING_REQUESTS from tunnelling server according to
  the specification.
- Send TUNNELLING_REQUESTS to the server, and resend TUNNELLING_REQUEST if no
  TUNNELLING_ACK is received.
- Disconnect and reconnect if TUNNELING_ACK is not received or signals an error.

## License

KNXnetIP is released under the MIT License. See the LICENSE file for further details.
