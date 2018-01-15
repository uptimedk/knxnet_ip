# KNXnetIP

KNXnetIP is an Elixir library for communicating with devices on a KNX network using KNXnet/IP. The library provides a set of functions for encoding and decoding KNX and KNXnet/IP frames, as well as encoding and decoding datapoints when given a datapoint type. It also packs KNXnetIP.Tunnel, a behaviour module for connecting to a KNX IP interface, and for sending and receiving KNX frames to and from the KNX network.

There is no intent to implement the full KNX specification. KNXnetIP has been written to provide the parts necessary to build applications which integrate with devices on a KNX network. It was specifically written to maintain connections to the KNX IP interface in spite of very lossy IP networks. The primary use case is to listen for group writes on the KNX network, and perform group reads and group writes.

**Note**: The library is under heavy development. Not all of the advertised features are implemented yet. Check below to see the list of implemented features.

## Examples

Define a simple callback module for the KNXnetIP.Tunnel behaviour:

```elixir
defmodule MyApp.Tunnel do
  @behaviour KNXnetIP.Tunnel

  def start_link(knxnet_ip_opts, gen_server_opts) do
    KNXnetIP.Tunnel.start_link(__MODULE__, :nil, knxnet_ip_opts, gen_server_opts)
  end

  def init(:nil) do
    {:ok, :nil}
  end

  def on_telegram(%KNXnetIP.Telegram{} = telegram, :nil) do
    IO.puts("Tunnel got message: #{inspect(telegram)}")
    {:ok, parent_pid}
  end
end
```

## Features

In order to fulfill the requirements of a KNXnet/IP tunnelling client, the library will implement encoding and decoding of the following data structures:

- KNXnet/IP services:
  - [ ] SEARCH_REQUEST
  - [ ] SEARCH_RESPONSE
  - [ ] DESCRIPTION_REQUEST
  - [ ] DESCRIPTION_RESPONSE
  - [x] CONNECT_REQUEST
  - [x] CONNECT_RESPONSE
  - [x] DISCONNECT_REQUEST
  - [x] DISCONNECT_RESPONSE
  - [x] CONNECTIONSTATE_REQUEST
  - [x] CONNECTIONSTATE_RESPONSE
  - [x] TUNNELING_REQUEST
  - [x] TUNNELING_ACK
- Telegrams
  - [x] L_Data.ind
  - [x] L_Data.con
  - [ ] L_Data.req
- Application services:
  - [x] A_GroupValue_Read
  - [x] A_GroupValue_Response
  - [x] A_GroupValue_Write
- Datapoint types (main group):
  - [x] 1
  - [x] 2
  - [x] 3
  - [x] 4
  - [x] 5
  - [x] 6
  - [x] 7
  - [x] 8
  - [x] 9
  - [x] 10
  - [x] 11
  - [x] 12
  - [x] 13
  - [x] 14
  - [x] 15
  - [x] 16
  - [x] 18
  - [x] 20

The KNXnetIP.Tunnel behaviour sports the following features:

- [x] Connect to a KNX IP interface
- [x] Retry failed connection attempts using a backoff interval
- [x] Perform heartbeating according to the specification
- [x] Reconnect if the heartbeat fails due to timeouts or other errors
- [x] Disconnect and reconnect to KNX IP interface if it receives a DISCONNECT_REQUEST
- [x] Handle duplicate TUNNELLING_REQUESTS from server according to the specification
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
