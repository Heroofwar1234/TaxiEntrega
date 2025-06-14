defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :step1, [:nosuspend])
    {:ok, %{request: request, minutes_remaining: 8, driver_accepted: false}}
  end

  def compute_ride_fare(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
    } = request
    {request, [70, 90, 120, 200, 250] |> Enum.random()}
  end

  def notify_customer_ride_fare({request, fare}) do
    %{"username" => customer} = request
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{msg: "Ride fare: #{fare}"})
  end

  def find_candidate_taxis(%{"pickup_address" => _pickup_address}) do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "pippin", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "samwise", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end

  def handle_info(:step1, %{request: request} = state) do
    task = Task.async(fn ->
      compute_ride_fare(request)
      |> notify_customer_ride_fare()
    end)

    list_of_taxis = find_candidate_taxis(request)
    Task.await(task)

    taxi = hd(list_of_taxis)

    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    TaxiBeWeb.Endpoint.broadcast("driver:" <> taxi.nickname, "booking_request", %{
      msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
      bookingId: booking_id
    })

    # 2-second retry timer for next driver
    retry_timer = Process.send_after(self(), :retry_timeout, 2000)
    # 1-minute global search timeout
    search_timeout = Process.send_after(self(), :driver_search_timeout, 90_000)

    {:noreply,
     %{
       request: request,
       contacted_taxi: taxi,
       candidates: tl(list_of_taxis),
       retry_timer_ref: retry_timer,
       search_timer_ref: search_timeout
     }}
  end

  def auxilary(%{request: request, candidates: list_of_taxis} = state) do
    taxi = hd(list_of_taxis)

    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    TaxiBeWeb.Endpoint.broadcast("driver:" <> taxi.nickname, "booking_request", %{
      msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
      bookingId: booking_id
    })

    retry_timer = Process.send_after(self(), :retry_timeout, 2000)

    {:noreply,
     %{state | contacted_taxi: taxi, candidates: tl(list_of_taxis), retry_timer_ref: retry_timer}}
  end

  def handle_info(:retry_timeout, %{candidates: []} = state) do
    IO.puts("No more taxis to try.")
    {:noreply, state}
  end

  def handle_info(:retry_timeout, state) do
    auxilary(state)
  end

  def handle_info(:driver_search_timeout, %{request: %{"username" => customer}} = state) do
    IO.puts("Driver search timeout hit.")
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "No drivers found. Try again later."
    })
    {:stop, :normal, state}
  end

  def handle_info(:driver_arrival_tick, %{minutes_remaining: 1, request: %{"username" => customer}} = state) do
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "Your driver is arriving now!"
    })
    {:stop, :normal, state}
  end

  def handle_info(:driver_arrival_tick, %{minutes_remaining: n, request: %{"username" => customer}} = state)
      when n > 1 do
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "Your driver will arrive in #{n} minutes."
    })

    Process.send_after(self(), :driver_arrival_tick, 60_000)

    {:noreply, %{state | minutes_remaining: n - 1}}
  end

  def handle_cast({:process_reject, _msg}, state) do
    IO.puts("Driver rejected.")
    auxilary(state)
  end

  def handle_cast({:process_accept, _msg}, state) do
    IO.puts("Driver accepted.")
    %{
      request: %{"username" => customer},
      retry_timer_ref: retry_timer,
      search_timer_ref: search_timer
    } = state

    # Cancel existing timers
    Process.cancel_timer(retry_timer)
    Process.cancel_timer(search_timer)

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "Your driver has accepted the ride. ETA: 8 minutes"
    })

    Process.send_after(self(), :driver_arrival_tick, 60_000)

    {:noreply, %{state | minutes_remaining: 8, driver_accepted: true}}
 end
end
