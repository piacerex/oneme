defmodule Oneme.WebhookDeliveryWorker do
  @moduledoc "Asynchronously dispatches and recovers queued webhook deliveries."

  use GenServer

  alias Oneme.Webhooks

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(delivery_id) when is_integer(delivery_id) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      _pid -> GenServer.cast(__MODULE__, {:enqueue, delivery_id})
    end
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :recover_queued, 0)
    {:ok, %{in_flight: %{}}}
  end

  @impl true
  def handle_cast({:enqueue, delivery_id}, state) do
    {:noreply, dispatch(delivery_id, state)}
  end

  @impl true
  def handle_info(:recover_queued, state) do
    next_state = Enum.reduce(Webhooks.queued_delivery_ids(), state, &dispatch(&1, &2))
    {:noreply, next_state}
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    {:noreply, remove_task(state, ref)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, remove_task(state, ref)}
  end

  defp dispatch(delivery_id, state) do
    if Enum.member?(Map.values(state.in_flight), delivery_id) do
      state
    else
      task =
        Task.Supervisor.async_nolink(Oneme.WebhookDeliveryTasks, fn ->
          Webhooks.deliver(delivery_id)
        end)

      put_in(state.in_flight[task.ref], delivery_id)
    end
  end

  defp remove_task(state, ref), do: %{state | in_flight: Map.delete(state.in_flight, ref)}
end
