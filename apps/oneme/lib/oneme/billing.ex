defmodule Oneme.Billing do
  @moduledoc "Provider-neutral billing plans, subscriptions, and quota summaries."

  import Ecto.Query

  alias Oneme.Billing.{BillingEvent, BillingPlan, TeamSubscription}
  alias Oneme.Repo
  alias Oneme.Usage

  @free_plan %{
    slug: "free",
    name: "Free",
    monthly_price_cents: 0,
    currency: "jpy",
    limits: %{
      "export_requested" => 10,
      "generation_requested" => 30,
      "face_analysis_requested" => 50
    },
    active: true
  }

  def list_plans do
    BillingPlan
    |> where([plan], plan.active == true)
    |> order_by([plan], asc: plan.monthly_price_cents, asc: plan.slug)
    |> Repo.all()
  end

  def create_plan(attrs) when is_map(attrs) do
    %BillingPlan{}
    |> BillingPlan.changeset(normalize_plan_attrs(attrs))
    |> Repo.insert()
  end

  def get_plan_by_slug(slug) when is_binary(slug), do: Repo.get_by(BillingPlan, slug: slug)
  def get_subscription(team_id), do: Repo.get_by(TeamSubscription, team_id: team_id)

  def overview(team_id) when is_integer(team_id) do
    with {:ok, subscription} <- ensure_subscription(team_id),
         %BillingPlan{} = plan <- Repo.get(BillingPlan, subscription.plan_id) do
      today = Date.utc_today()

      period_end =
        if Date.compare(subscription.current_period_end, today) == :lt,
          do: subscription.current_period_end,
          else: today

      usage = Usage.summary(team_id, subscription.current_period_start, period_end)

      {:ok,
       %{
         team_id: team_id,
         plan: plan,
         subscription: subscription,
         usage: usage,
         remaining: remaining_limits(plan.limits, usage)
       }}
    else
      nil -> {:error, :plan_not_found}
      error -> error
    end
  end

  def change_subscription(team_id, attrs) when is_integer(team_id) and is_map(attrs) do
    with {:ok, current} <- ensure_subscription(team_id),
         plan_slug <-
           Map.get(attrs, "planSlug", Map.get(attrs, :plan_slug, current_plan_slug(current))),
         %BillingPlan{} = plan <- get_plan_by_slug(plan_slug) do
      changes = %{
        plan_id: plan.id,
        status: Map.get(attrs, "status", Map.get(attrs, :status, current.status)),
        provider: Map.get(attrs, "provider", Map.get(attrs, :provider, current.provider)),
        provider_customer_id:
          Map.get(
            attrs,
            "providerCustomerId",
            Map.get(attrs, :provider_customer_id, current.provider_customer_id)
          ),
        provider_subscription_id:
          Map.get(
            attrs,
            "providerSubscriptionId",
            Map.get(attrs, :provider_subscription_id, current.provider_subscription_id)
          )
      }

      current
      |> TeamSubscription.changeset(changes)
      |> Repo.update()
    else
      nil -> {:error, :plan_not_found}
      error -> error
    end
  end

  def record_event(attrs) when is_map(attrs) do
    %BillingEvent{}
    |> BillingEvent.changeset(normalize_event_attrs(attrs))
    |> Repo.insert()
  end

  defp ensure_subscription(team_id) do
    case get_subscription(team_id) do
      %TeamSubscription{} = subscription -> {:ok, subscription}
      nil -> create_default_subscription(team_id)
    end
  end

  defp create_default_subscription(team_id) do
    with {:ok, plan} <- ensure_free_plan() do
      attrs = %{
        team_id: team_id,
        plan_id: plan.id,
        status: "active",
        current_period_start: Date.utc_today(),
        current_period_end: Date.add(Date.utc_today(), 30),
        provider: "manual"
      }

      case %TeamSubscription{} |> TeamSubscription.changeset(attrs) |> Repo.insert() do
        {:ok, subscription} -> {:ok, subscription}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp ensure_free_plan do
    case get_plan_by_slug("free") do
      %BillingPlan{} = plan ->
        {:ok, plan}

      nil ->
        case create_plan(@free_plan) do
          {:ok, plan} ->
            {:ok, plan}

          {:error, %Ecto.Changeset{} = changeset} ->
            case get_plan_by_slug("free") do
              %BillingPlan{} = plan -> {:ok, plan}
              nil -> {:error, changeset}
            end
        end
    end
  end

  defp remaining_limits(limits, usage) do
    limits
    |> Enum.map(fn {metric, limit} -> {metric, max(limit - Map.get(usage, metric, 0), 0)} end)
    |> Map.new()
  end

  defp current_plan_slug(subscription) do
    case Repo.get(BillingPlan, subscription.plan_id) do
      %BillingPlan{slug: slug} -> slug
      _ -> "free"
    end
  end

  defp normalize_plan_attrs(attrs) do
    %{
      slug: Map.get(attrs, "slug", Map.get(attrs, :slug)),
      name: Map.get(attrs, "name", Map.get(attrs, :name)),
      monthly_price_cents:
        Map.get(attrs, "monthlyPriceCents", Map.get(attrs, :monthly_price_cents, 0)),
      currency: Map.get(attrs, "currency", Map.get(attrs, :currency, "jpy")),
      limits: Map.get(attrs, "limits", Map.get(attrs, :limits, %{})),
      active: Map.get(attrs, "active", Map.get(attrs, :active, true))
    }
  end

  defp normalize_event_attrs(attrs) do
    %{
      team_id: Map.get(attrs, "teamId", Map.get(attrs, :team_id)),
      provider: Map.get(attrs, "provider", Map.get(attrs, :provider)),
      external_id: Map.get(attrs, "externalId", Map.get(attrs, :external_id)),
      event_type: Map.get(attrs, "eventType", Map.get(attrs, :event_type)),
      payload: Map.get(attrs, "payload", Map.get(attrs, :payload, %{})),
      processed_at: Map.get(attrs, "processedAt", Map.get(attrs, :processed_at))
    }
  end
end
