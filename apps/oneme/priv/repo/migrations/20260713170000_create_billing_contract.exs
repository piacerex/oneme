defmodule Oneme.Repo.Migrations.CreateBillingContract do
  use Ecto.Migration

  def change do
    create table(:billing_plans) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :monthly_price_cents, :integer, null: false, default: 0
      add :currency, :string, null: false, default: "jpy"
      add :limits, :map, null: false, default: %{}
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_plans, [:slug])

    create table(:team_subscriptions) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :plan_id, references(:billing_plans, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "active"
      add :current_period_start, :date, null: false
      add :current_period_end, :date, null: false
      add :provider, :string, null: false, default: "manual"
      add :provider_customer_id, :string
      add :provider_subscription_id, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:team_subscriptions, [:team_id])
    create index(:team_subscriptions, [:plan_id, :status])

    create table(:billing_events) do
      add :team_id, references(:teams, on_delete: :nilify_all)
      add :provider, :string, null: false
      add :external_id, :string, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :processed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_events, [:provider, :external_id])
    create index(:billing_events, [:team_id, :inserted_at])
  end
end
