defmodule Oneme.Billing do
  @moduledoc "Provider-neutral billing plans, subscriptions, and quota summaries."

  import Ecto.Query

  alias Oneme.Billing.{
    BillingEvent,
    BillingInvoice,
    BillingPlan,
    CheckoutProvider,
    ProviderWebhook,
    TeamSubscription
  }

  alias Oneme.Operations
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

  def list_invoices(team_id) when is_integer(team_id) do
    BillingInvoice
    |> where([invoice], invoice.team_id == ^team_id)
    |> order_by([invoice], desc: invoice.inserted_at)
    |> limit(100)
    |> Repo.all()
  end

  def create_checkout_session(team_id, attrs)
      when is_integer(team_id) and is_map(attrs) do
    with {:ok, subscription} <- ensure_subscription(team_id),
         {:ok, plan_slug} <- checkout_plan_slug(attrs, subscription),
         %BillingPlan{active: true} = plan <- get_plan_by_slug(plan_slug),
         {:ok, success_url} <- checkout_return_url(attrs, "successUrl", :success_url),
         {:ok, cancel_url} <- checkout_return_url(attrs, "cancelUrl", :cancel_url),
         {:ok, idempotency_key} <- checkout_idempotency_key(attrs),
         {:ok, session} <-
           CheckoutProvider.create(
             checkout_payload(team_id, plan, success_url, cancel_url),
             idempotency_key
           ) do
      metadata = %{
        "planSlug" => plan.slug,
        "provider" => session.provider,
        "sessionId" => session.session_id
      }

      Operations.track_usage("billing_checkout_requested", %{
        subject_type: "team",
        subject_id: team_id,
        metadata: metadata
      })

      Operations.track_audit("billing_checkout_requested", %{
        resource_type: "team",
        resource_id: team_id,
        metadata: metadata
      })

      {:ok, session}
    else
      nil -> {:error, :plan_not_found}
      %BillingPlan{} -> {:error, :plan_inactive}
      {:error, _reason} = error -> error
    end
  end

  def create_checkout_session(_team_id, _attrs), do: {:error, :invalid_checkout_request}

  def verify_provider_webhook(provider, body, signature),
    do: ProviderWebhook.verify(provider, body, signature)

  def process_provider_event(provider, attrs) when is_binary(provider) and is_map(attrs) do
    with {:ok, normalized} <- normalize_provider_event(attrs) do
      Repo.transaction(fn -> process_normalized_event(provider, normalized) end)
    end
  end

  def process_provider_event(_provider, _attrs), do: {:error, :invalid_provider_event}

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

  def authorize_usage(team_id, metric) when is_integer(team_id) and is_binary(metric) do
    with {:ok, %{subscription: subscription, remaining: remaining}} <- overview(team_id) do
      cond do
        subscription.status in ["past_due", "canceled"] ->
          {:error, :subscription_inactive}

        Map.has_key?(remaining, metric) and Map.get(remaining, metric, 0) <= 0 ->
          {:error, :quota_exceeded}

        true ->
          :ok
      end
    end
  end

  def authorize_usage(_team_id, _metric), do: :ok

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

  defp process_normalized_event(provider, normalized) do
    case Repo.get_by(BillingEvent, provider: provider, external_id: normalized.external_id) do
      %BillingEvent{} = event ->
        %{event: event, duplicate: true, invoice: nil}

      nil ->
        attrs = Map.put(normalized, :provider, provider)

        with {:ok, event} <- %BillingEvent{} |> BillingEvent.changeset(attrs) |> Repo.insert(),
             {:ok, invoice} <- apply_provider_event(provider, normalized),
             {:ok, event} <-
               event
               |> BillingEvent.changeset(%{
                 processed_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
               |> Repo.update() do
          %{event: event, duplicate: false, invoice: invoice}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp normalize_provider_event(attrs) do
    external_id = first_value(attrs, ["id", "eventId", "externalId"])
    event_type = first_value(attrs, ["type", "eventType"])

    if is_binary(external_id) and external_id != "" and is_binary(event_type) and event_type != "" do
      {:ok,
       %{
         external_id: external_id,
         event_type: event_type,
         team_id: integer_value(first_value(attrs, ["teamId"])),
         payload: attrs
       }}
    else
      {:error, :provider_event_id_and_type_required}
    end
  end

  defp apply_provider_event(provider, %{
         event_type: event_type,
         payload: payload,
         team_id: team_id
       }) do
    cond do
      String.starts_with?(event_type, "invoice.") ->
        upsert_invoice(provider, event_type, payload, team_id)

      String.starts_with?(event_type, "customer.subscription") or
          String.starts_with?(event_type, "subscription.") ->
        sync_subscription(provider, event_type, payload, team_id)

      true ->
        {:ok, nil}
    end
  end

  defp upsert_invoice(provider, event_type, payload, event_team_id) do
    source = nested_object(payload, "invoice")
    external_id = first_value(source, ["id", "externalId"])

    if is_binary(external_id) and external_id != "" do
      present_attrs =
        %{
          team_id: event_team_id || metadata_team_id(source),
          provider: provider,
          external_id: external_id,
          number: first_value(source, ["number", "invoiceNumber"]),
          status: invoice_status(event_type, source),
          currency: currency_value(first_value(source, ["currency"])),
          subtotal_cents: integer_value(first_value(source, ["subtotal", "subtotalCents"])),
          total_cents: integer_value(first_value(source, ["total", "totalCents"])),
          amount_due_cents: integer_value(first_value(source, ["amountDue", "amountDueCents"])),
          amount_paid_cents:
            integer_value(first_value(source, ["amountPaid", "amountPaidCents"])),
          hosted_url: first_value(source, ["hostedUrl", "hostedInvoiceUrl"]),
          invoice_pdf_url: first_value(source, ["invoicePdfUrl", "invoicePdf"]),
          due_date: date_value(first_value(source, ["dueDate"])),
          paid_at: paid_at(event_type, source),
          metadata:
            if(is_map(first_value(source, ["metadata"])), do: first_value(source, ["metadata"]))
        }
        |> drop_nil_values()

      insert_attrs =
        Map.merge(
          %{
            currency: "jpy",
            subtotal_cents: 0,
            total_cents: 0,
            amount_due_cents: 0,
            amount_paid_cents: 0,
            metadata: %{}
          },
          present_attrs
        )

      invoice = Repo.get_by(BillingInvoice, provider: provider, external_id: external_id)

      case invoice do
        nil ->
          %BillingInvoice{}
          |> BillingInvoice.changeset(insert_attrs)
          |> Repo.insert()

        %BillingInvoice{} = invoice ->
          invoice
          |> BillingInvoice.changeset(present_attrs)
          |> Repo.update()
      end
    else
      {:error, :invoice_id_required}
    end
  end

  defp sync_subscription(provider, event_type, payload, event_team_id) do
    source = nested_object(payload, "subscription")
    team_id = event_team_id || metadata_team_id(source)

    if is_integer(team_id) do
      plan_slug = first_value(source, ["planSlug", "plan_slug"])
      status = subscription_status(event_type, first_value(source, ["status"]))

      with {:ok, current} <- ensure_subscription(team_id),
           %BillingPlan{} = plan <- get_plan_by_slug(plan_slug || current_plan_slug(current)),
           {:ok, subscription} <-
             current
             |> TeamSubscription.changeset(%{
               plan_id: plan.id,
               status: status,
               provider: provider,
               provider_customer_id: first_value(source, ["providerCustomerId", "customerId"]),
               provider_subscription_id: first_value(source, ["providerSubscriptionId", "id"])
             })
             |> Repo.update() do
        {:ok, subscription}
      else
        nil -> {:error, :plan_not_found}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, nil}
    end
  end

  defp nested_object(payload, key) do
    case first_value(payload, [key]) do
      object when is_map(object) ->
        object

      _ ->
        case first_value(payload, ["data"]) do
          %{} = data ->
            case first_value(data, ["object"]) do
              object when is_map(object) -> object
              _ -> payload
            end

          _ ->
            payload
        end
    end
  end

  defp metadata_team_id(source) do
    case first_value(source, ["metadata"]) do
      metadata when is_map(metadata) ->
        integer_value(first_value(metadata, ["teamId", "team_id"]))

      _ ->
        nil
    end
  end

  defp invoice_status("invoice.paid", _source), do: "paid"
  defp invoice_status("invoice.payment_failed", _source), do: "past_due"

  defp invoice_status(_event_type, source) do
    case first_value(source, ["status"]) do
      status when status in ~w(draft open paid void uncollectible past_due payment_failed) ->
        status

      _ ->
        "open"
    end
  end

  defp subscription_status("customer.subscription.deleted", _status), do: "canceled"

  defp subscription_status(_event_type, status)
       when status in ~w(active trialing past_due canceled), do: status

  defp subscription_status(_event_type, _status), do: "active"

  defp paid_at("invoice.paid", source) do
    date_time_value(first_value(source, ["paidAt", "paid_at"])) ||
      DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp paid_at(_event_type, source),
    do: date_time_value(first_value(source, ["paidAt", "paid_at"]))

  defp first_value(map, keys) when is_map(map) do
    Enum.find_value(keys, fn key -> Map.get(map, key) || Map.get(map, key_to_atom(key)) end)
  end

  defp first_value(_map, _keys), do: nil

  defp key_to_atom("teamId"), do: :team_id
  defp key_to_atom("id"), do: :id
  defp key_to_atom("type"), do: :type
  defp key_to_atom("eventId"), do: :event_id
  defp key_to_atom("externalId"), do: :external_id
  defp key_to_atom("eventType"), do: :event_type
  defp key_to_atom("invoice"), do: :invoice
  defp key_to_atom("data"), do: :data
  defp key_to_atom("object"), do: :object
  defp key_to_atom("subscription"), do: :subscription
  defp key_to_atom("status"), do: :status
  defp key_to_atom("currency"), do: :currency
  defp key_to_atom("metadata"), do: :metadata
  defp key_to_atom("number"), do: :number
  defp key_to_atom("total"), do: :total
  defp key_to_atom("subtotal"), do: :subtotal
  defp key_to_atom("customerId"), do: :customer_id
  defp key_to_atom("planSlug"), do: :plan_slug
  defp key_to_atom("plan_slug"), do: :plan_slug
  defp key_to_atom("invoiceNumber"), do: :invoice_number
  defp key_to_atom("subtotalCents"), do: :subtotal_cents
  defp key_to_atom("totalCents"), do: :total_cents
  defp key_to_atom("amountDue"), do: :amount_due
  defp key_to_atom("amountDueCents"), do: :amount_due_cents
  defp key_to_atom("amountPaid"), do: :amount_paid
  defp key_to_atom("amountPaidCents"), do: :amount_paid_cents
  defp key_to_atom("hostedUrl"), do: :hosted_url
  defp key_to_atom("hostedInvoiceUrl"), do: :hosted_invoice_url
  defp key_to_atom("invoicePdfUrl"), do: :invoice_pdf_url
  defp key_to_atom("invoicePdf"), do: :invoice_pdf
  defp key_to_atom("dueDate"), do: :due_date
  defp key_to_atom("paidAt"), do: :paid_at
  defp key_to_atom("providerCustomerId"), do: :provider_customer_id
  defp key_to_atom("providerSubscriptionId"), do: :provider_subscription_id
  defp key_to_atom(_key), do: nil

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer_value(_value), do: nil

  defp currency_value(value) when is_binary(value) and value != "", do: String.downcase(value)
  defp currency_value(_value), do: nil

  defp drop_nil_values(attrs),
    do: Enum.reject(attrs, fn {_key, value} -> is_nil(value) end) |> Map.new()

  defp date_value(%Date{} = date), do: date

  defp date_value(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date_value(_value), do: nil

  defp date_time_value(%DateTime{} = date_time), do: DateTime.truncate(date_time, :second)

  defp date_time_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} -> DateTime.truncate(date_time, :second)
      _ -> nil
    end
  end

  defp date_time_value(_value), do: nil

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

  defp checkout_plan_slug(attrs, subscription) do
    value =
      Map.get(attrs, "planSlug", Map.get(attrs, :plan_slug, current_plan_slug(subscription)))

    if is_binary(value) and value != "" do
      {:ok, value}
    else
      {:error, :invalid_plan}
    end
  end

  defp checkout_return_url(attrs, string_key, atom_key) do
    case Map.get(attrs, string_key, Map.get(attrs, atom_key)) do
      value when is_binary(value) ->
        case URI.parse(String.trim(value)) do
          %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
            {:ok, String.slice(String.trim(value), 0, 2_000)}

          _ ->
            {:error, :invalid_return_url}
        end

      _ ->
        {:error, :return_url_required}
    end
  end

  defp checkout_idempotency_key(attrs) do
    value = Map.get(attrs, "idempotencyKey", Map.get(attrs, :idempotency_key))

    if is_binary(value) and String.trim(value) != "" do
      {:ok, String.trim(value)}
    else
      {:error, :idempotency_key_required}
    end
  end

  defp checkout_payload(team_id, plan, success_url, cancel_url) do
    %{
      "kind" => "subscription_checkout",
      "teamId" => team_id,
      "plan" => %{
        "slug" => plan.slug,
        "currency" => plan.currency,
        "monthlyPriceCents" => plan.monthly_price_cents
      },
      "successUrl" => success_url,
      "cancelUrl" => cancel_url
    }
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
