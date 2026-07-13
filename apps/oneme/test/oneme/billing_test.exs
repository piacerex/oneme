defmodule Oneme.BillingTest do
  use Oneme.DataCase

  alias Oneme.Access
  alias Oneme.Billing
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
end
