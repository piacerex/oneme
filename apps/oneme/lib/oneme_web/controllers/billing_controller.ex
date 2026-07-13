defmodule OnemeWeb.BillingController do
  use OnemeWeb, :controller

  alias Oneme.Access
  alias Oneme.Billing

  def show(conn, _params) do
    with {:ok, team_id} <- admin_team(conn),
         {:ok, overview} <- Billing.overview(team_id) do
      json(conn, serialize_overview(overview))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "billing_unavailable"})
    end
  end

  def invoices(conn, _params) do
    with {:ok, team_id} <- admin_team(conn) do
      json(conn, %{invoices: Enum.map(Billing.list_invoices(team_id), &serialize_invoice/1)})
    else
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def provider_webhook(conn, %{"provider" => provider} = params) do
    body = conn.assigns[:raw_body] || Jason.encode!(Map.delete(params, "provider"))
    signature = List.first(get_req_header(conn, "x-oneme-billing-signature"))

    with true <- is_binary(signature),
         :ok <- Billing.verify_provider_webhook(provider, body, signature),
         {:ok, result} <- Billing.process_provider_event(provider, params) do
      json(conn, %{received: true, duplicate: result.duplicate})
    else
      false ->
        conn |> put_status(:unauthorized) |> json(%{error: "billing_signature_required"})

      {:error, :secret_not_configured} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "billing_webhook_not_configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_billing_signature"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_billing_event", reason: inspect(reason)})
    end
  end

  def update_subscription(conn, params) do
    with {:ok, team_id} <- admin_team(conn),
         {:ok, subscription} <- Billing.change_subscription(team_id, params),
         {:ok, overview} <- Billing.overview(team_id) do
      json(conn, serialize_overview(Map.put(overview, :subscription, subscription)))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :plan_not_found} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "plan_not_found"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def create_plan(conn, params) do
    with {:ok, _team_id} <- owner_team(conn),
         {:ok, plan} <- Billing.create_plan(params) do
      conn |> put_status(:created) |> json(%{plan: serialize_plan(plan)})
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp serialize_overview(overview) do
    %{
      teamId: overview.team_id,
      plan: serialize_plan(overview.plan),
      plans: Enum.map(Billing.list_plans(), &serialize_plan/1),
      subscription: serialize_subscription(overview.subscription),
      usage: overview.usage,
      remaining: overview.remaining
    }
  end

  defp serialize_plan(plan) do
    %{
      id: plan.id,
      slug: plan.slug,
      name: plan.name,
      monthlyPriceCents: plan.monthly_price_cents,
      currency: plan.currency,
      limits: plan.limits,
      active: plan.active
    }
  end

  defp serialize_subscription(subscription) do
    %{
      id: subscription.id,
      planId: subscription.plan_id,
      status: subscription.status,
      currentPeriodStart: subscription.current_period_start,
      currentPeriodEnd: subscription.current_period_end,
      provider: subscription.provider,
      providerCustomerId: subscription.provider_customer_id,
      providerSubscriptionId: subscription.provider_subscription_id
    }
  end

  defp serialize_invoice(invoice) do
    %{
      id: invoice.id,
      teamId: invoice.team_id,
      provider: invoice.provider,
      externalId: invoice.external_id,
      number: invoice.number,
      status: invoice.status,
      currency: invoice.currency,
      subtotalCents: invoice.subtotal_cents,
      totalCents: invoice.total_cents,
      amountDueCents: invoice.amount_due_cents,
      amountPaidCents: invoice.amount_paid_cents,
      hostedUrl: invoice.hosted_url,
      invoicePdfUrl: invoice.invoice_pdf_url,
      dueDate: invoice.due_date,
      paidAt: invoice.paid_at,
      metadata: invoice.metadata,
      createdAt: invoice.inserted_at,
      updatedAt: invoice.updated_at
    }
  end

  defp admin_team(conn) do
    case conn.assigns[:principal] do
      %{team_id: team_id} = principal when is_integer(team_id) ->
        if Access.authorized?(principal, "admin"), do: {:ok, team_id}, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp owner_team(conn) do
    case conn.assigns[:principal] do
      %{team_id: team_id, role: role} when is_integer(team_id) and role in ["owner"] ->
        {:ok, team_id}

      _ ->
        {:error, :forbidden}
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
