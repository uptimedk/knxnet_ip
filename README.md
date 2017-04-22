# KNXnetIP

KNXnetIP is an Elixir library for communicating with devices on a KNX network using KNXnet/IP. The library provides a set of functions for encoding and decoding KNX and KNXnet/IP frames, as well as encoding and decoding values of shared variables when given a datapoint type. It also packs KNXnetIP.Tunnel, a behaviour module for connecting to a KNX IP interface, and for sending and receiving KNX frames to and from the KNX network.

There is no intent to implement the full KNX specification. KNXnetIP has been written to provide the parts necessary to build applications which integrate with devices on a KNX network. It was specifically written to maintain connections to the KNX IP interface in spite of very lossy IP networks. The primary use case is to listen for group writes on the KNX network, and perform group reads and group writes.

**Note**: The library is under heavy development. Not all of the advertised features are implemented yet. Check below to see the list of implemented features.

## Examples

Defining a simple callback module for the KNXnetIP.Tunnel behaviour:

```elixir
defmodule MyApp.Tunnel do
  use KNXnetIP.Tunnel

  def start_link(parent_pid, knxnet_ip_opts, gen_server_opts) do
    KNXnetIP.Tunnel.start_link(__MODULE__, parent_pid, knxnet_ip_opts, gen_server_opts)
  end

  def send(tunnel, msg) do
    KNXnetIP.Tunnel.send(tunnel, msg)
  end

  def init(parent_pid) do
    {:ok, nil}
  end

  def on_data(%KNXnetIP.Tunnelling.TunnellingRequest{} = msg, parent_pid) do
    IO.puts("Tunnel got message: #{inspect(msg)}")
    Kernel.send(parent_pid, msg)
    {:noreply, parent_pid}
  end
end
```

Using the above callback module:

```elixir
>>> {:ok, tunnel} = MyApp.Tunnel.start_link(knxnet_ip_opts, gen_server_opts)
>>> group_read = %CEMI.Frame{type: :request, source: "1.1.1", destination: "0/0/7", service: :group_read}
>>> {:ok, frame} = %CEMI.encode(group_read)
>>> msg = %KNXnetIP.Tunnelling.TunnellingRequest{cemi_frame: frame}
Tunnel got message: %KNXnetIP.Tunnelling.TunnellingRequest{}
>>> receive do
..>   msg ->
..>     cemi = %KNXnetIP.CEMI.decode(msg.cemi_frame)
..>     IO.puts("CEMI content is: #{inspect(cemi)")
..>     # Assuming that the datapoint type is a 32 bit float (e.g. 14.004 - main group 14)
..>     value = KNXnetIP.DatapointTypes.decode(cemi.value, 14)
..>     IO.puts("Value is: #{value}")
..> end
```

## Features

In order to fulfill the requirements of a KNXnet/IP tunnelling client, the library will implement encoding and decoding of the following data structures:

- KNXnet/IP services:
  - [x] CONNECT_REQUEST
  - [x] CONNECT_RESPONSE
  - [x] DISCONNECT_REQUEST
  - [x] DISCONNECT_RESPONSE
  - [x] CONNECTIONSTATE_REQUEST
  - [x] CONNECTIONSTATE_RESPONSE
  - [x] TUNNELING_REQUEST
  - [x] TUNNELING_ACK
- cEMI messages
  - [x] L_Data.ind
  - [x] L_Data.con
  - [ ] L_Data.req
- Application services:
  - [x] A_GroupValue_Read
  - [x] A_GroupValue_Response
  - [ ] A_GroupValue_Write
- Datapoint types (main group):
  - [ ] 1
  - [ ] 2
  - [ ] 3
  - [ ] 4
  - [ ] 5
  - [ ] 6
  - [ ] 7
  - [ ] 8
  - [ ] 9
  - [ ] 10
  - [ ] 11
  - [ ] 12
  - [ ] 13
  - [ ] 14
  - [ ] 15
  - [ ] 16

The KNXnetIP.Tunnel behaviour sports the following features:

- [ ] Connect to a KNX IP interface
- [ ] Retry failed connection attempts using a backoff interval
- [ ] Perform heartbeating according to the specification
- [ ] Reconnect if the heartbeat fails due to timeouts or other errors
- [ ] Disconnect and reconnect to KNX IP interface if it receives a DISCONNECT_REQUEST
- [ ] Handle duplicate TUNNELLING_REQUESTS from server according to the specification
- [ ] Send TUNNELLING_REQUESTS to the server
- [ ] Resend TUNNELLING_REQUEST if no TUNNELLING_ACK is received
- [ ] Disconnect and reconnect if TUNNELING_ACK is not received or signals an error

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `knxnet_ip` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:knxnet_ip, "~> 0.1.0"}]
    end
    ```

  2. Ensure `knxnet_ip` is started before your application:

    ```elixir
    def application do
      [applications: [:knxnet_ip]]
    end
    ```
