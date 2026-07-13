defmodule Oneme.Usage do
  @moduledoc "Daily team usage counters and summaries."

  import Ecto.Query

  alias Oneme.Repo
  alias Oneme.Usage.UsageCounter

  def record(team_id, metric, quantity \\ 1)

  def record(team_id, metric, quantity)
      when is_integer(team_id) and is_binary(metric) and is_integer(quantity) and quantity > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      UsageCounter,
      [
        %{
          team_id: team_id,
          period_start: Date.utc_today(),
          metric: metric,
          quantity: quantity,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [inc: [quantity: quantity], set: [updated_at: now]],
      conflict_target: [:team_id, :period_start, :metric]
    )

    :ok
  end

  def record(_team_id, _metric, _quantity), do: {:error, :invalid_usage}

  def summary(team_id, from_date \\ Date.add(Date.utc_today(), -30), to_date \\ Date.utc_today()) do
    UsageCounter
    |> where([counter], counter.team_id == ^team_id)
    |> where([counter], counter.period_start >= ^from_date and counter.period_start <= ^to_date)
    |> group_by([counter], counter.metric)
    |> select([counter], {counter.metric, sum(counter.quantity)})
    |> Repo.all()
    |> Map.new(fn {metric, quantity} -> {metric, normalize_quantity(quantity)} end)
  end

  defp normalize_quantity(quantity) when is_integer(quantity), do: quantity
  defp normalize_quantity(%Decimal{} = quantity), do: Decimal.to_integer(quantity)
end
