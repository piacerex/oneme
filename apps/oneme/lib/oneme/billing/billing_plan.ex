defmodule Oneme.Billing.BillingPlan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "billing_plans" do
    field :slug, :string
    field :name, :string
    field :monthly_price_cents, :integer, default: 0
    field :currency, :string, default: "jpy"
    field :limits, :map, default: %{}
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:slug, :name, :monthly_price_cents, :currency, :limits, :active])
    |> validate_required([:slug, :name, :monthly_price_cents, :currency, :limits, :active])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> validate_number(:monthly_price_cents, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> validate_limits()
    |> unique_constraint(:slug)
  end

  defp validate_limits(changeset) do
    validate_change(changeset, :limits, fn :limits, limits ->
      if is_map(limits) and Enum.all?(limits, &valid_limit?/1),
        do: [],
        else: [limits: "must be a map of non-negative integer limits"]
    end)
  end

  defp valid_limit?({metric, limit}) when is_binary(metric) and is_integer(limit), do: limit >= 0
  defp valid_limit?(_entry), do: false
end
