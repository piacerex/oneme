defmodule Oneme.Repo.Migrations.CreateBillingInvoices do
  use Ecto.Migration

  def change do
    create table(:billing_invoices) do
      add :team_id, references(:teams, on_delete: :nilify_all)
      add :provider, :string, null: false
      add :external_id, :string, null: false
      add :number, :string
      add :status, :string, null: false, default: "open"
      add :currency, :string, null: false, default: "jpy"
      add :subtotal_cents, :integer, null: false, default: 0
      add :total_cents, :integer, null: false, default: 0
      add :amount_due_cents, :integer, null: false, default: 0
      add :amount_paid_cents, :integer, null: false, default: 0
      add :hosted_url, :string
      add :invoice_pdf_url, :string
      add :due_date, :date
      add :paid_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_invoices, [:provider, :external_id])
    create index(:billing_invoices, [:team_id, :status, :inserted_at])
  end
end
