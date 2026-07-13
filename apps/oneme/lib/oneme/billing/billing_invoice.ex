defmodule Oneme.Billing.BillingInvoice do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft open paid void uncollectible past_due payment_failed)

  schema "billing_invoices" do
    field :team_id, :id
    field :provider, :string
    field :external_id, :string
    field :number, :string
    field :status, :string, default: "open"
    field :currency, :string, default: "jpy"
    field :subtotal_cents, :integer, default: 0
    field :total_cents, :integer, default: 0
    field :amount_due_cents, :integer, default: 0
    field :amount_paid_cents, :integer, default: 0
    field :hosted_url, :string
    field :invoice_pdf_url, :string
    field :due_date, :date
    field :paid_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :team_id,
      :provider,
      :external_id,
      :number,
      :status,
      :currency,
      :subtotal_cents,
      :total_cents,
      :amount_due_cents,
      :amount_paid_cents,
      :hosted_url,
      :invoice_pdf_url,
      :due_date,
      :paid_at,
      :metadata
    ])
    |> validate_required([:provider, :external_id, :status, :currency, :metadata])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:currency, is: 3)
    |> validate_number(:subtotal_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_cents, greater_than_or_equal_to: 0)
    |> validate_number(:amount_due_cents, greater_than_or_equal_to: 0)
    |> validate_number(:amount_paid_cents, greater_than_or_equal_to: 0)
    |> unique_constraint([:provider, :external_id])
  end
end
