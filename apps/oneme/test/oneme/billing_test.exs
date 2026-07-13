defmodule Oneme.BillingTest do
  use Oneme.DataCase

  alias Oneme.Access
  alias Oneme.Billing
  alias Oneme.Billing.{BillingEvent, BillingInvoice, ProviderWebhook}
  alias Oneme.Repo
  alias Oneme.Usage

  test "creates a free subscription and reports period usage remaining" do
    assert {:ok, team} = Access.create_team(%{name: "Billing team", slug: "billing-team"})
    assert {:ok, overview} = Billing.overview(team.id)

    assert overview.plan.slug == "free"
    assert overview.subscription.status == "active"
    assert overview.remaining["export_requested"] == 10

    assert :ok = Usage.record(team.id, "export_requested", 3)
    assert {:ok, updated} = Billing.overview(team.id)
    assert updated.usage["export_requested"] == 3
    assert updated.remaining["export_requested"] == 7
  end

  test "rejects invalid plan limits" do
    assert {:error, changeset} =
             Billing.create_plan(%{
               "slug" => "invalid-limits",
               "name" => "Invalid",
               "limits" => %{"exports" => -1}
             })

    assert errors_on(changeset).limits
  end

  test "upserts provider invoices and ignores duplicate events" do
    assert {:ok, team} = Access.create_team(%{name: "Provider team", slug: "provider-team"})

    paid_event = %{
      "id" => "evt_invoice_paid_1",
      "type" => "invoice.paid",
      "teamId" => team.id,
      "invoice" => %{
        "id" => "invoice_1",
        "number" => "INV-001",
        "currency" => "JPY",
        "subtotal" => 1200,
        "total" => 1200,
        "amountDue" => 1200,
        "amountPaid" => 1200,
        "hostedUrl" => "https://billing.example/invoice_1",
        "metadata" => %{"teamId" => Integer.to_string(team.id)}
      }
    }

    assert {:ok, %{duplicate: false, invoice: %BillingInvoice{status: "paid"}}} =
             Billing.process_provider_event("mock", paid_event)

    assert {:ok, %{duplicate: true}} = Billing.process_provider_event("mock", paid_event)
    assert Repo.aggregate(BillingEvent, :count, :id) == 1

    failed_event = %{
      "id" => "evt_invoice_failed_1",
      "type" => "invoice.payment_failed",
      "teamId" => team.id,
      "invoice" => %{"id" => "invoice_1", "amountDue" => 1200}
    }

    assert {:ok, %{duplicate: false, invoice: %BillingInvoice{status: "past_due"}}} =
             Billing.process_provider_event("mock", failed_event)

    assert [%BillingInvoice{status: "past_due", total_cents: 1200}] =
             Billing.list_invoices(team.id)
  end

  test "requires an event id and type" do
    assert {:error, :provider_event_id_and_type_required} =
             Billing.process_provider_event("mock", %{"type" => "invoice.paid"})
  end

  test "signs provider webhook bodies" do
    body = ~s({"id":"evt_1"})
    signature = ProviderWebhook.signature("test-secret", body)

    Application.put_env(:oneme, :billing_webhook_secrets, %{"mock" => "test-secret"})

    on_exit(fn -> Application.delete_env(:oneme, :billing_webhook_secrets) end)

    assert :ok = Billing.verify_provider_webhook("mock", body, signature)

    assert {:error, :invalid_signature} =
             Billing.verify_provider_webhook("mock", body, "sha256=bad")
  end
end
