defmodule Oneme.RateLimiter do
  @moduledoc "Small in-memory fixed-window rate limiter for the Phoenix API edge."

  use GenServer

  @table :oneme_rate_limits
  @default_limit 120
  @window_seconds 60

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  def allow?(key, limit \\ configured_limit(), window_seconds \\ @window_seconds) do
    now = System.system_time(:second)
    bucket = div(now, window_seconds)
    table_key = {key, bucket}

    count =
      case :ets.lookup(@table, table_key) do
        [] ->
          :ets.insert(@table, {table_key, 1})
          1

        [{^table_key, current}] ->
          :ets.update_counter(@table, table_key, {2, 1})
          current + 1
      end

    remaining = max(limit - count, 0)
    reset_at = (bucket + 1) * window_seconds
    {count <= limit, remaining, reset_at}
  end

  def reset!, do: :ets.delete_all_objects(@table)

  def configured_limit do
    case Integer.parse(
           System.get_env("ONEME_RATE_LIMIT_PER_MINUTE", Integer.to_string(@default_limit))
         ) do
      {limit, ""} when limit > 0 -> limit
      _ -> @default_limit
    end
  end
end
