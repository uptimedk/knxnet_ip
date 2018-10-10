defmodule KNXnetIP.TunnelTest do
  use ExUnit.Case, async: true

  alias KNXnetIP.Frame.{Core, Tunnelling}
  alias KNXnetIP.{Telegram, Tunnel}
  alias KNXnetIP.Support.TunnelMock

  import Mox

  setup [:verify_on_exit!]

  describe "init/1" do
    @tag :init
    test "if mod.init/1 sucess will return connect tuple" do
      Mox.expect(TunnelMock, :init, fn [] -> {:ok, :test_state} end)

      assert {:connect, :init, %{mod_state: :test_state}} = Tunnel.init({TunnelMock, [], []})
    end

    @tag :init
    test "if mod.init/1 fails it will return stop" do
      Mox.expect(TunnelMock, :init, fn nil -> {:stop, {:error, :expected}} end)

      assert {:stop, {:error, :expected}} = Tunnel.init({TunnelMock, nil, []})
    end
  end

  describe "connect/2" do
    setup [:server_sockets, :init]

    @tag :connect
    test "opens control and data socket", context do
      {:ok, state} = Tunnel.connect(:init, context.state)
      assert is_port(state.control_socket)
      assert is_integer(state.control_port)
      assert is_port(state.data_socket)
      assert is_integer(state.data_port)
    end

    @tag :connect
    test "sends a connect request", context do
      {:ok, _state} = Tunnel.connect(:init, context.state)
      assert {:ok, {_, _, connect_frame}} = :gen_udp.recv(context.control_socket, 0, 1_000)
      assert {:ok, %Core.ConnectRequest{}} = KNXnetIP.Frame.decode(connect_frame)
    end

    @tag :connect
    test "starts connect response timer", context do
      {:ok, state} = Tunnel.connect(:init, context.state)
      assert is_reference(state.connect_response_timer.timer)
      assert is_reference(state.connect_response_timer.ref)
    end
  end

  describe "disconnect/2" do
    setup [:server_sockets, :init, :connect]

    @tag :disconnect
    test "returns stop tuple on normal shutdown", context do
      assert {:stop, :normal, _state} = Tunnel.disconnect({:stop, :normal}, context.state)
    end

    @tag :disconnect
    test "returns connect tuple on error", context do
      assert {:connect, :reconnect, _state} =
               Tunnel.disconnect({:error, :expected}, context.state)
    end

    @tag :disconnect
    test "stops all timers", context do
      ref = make_ref()

      state = %{
        context.state
        | heartbeat_timer: %{timer: ref, ref: ref},
          connectionstate_response_timer: %{timer: ref, ref: ref},
          connect_response_timer: %{timer: ref, ref: ref},
          disconnect_response_timer: %{timer: ref, ref: ref},
          tunnelling_ack_timer: %{timer: ref, ref: ref}
      }

      {:stop, :normal, state} = Tunnel.disconnect({:stop, :normal}, state)

      refute is_reference(state.heartbeat_timer.timer)
      refute is_reference(state.heartbeat_timer.ref)
      refute is_reference(state.connectionstate_response_timer.timer)
      refute is_reference(state.connectionstate_response_timer.ref)
      refute is_reference(state.connect_response_timer.timer)
      refute is_reference(state.connect_response_timer.ref)
      refute is_reference(state.disconnect_response_timer.timer)
      refute is_reference(state.disconnect_response_timer.ref)
      refute is_reference(state.tunnelling_ack_timer.timer)
      refute is_reference(state.tunnelling_ack_timer.ref)
    end

    @tag :disconnect
    test "sets communication_channel_id to nil", context do
      {:stop, :normal, state} = Tunnel.disconnect({:stop, :normal}, context.state)
      assert is_nil(state.communication_channel_id)
    end

    @tag :disconnect
    test "closes sockets", context do
      {:stop, :normal, state} = Tunnel.disconnect({:stop, :normal}, context.state)
      assert {:error, :einval} = :inet.port(state.control_socket)
      assert {:error, :einval} = :inet.port(state.data_socket)
    end
  end

  describe "handle_info/2" do
    test "ignores timeouts with stale references" do
      state = %{connect_response_timer: %{timer: make_ref(), ref: make_ref()}}
      timeout = {:timeout, :connect_response_timer, make_ref()}
      assert {:noreply, _state} = Tunnel.handle_info(timeout, state)
    end
  end

  describe "handle_cast/2" do
    setup [:server_sockets, :init, :connect]

    test "invokes handle_cast of callback module", context do
      Mox.expect(TunnelMock, :handle_cast, fn _msg, _state -> {:noreply, :handle_cast_invoked} end)

      assert {:noreply, %{mod_state: :handle_cast_invoked}} =
               Tunnel.handle_cast(nil, context.state)
    end
  end

  describe "handle_timeout/2 connect response" do
    @tag :connect_response_timeout
    test "returns connect tuple for reconnect" do
      ref = make_ref()
      state = %{connect_response_timer: %{timer: make_ref(), ref: ref}}
      timeout = {:timeout, :connect_response_timer, ref}
      assert {:connect, :retry, _state} = Tunnel.handle_info(timeout, state)
    end
  end

  describe "handle_timeout/2 heartbeat" do
    setup [:server_sockets, :init, :connect]

    @tag :heartbeat_timeout
    test "starts connectionstate_response_timer on heartbeat timeout", context do
      timeout = {:timeout, :heartbeat_timer, context.state.heartbeat_timer.ref}
      assert {:noreply, state} = Tunnel.handle_info(timeout, context.state)
      assert is_reference(state.connectionstate_response_timer.timer)
      assert is_reference(state.connectionstate_response_timer.ref)
    end

    @tag :heartbeat_timeout
    test "sends a connectionstate request", context do
      timeout = {:timeout, :heartbeat_timer, context.state.heartbeat_timer.ref}
      {:noreply, _state} = Tunnel.handle_info(timeout, context.state)

      assert {:ok, {_, _, connectionstate_request_frame}} =
               :gen_udp.recv(context.control_socket, 0, 1_000)

      assert {:ok, %Core.ConnectionstateRequest{}} =
               KNXnetIP.Frame.decode(connectionstate_request_frame)
    end

    @tag :heartbeat_timeout
    test "sets the connectionstate attempts counter to 1", context do
      timeout = {:timeout, :heartbeat_timer, context.state.heartbeat_timer.ref}
      {:noreply, state} = Tunnel.handle_info(timeout, context.state)
      assert 1 == state.connectionstate_attempts
    end
  end

  describe "handle_timeout/2 connectionstate response" do
    setup [:server_sockets, :init, :connect]

    @tag :connectionstate_response_timeout
    test "increments connectionstate attempts counter on connectionstate response timeout",
         context do
      ref = make_ref()
      timeout = {:timeout, :connectionstate_response_timer, ref}

      state = %{
        context.state
        | connectionstate_response_timer: %{timer: ref, ref: ref, timeout: 10_000}
      }

      {:noreply, state} = Tunnel.handle_info(timeout, state)
      assert state.connectionstate_attempts == context.state.connectionstate_attempts + 1
    end

    @tag :connectionstate_response_timeout
    test "sends new connectionstate request when less than 3 connectionstate attempts", context do
      ref = make_ref()
      timeout = {:timeout, :connectionstate_response_timer, ref}

      states =
        Enum.map(0..2, fn attempts ->
          %{
            context.state
            | connectionstate_response_timer: %{timer: ref, ref: ref, timeout: 10_000},
              connectionstate_attempts: attempts
          }
        end)

      Enum.each(states, fn state ->
        {:noreply, _state} = Tunnel.handle_info(timeout, state)

        assert {:ok, {_, _, connectionstate_request_frame}} =
                 :gen_udp.recv(context.control_socket, 0, 1_000)

        assert {:ok, %Core.ConnectionstateRequest{}} =
                 KNXnetIP.Frame.decode(connectionstate_request_frame)
      end)
    end

    @tag :connectionstate_response_timeout
    test "starts a new timer when less than 3 connectionstate attempts", context do
      ref = make_ref()
      timeout = {:timeout, :connectionstate_response_timer, ref}

      states =
        Enum.map(0..2, fn attempts ->
          %{
            context.state
            | connectionstate_response_timer: %{timer: ref, ref: ref, timeout: 10_000},
              connectionstate_attempts: attempts
          }
        end)

      Enum.each(states, fn state ->
        {:noreply, state} = Tunnel.handle_info(timeout, state)
        assert is_reference(state.connectionstate_response_timer.ref)
        assert state.connectionstate_response_timer.ref != ref
      end)
    end

    @tag :connectionstate_response_timeout
    test "sends disconnect request when 3 connectionstate attempts", context do
      ref = make_ref()
      timeout = {:timeout, :connectionstate_response_timer, ref}

      state = %{
        context.state
        | connectionstate_response_timer: %{timer: ref, ref: ref, timeout: 10_000},
          connectionstate_attempts: 3
      }

      {:noreply, _state} = Tunnel.handle_info(timeout, state)

      assert {:ok, {_, _, disconnect_request_frame}} =
               :gen_udp.recv(context.control_socket, 0, 1_000)

      assert {:ok, %Core.DisconnectRequest{}} = KNXnetIP.Frame.decode(disconnect_request_frame)
    end

    @tag :connectionstate_response_timeout
    test "sets communication_channel_id and disconnect info when 3 connectionstate attempts",
         context do
      ref = make_ref()
      timeout = {:timeout, :connectionstate_response_timer, ref}

      state = %{
        context.state
        | connectionstate_response_timer: %{timer: ref, ref: ref, timeout: 10_000},
          connectionstate_attempts: 3
      }

      {:noreply, state} = Tunnel.handle_info(timeout, state)
      assert state.communication_channel_id == nil
      assert state.disconnect_info == {:error, :no_heartbeat}
    end
  end

  describe "handle_timeout/2 disconnect response" do
    setup [:server_sockets, :init, :connect]

    @tag :disconnect_response_timeout
    test "returns a disconnect tuple", context do
      ref = make_ref()
      timeout = {:timeout, :disconnect_response_timer, ref}

      state = %{
        context.state
        | disconnect_response_timer: %{timer: ref, ref: ref, timeout: 10_000},
          disconnect_info: {:error, :disconnect_response_timeout}
      }

      assert {:disconnect, {:error, :disconnect_response_timeout}, _state} =
               Tunnel.handle_info(timeout, state)
    end
  end

  describe "handle_timeout/2 tunnelling ack" do
    setup [:server_sockets, :init, :connect, :transmit]

    @tag :tunnelling_ack_timeout
    test "increments tunnelling timeouts on first timeout", context do
      Mox.expect(TunnelMock, :transmit_ack, 0, fn _, _, _ -> :ok end)

      timeout = {:timeout, :tunnelling_ack_timer, context.state.tunnelling_ack_timer.ref}

      {:noreply, state} = Tunnel.handle_info(timeout, context.state)
      assert state.tunnelling_timeouts == context.state.tunnelling_timeouts + 1
    end

    @tag :tunnelling_ack_timeout
    test "resends tunnelling request on first timeout", context do
      Mox.expect(TunnelMock, :transmit_ack, 0, fn _, _, _ -> :ok end)

      timeout = {:timeout, :tunnelling_ack_timer, context.state.tunnelling_ack_timer.ref}

      {:noreply, _state} = Tunnel.handle_info(timeout, context.state)

      assert {:ok, {_, _, tunnelling_request_frame}} =
               :gen_udp.recv(context.data_socket, 0, 1_000)

      assert {:ok, %Tunnelling.TunnellingRequest{}} =
               KNXnetIP.Frame.decode(tunnelling_request_frame)
    end

    @tag :tunnelling_ack_timeout
    test "invokes transmit_ack callback with timeout status on second timeout", context do
      Mox.expect(TunnelMock, :transmit_ack, fn ref, status, _state ->
        assert status == :timeout
        assert {^ref, _} = context.state.tunnelling_request
        {:ok, :got_transmit_ack_timeout}
      end)

      state = %{context.state | tunnelling_timeouts: 1}
      timeout = {:timeout, :tunnelling_ack_timer, context.state.tunnelling_ack_timer.ref}

      {:noreply, state} = Tunnel.handle_info(timeout, state)

      assert state.mod_state == :got_transmit_ack_timeout
    end

    @tag :tunnelling_ack_timeout
    test "repeats tunnelling request and sends a disconnect request on second timeout", context do
      Mox.expect(TunnelMock, :transmit_ack, fn _, _, _ -> {:ok, :got_transmit_ack_callback} end)

      timeout = {:timeout, :tunnelling_ack_timer, context.state.tunnelling_ack_timer.ref}

      state = %{context.state | tunnelling_timeouts: 1}

      {:noreply, state} = Tunnel.handle_info(timeout, state)

      assert {:ok, {_, _, tunnelling_request_frame}} =
               :gen_udp.recv(context.data_socket, 0, 1_000)

      assert {:ok, %Tunnelling.TunnellingRequest{}} =
               KNXnetIP.Frame.decode(tunnelling_request_frame)

      assert {:ok, {_, _, disconnect_request_frame}} =
               :gen_udp.recv(context.control_socket, 0, 1_000)

      assert {:ok, %Core.DisconnectRequest{}} = KNXnetIP.Frame.decode(disconnect_request_frame)

      assert state.disconnect_info == {:error, :no_tunnelling_ack}
    end
  end

  describe "on_message/2 not connected" do
    setup [:server_sockets, :init]

    @tag :not_connected
    test "does not respond to messages other than connect and disconnect response when not connected",
         context do
      connectionstate_response = connectionstate_response()
      disconnect_request = disconnect_request()
      tunnelling_request = tunnelling_request()
      tunnelling_ack = tunnelling_ack()

      assert {:noreply, _state} = Tunnel.on_message(connectionstate_response, context.state)
      assert {:noreply, _state} = Tunnel.on_message(disconnect_request, context.state)
      assert {:noreply, _state} = Tunnel.on_message(tunnelling_request, context.state)
      assert {:noreply, _state} = Tunnel.on_message(tunnelling_ack, context.state)

      assert {:error, :timeout} = :gen_udp.recv(context.control_socket, 0, 100)
      assert {:error, :timeout} = :gen_udp.recv(context.data_socket, 0, 100)
    end
  end

  describe "on_message/2 wrong communication_channel_id" do
    setup [:server_sockets, :init, :connect]

    @tag :wrong_communication_channel_id
    test "does not respond when communication_channel_id in message and state are unequal",
         context do
      tunnelling_request = %{
        tunnelling_request()
        | communication_channel_id: context.state.communication_channel_id + Enum.random(1..10)
      }

      {:noreply, _state} = Tunnel.on_message(tunnelling_request, context.state)

      assert {:error, :timeout} = :gen_udp.recv(context.control_socket, 0, 100)
      assert {:error, :timeout} = :gen_udp.recv(context.data_socket, 0, 100)
    end
  end

  describe "on_message/2 connect response when status e_no_error" do
    setup [:server_sockets, :init]

    @tag :connect_response
    test "stops connect response timer", context do
      {:ok, data_port} = :inet.port(context.data_socket)
      connect_response = connect_response(data_port)

      {:ok, state} = Tunnel.connect(:init, context.state)
      {:noreply, state} = Tunnel.on_message(connect_response, state)

      refute is_reference(state.connect_response_timer.timer)
      refute is_reference(state.connect_response_timer.ref)
    end

    @tag :connect_response
    test "starts heartbeat timer", context do
      {:ok, data_port} = :inet.port(context.data_socket)
      connect_response = connect_response(data_port)

      {:ok, state} = Tunnel.connect(:init, context.state)
      {:noreply, state} = Tunnel.on_message(connect_response, state)

      assert is_reference(state.heartbeat_timer.timer)
      assert is_reference(state.heartbeat_timer.ref)
    end

    @tag :connect_response
    test "sets communication_channel_id", context do
      {:ok, data_port} = :inet.port(context.data_socket)
      connect_response = connect_response(data_port)

      {:ok, state} = Tunnel.connect(:init, context.state)
      {:noreply, state} = Tunnel.on_message(connect_response, state)

      assert is_integer(state.communication_channel_id)
    end
  end

  describe "on_message/2 connect response when status indicates error" do
    setup [:server_sockets, :init]

    @tag :connect_response
    test "stops connect response timer", context do
      {:ok, data_port} = :inet.port(context.data_socket)
      connect_response = connect_response(data_port, :e_host_protocol_type)

      {:ok, state} = Tunnel.connect(:init, context.state)
      {:disconnect, _timeout, state} = Tunnel.on_message(connect_response, state)

      refute is_reference(state.connect_response_timer.timer)
      refute is_reference(state.connect_response_timer.ref)
    end

    @tag :connect_response
    test "returns disconnect tuple", context do
      {:ok, data_port} = :inet.port(context.data_socket)
      connect_response = connect_response(data_port, :e_host_protocol_type)

      {:ok, state} = Tunnel.connect(:init, context.state)

      assert {:disconnect, {:error, :connect_response_error}, _state} =
               Tunnel.on_message(connect_response, state)
    end
  end

  describe "on_message/2 connectionstate response when status e_no_error" do
    setup [:server_sockets, :init, :connect]

    @tag :connectionstate_response
    test "resets connectionstate attempts counter", context do
      connectionstate_response = connectionstate_response()
      state = %{context.state | connectionstate_attempts: 2}

      {:noreply, state} = Tunnel.on_message(connectionstate_response, state)
      assert state.connectionstate_attempts == 0
    end

    @tag :connectionstate_response
    test "starts heartbeat timer", context do
      connectionstate_response = connectionstate_response()

      {:noreply, state} = Tunnel.on_message(connectionstate_response, context.state)

      assert is_reference(state.heartbeat_timer.timer)
      assert is_reference(state.heartbeat_timer.ref)
      assert state.heartbeat_timer.ref != context.state.heartbeat_timer.ref
    end
  end

  describe "on_message/2 connectionstate response when status indicates error" do
    setup [:server_sockets, :init, :connect]

    @tag :connectionstate_response
    test "increments connectionstate attempts counter", context do
      connectionstate_response = connectionstate_response(:e_host_protocol_type)

      {:noreply, state} = Tunnel.on_message(connectionstate_response, context.state)
      assert state.connectionstate_attempts == context.state.connectionstate_attempts + 1
    end

    @tag :connectionstate_response
    test "sends new connectionstate request when less than 3 connectionstate attempts", context do
      connectionstate_response = connectionstate_response(:e_host_protocol_type)

      states =
        Enum.map(0..2, fn attempts ->
          %{context.state | connectionstate_attempts: attempts}
        end)

      Enum.each(states, fn state ->
        {:noreply, _state} = Tunnel.on_message(connectionstate_response, state)

        assert {:ok, {_, _, connectionstate_request_frame}} =
                 :gen_udp.recv(context.control_socket, 0, 1_000)

        assert {:ok, %Core.ConnectionstateRequest{}} =
                 KNXnetIP.Frame.decode(connectionstate_request_frame)
      end)
    end

    @tag :connectionstate_response
    test "starts a new timer when less than 3 connectionstate attempts", context do
      connectionstate_response = connectionstate_response(:e_host_protocol_type)

      states =
        Enum.map(0..2, fn attempts ->
          %{context.state | connectionstate_attempts: attempts}
        end)

      Enum.each(states, fn state ->
        {:noreply, state} = Tunnel.on_message(connectionstate_response, state)
        assert is_reference(state.connectionstate_response_timer.ref)

        assert state.connectionstate_response_timer.ref !=
                 context.state.connectionstate_response_timer.ref
      end)
    end

    @tag :connectionstate_response
    test "sends disconnect request when 3 connectionstate attempts", context do
      connectionstate_response = connectionstate_response(:e_host_protocol_type)
      state = %{context.state | connectionstate_attempts: 3}

      {:noreply, _state} = Tunnel.on_message(connectionstate_response, state)

      assert {:ok, {_, _, disconnect_request_frame}} =
               :gen_udp.recv(context.control_socket, 0, 1_000)

      assert {:ok, %Core.DisconnectRequest{}} = KNXnetIP.Frame.decode(disconnect_request_frame)
    end

    @tag :connectionstate_response
    test "sets communication_channel_id and disconnect info when 3 connectionstate attempts",
         context do
      connectionstate_response = connectionstate_response(:e_host_protocol_type)
      state = %{context.state | connectionstate_attempts: 3}

      {:noreply, state} = Tunnel.on_message(connectionstate_response, state)
      assert state.communication_channel_id == nil
      assert state.disconnect_info == {:error, :no_heartbeat}
    end
  end

  describe "on_message/2 disconnect request" do
    setup [:server_sockets, :init, :connect]

    @tag :disconnect_request
    test "returns disconnect tuple with disconnect requested info", context do
      disconnect_request = disconnect_request()

      assert {:disconnect, {:error, :disconnect_requested}, _state} =
               Tunnel.on_message(disconnect_request, context.state)
    end

    @tag :disconnect_request
    test "stops all timers", context do
      ref = make_ref()

      state = %{
        context.state
        | heartbeat_timer: %{timer: ref, ref: ref},
          connectionstate_response_timer: %{timer: ref, ref: ref},
          connect_response_timer: %{timer: ref, ref: ref},
          disconnect_response_timer: %{timer: ref, ref: ref},
          tunnelling_ack_timer: %{timer: ref, ref: ref}
      }

      disconnect_request = disconnect_request()

      {:disconnect, _, state} = Tunnel.on_message(disconnect_request, state)

      refute is_reference(state.heartbeat_timer.timer)
      refute is_reference(state.heartbeat_timer.ref)
      refute is_reference(state.connectionstate_response_timer.timer)
      refute is_reference(state.connectionstate_response_timer.ref)
      refute is_reference(state.connect_response_timer.timer)
      refute is_reference(state.connect_response_timer.ref)
      refute is_reference(state.disconnect_response_timer.timer)
      refute is_reference(state.disconnect_response_timer.ref)
      refute is_reference(state.tunnelling_ack_timer.timer)
      refute is_reference(state.tunnelling_ack_timer.ref)
    end

    @tag :disconnect_request
    test "sends a disconnect response", context do
      disconnect_request = disconnect_request()
      {:disconnect, _, _state} = Tunnel.on_message(disconnect_request, context.state)

      assert {:ok, {_, _, disconnect_response_frame}} =
               :gen_udp.recv(context.control_socket, 0, 1_000)

      assert {:ok, %Core.DisconnectResponse{}} = KNXnetIP.Frame.decode(disconnect_response_frame)
    end

    @tag :disconnect_request
    test "sets communication channel id to nil", context do
      disconnect_request = disconnect_request()
      {:disconnect, _, state} = Tunnel.on_message(disconnect_request, context.state)

      assert is_nil(state.communication_channel_id)
    end
  end

  describe "on_message/2 disconnect response" do
    setup [:server_sockets, :init, :connect]

    @tag :disconnect_response
    test "is ignored if communication channel id is not nil", context do
      disconnect_response = disconnect_response()

      assert {:noreply, state} = Tunnel.on_message(disconnect_response, context.state)
      assert state == context.state
    end

    @tag :disconnect_response
    test "returns disconnect tuple with disconnect info from state", context do
      state = %{
        context.state
        | communication_channel_id: nil,
          disconnect_info: {:error, :testing}
      }

      disconnect_response = disconnect_response()

      assert {:disconnect, {:error, :testing}, _state} =
               Tunnel.on_message(disconnect_response, state)
    end

    @tag :disconnect_response
    test "stops disconnect response timer", context do
      state = %{
        context.state
        | communication_channel_id: nil,
          disconnect_info: {:error, :testing}
      }

      disconnect_response = disconnect_response()

      {:disconnect, _, state} = Tunnel.on_message(disconnect_response, state)

      refute is_reference(state.disconnect_response_timer.timer)
      refute is_reference(state.disconnect_response_timer.ref)
    end
  end

  describe "on_message/2 tunnelling request" do
    setup [:server_sockets, :init, :connect]

    @tag :tunnelling_request
    test "increments remote sequence conter when tunnelling request is next in sequence",
         context do
      Mox.expect(TunnelMock, :on_telegram, fn _msg, _state -> {:ok, :new_mod_state} end)

      tunnelling_request = tunnelling_request()
      {:noreply, state} = Tunnel.on_message(tunnelling_request, context.state)

      assert state.remote_sequence_counter == tunnelling_request.sequence_counter + 1
      assert state.remote_sequence_counter == context.state.remote_sequence_counter + 1
    end

    @tag :tunnelling_request
    test "sends ack when tunnelling request is next in sequence", context do
      Mox.expect(TunnelMock, :on_telegram, fn _msg, _state -> {:ok, :new_mod_state} end)

      tunnelling_request = tunnelling_request()
      {:noreply, _state} = Tunnel.on_message(tunnelling_request, context.state)

      assert {:ok, {_, _, tunnelling_ack_frame}} = :gen_udp.recv(context.data_socket, 0, 1_000)
      assert {:ok, %Tunnelling.TunnellingAck{}} = KNXnetIP.Frame.decode(tunnelling_ack_frame)
    end

    @tag :tunnelling_request
    test "sends ack when tunnelling request is equal to sequence", context do
      Mox.expect(TunnelMock, :on_telegram, fn _msg, _state -> {:ok, :new_mod_state} end)

      tunnelling_request = tunnelling_request(0)
      {:noreply, _state} = Tunnel.on_message(tunnelling_request, context.state)

      assert {:ok, {_, _, tunnelling_ack_frame}} = :gen_udp.recv(context.data_socket, 0, 1_000)
      assert {:ok, %Tunnelling.TunnellingAck{}} = KNXnetIP.Frame.decode(tunnelling_ack_frame)
    end

    @tag :tunnelling_request
    test "does not send ack when tunnelling request is out of sequence", context do
      state = %{context.state | remote_sequence_counter: 10}

      {:noreply, _state} = Tunnel.on_message(tunnelling_request(8), state)
      {:noreply, _state} = Tunnel.on_message(tunnelling_request(11), state)

      assert {:error, :timeout} = :gen_udp.recv(context.data_socket, 0, 100)
    end

    @tag :tunnelling_request
    test "resets sequence counter when it has reached 255", context do
      Mox.expect(TunnelMock, :on_telegram, fn _msg, _state -> {:ok, :new_mod_state} end)

      state = %{context.state | remote_sequence_counter: 255}

      {:noreply, state} = Tunnel.on_message(tunnelling_request(255), state)

      assert {:ok, {_, _, tunnelling_ack_frame}} = :gen_udp.recv(context.data_socket, 0, 1_000)
      assert {:ok, %Tunnelling.TunnellingAck{}} = KNXnetIP.Frame.decode(tunnelling_ack_frame)
      assert state.remote_sequence_counter == 0
    end
  end

  describe "on_message/2 tunnelling ack when status :e_no_error" do
    setup [:server_sockets, :init, :connect, :transmit]

    @tag :tunnelling_ack
    test "stops tunnelling_ack_timer", context do
      Mox.expect(TunnelMock, :transmit_ack, fn _ref, _status, _state ->
        {:ok, :got_transmit_ack_callback}
      end)

      {:noreply, state} = Tunnel.on_message(tunnelling_ack(0), context.state)

      refute is_reference(state.tunnelling_ack_timer.timer)
      refute is_reference(state.tunnelling_ack_timer.ref)
    end

    @tag :tunnelling_ack
    test "resets tunnelling timeouts counter", context do
      Mox.expect(TunnelMock, :transmit_ack, fn _ref, _status, _state ->
        {:ok, :got_transmit_ack_callback}
      end)

      state = %{context.state | tunnelling_timeouts: 1}
      {:noreply, state} = Tunnel.on_message(tunnelling_ack(0), state)
      assert state.tunnelling_timeouts == 0
    end

    @tag :tunnelling_ack
    test "removes tunnelling request from state", context do
      Mox.expect(TunnelMock, :transmit_ack, fn _ref, _status, _state ->
        {:ok, :got_transmit_ack_callback}
      end)

      {:noreply, state} = Tunnel.on_message(tunnelling_ack(0), context.state)
      assert state.tunnelling_request == nil
    end

    @tag :tunnelling_ack
    test "bumps sequence counter", context do
      Mox.expect(TunnelMock, :transmit_ack, fn _ref, _status, _state ->
        {:ok, :got_transmit_ack_callback}
      end)

      {:noreply, state} = Tunnel.on_message(tunnelling_ack(0), context.state)
      assert state.local_sequence_counter == context.state.local_sequence_counter + 1
    end

    @tag :tunnelling_ack
    test "invokes transmit_ack with status code", context do
      {req_ref, _} = context.state.tunnelling_request

      Mox.expect(TunnelMock, :transmit_ack, fn ref, status, _state ->
        assert req_ref == ref
        assert status == :e_no_error
        {:ok, :got_transmit_ack_callback}
      end)

      {:noreply, state} = Tunnel.on_message(tunnelling_ack(0), context.state)

      assert state.mod_state == :got_transmit_ack_callback
    end

    @tag :tunnelling_ack
    test "sends the next telegram in the queue", context do
      Mox.expect(TunnelMock, :transmit_ack, fn _ref, _status, _state ->
        {:ok, :got_transmit_ack_callback}
      end)

      telegram = %Telegram{
        destination: "4/4/21",
        service: :group_read,
        source: "1.1.6",
        type: :request,
        value: <<0::6>>
      }

      req_ref = make_ref()

      queue = :queue.new()
      queue = :queue.in({req_ref, telegram}, queue)

      state = %{context.state | telegram_queue: queue}

      {:noreply, state} = Tunnel.on_message(tunnelling_ack(0), state)

      assert state.local_sequence_counter == context.state.local_sequence_counter + 1
      assert {^req_ref, _req} = state.tunnelling_request

      assert {:ok, {_, _, tunnelling_request_frame}} =
               :gen_udp.recv(context.data_socket, 0, 1_000)

      assert {:ok, %Tunnelling.TunnellingRequest{} = req} =
               KNXnetIP.Frame.decode(tunnelling_request_frame)

      assert {:ok, telegram} == KNXnetIP.Telegram.decode(req.telegram)
      assert req.sequence_counter == state.local_sequence_counter
    end
  end

  describe "on_message/2 tunnelling ack when status is not :e_no_error" do
    setup [:server_sockets, :init, :connect, :transmit]

    @tag :tunnelling_ack
    test "repeats tunnelling request and disconnects", context do
      Mox.expect(TunnelMock, :transmit_ack, fn _ref, status, _state ->
        assert status == :anything_but_e_no_error
        {:ok, :got_transmit_ack_callback}
      end)

      tun_ack = tunnelling_ack(0, :anything_but_e_no_error)

      assert {:noreply, state} = Tunnel.on_message(tun_ack, context.state)

      assert {:ok, {_, _, tunnelling_request_frame}} =
               :gen_udp.recv(context.data_socket, 0, 1_000)

      assert {:ok, %Tunnelling.TunnellingRequest{}} =
               KNXnetIP.Frame.decode(tunnelling_request_frame)

      assert {:ok, {_, _, disconnect_request_frame}} =
               :gen_udp.recv(context.control_socket, 0, 1_000)

      assert {:ok, %Core.DisconnectRequest{}} = KNXnetIP.Frame.decode(disconnect_request_frame)

      assert state.disconnect_info == {:error, :anything_but_e_no_error}
    end
  end

  describe "handle_cast/2 returns transmit" do
    setup [:server_sockets, :init, :connect]

    @tag :transmit
    test "encodes and transmits a tunnelling_request on data socket", context do
      telegram = %Telegram{
        destination: "4/4/21",
        service: :group_read,
        source: "1.1.5",
        type: :request,
        value: <<0::6>>
      }

      Mox.expect(TunnelMock, :handle_cast, fn :test_transmit, _state ->
        {:transmit, make_ref(), telegram, :transmitting}
      end)

      assert {:noreply, _state} = Tunnel.handle_cast(:test_transmit, context.state)

      assert {:ok, {_, _, tunnelling_request_frame}} =
               :gen_udp.recv(context.data_socket, 0, 1_000)

      assert {:ok, %Tunnelling.TunnellingRequest{} = req} =
               KNXnetIP.Frame.decode(tunnelling_request_frame)

      assert {:ok, telegram} == KNXnetIP.Telegram.decode(req.telegram)
    end

    @tag :transmit
    test "adds tunnelling request to state", context do
      telegram = %Telegram{
        destination: "4/4/21",
        service: :group_read,
        source: "1.1.5",
        type: :request,
        value: <<0::6>>
      }

      ref = make_ref()

      Mox.expect(TunnelMock, :handle_cast, fn :test_transmit, _state ->
        {:transmit, ref, telegram, :transmitting}
      end)

      {:noreply, state} = Tunnel.handle_cast(:test_transmit, context.state)

      assert {^ref, tunnelling_request} = state.tunnelling_request
      assert {:ok, telegram} == KNXnetIP.Telegram.decode(tunnelling_request.telegram)
    end

    @tag :transmit
    test "starts tunnelling_ack_timer", context do
      Mox.expect(TunnelMock, :handle_cast, fn :test_transmit, _state ->
        telegram = %Telegram{
          destination: "4/4/21",
          service: :group_read,
          source: "1.1.5",
          type: :request,
          value: <<0::6>>
        }

        {:transmit, make_ref(), telegram, :transmitting}
      end)

      {:noreply, state} = Tunnel.handle_cast(:test_transmit, context.state)

      assert is_reference(state.tunnelling_ack_timer.timer)
      assert is_reference(state.tunnelling_ack_timer.ref)
    end

    @tag :transmit
    test "puts telegram in queue if waiting for tunnelling request ack", context do
      telegram = %Telegram{
        destination: "4/4/21",
        service: :group_read,
        source: "1.1.5",
        type: :request,
        value: <<0::6>>
      }

      ref = make_ref()

      Mox.expect(TunnelMock, :handle_cast, fn :test_transmit, _state ->
        {:transmit, ref, telegram, :transmitting}
      end)

      state = %{context.state | tunnelling_request: {make_ref(), telegram}}

      {:noreply, state} = Tunnel.handle_cast(:test_transmit, state)

      assert {{:value, {^ref, ^telegram}}, {[], []}} = :queue.out(state.telegram_queue)
    end
  end

  defp server_sockets(_context) do
    {:ok, control_socket} = :gen_udp.open(0, [:binary, active: false])
    {:ok, data_socket} = :gen_udp.open(0, [:binary, active: false])

    %{
      control_socket: control_socket,
      data_socket: data_socket
    }
  end

  defp init(context) do
    Mox.expect(TunnelMock, :init, fn [] -> {:ok, :test_state} end)

    {:ok, control_port} = :inet.port(context.control_socket)
    {:connect, :init, state} = Tunnel.init({TunnelMock, [], [server_control_port: control_port]})
    %{state: state}
  end

  defp connect(context) do
    {:ok, data_port} = :inet.port(context.data_socket)
    connect_response = connect_response(data_port)

    {:ok, state} = Tunnel.connect(:init, context.state)
    {:noreply, state} = Tunnel.on_message(connect_response, state)
    :gen_udp.recv(context.control_socket, 0, 1_000)

    %{state: state}
  end

  defp transmit(context) do
    telegram = %Telegram{
      destination: "4/4/21",
      service: :group_read,
      source: "1.1.5",
      type: :request,
      value: <<0::6>>
    }

    ref = make_ref()

    Mox.expect(TunnelMock, :handle_cast, fn :setup_transmit, _state ->
      {:transmit, ref, telegram, :transmitting}
    end)

    {:noreply, state} = Tunnel.handle_cast(:setup_transmit, context.state)
    :gen_udp.recv(context.data_socket, 0, 1_000)

    %{state: state}
  end

  defp connect_response(data_port, status \\ :e_no_error) do
    %Core.ConnectResponse{
      communication_channel_id: 10,
      status: status,
      data_endpoint: %Core.HostProtocolAddressInformation{
        ip_address: {127, 0, 0, 1},
        port: data_port
      },
      connection_response_data_block: %Core.ConnectionResponseDataBlock{
        connection_type: :tunnel_connection,
        connection_data: %{
          knx_individual_address: "1.1.1"
        }
      }
    }
  end

  defp connectionstate_response(status \\ :e_no_error) do
    %Core.ConnectionstateResponse{
      communication_channel_id: 10,
      status: status
    }
  end

  defp disconnect_request() do
    %Core.DisconnectRequest{
      communication_channel_id: 10,
      control_endpoint: %Core.HostProtocolAddressInformation{
        ip_address: {127, 0, 0, 1},
        port: 3671
      }
    }
  end

  defp disconnect_response() do
    %Core.DisconnectResponse{
      communication_channel_id: 10,
      status: :e_no_error
    }
  end

  defp tunnelling_request(sequence_counter \\ 0) do
    %Tunnelling.TunnellingRequest{
      communication_channel_id: 10,
      sequence_counter: sequence_counter,
      telegram: <<41, 0, 188, 224, 17, 1, 0, 3, 3, 0, 128, 25, 23>>
    }
  end

  defp tunnelling_ack(sequence_counter \\ 1, status \\ :e_no_error) do
    %Tunnelling.TunnellingAck{
      communication_channel_id: 10,
      sequence_counter: sequence_counter,
      status: status
    }
  end
end
