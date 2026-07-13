defmodule Oneme.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Oneme.RateLimiter

  setup do
    RateLimiter.reset!()
    :ok
  end

  test "returns remaining capacity and blocks after the limit" do
    assert {true, 1, reset_at} = RateLimiter.allow?("test-key", 2, 60)
    assert reset_at > System.system_time(:second)
    assert {true, 0, ^reset_at} = RateLimiter.allow?("test-key", 2, 60)
    assert {false, 0, ^reset_at} = RateLimiter.allow?("test-key", 2, 60)
  end
end
