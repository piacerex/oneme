defmodule Oneme.Billing.TeamSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active trialing past_due canceled)

  schema "team_subscriptions" do
    field :team_id, :id
    field :plan_id, :id
    field :status, :string, default: "active"
    field :current_period_start, :date
    field :current_period_end, :date
    field :provider, :string, default: "manual"
    field :provider_customer_id, :string
    field :provider_subscription_id, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :team_id,
      :plan_id,
      :status,
      :current_period_start,
      :current_period_end,
      :provider,
      :provider_customer_id,
      :provider_subscription_id
    ])
    |> validate_required([
      :team_id,
      :plan_id,
      :status,
      :current_period_start,
      :current_period_end,
      :provider
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_date_order()
  end

  defp validate_date_order(changeset) do
    start_date = get_field(changeset, :current_period_start)
    end_date = get_field(changeset, :current_period_end)

    if start_date && end_date && Date.compare(start_date, end_date) != :lt do
      add_error(changeset, :current_period_end, "must be after current_period_start")
    else
      changeset
    end
  end
end
