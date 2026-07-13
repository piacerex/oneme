defmodule Oneme.UsageTest do
  use Oneme.DataCase

  alias Oneme.Access
  alias Oneme.Usage

  test "increments and summarizes daily team metrics" do
    assert {:ok, team} = Access.create_team(%{name: "Usage team", slug: "usage-team"})
    assert :ok = Usage.record(team.id, "export_requested")
    assert :ok = Usage.record(team.id, "export_requested", 2)
    assert :ok = Usage.record(team.id, "generation_requested")

    assert Usage.summary(team.id) == %{
             "export_requested" => 3,
             "generation_requested" => 1
           }
  end
end
