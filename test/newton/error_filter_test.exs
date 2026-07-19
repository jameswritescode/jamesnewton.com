defmodule Newton.ErrorFilterTest do
  use ExUnit.Case, async: true

  alias Newton.ErrorFilter

  test "redacts credential params anywhere in the request params" do
    context = %{
      "request.params" => %{
        "user" => %{"email" => "a@b.com", "password" => "hunter2"},
        "current_password" => "old",
        "code" => "recovery-code",
        "keep" => "visible"
      },
      "request.path" => "/login"
    }

    sanitized = ErrorFilter.sanitize(context)
    params = sanitized["request.params"]

    assert params["user"]["password"] == "[REDACTED]"
    assert params["user"]["email"] == "a@b.com"
    assert params["current_password"] == "[REDACTED]"
    assert params["code"] == "[REDACTED]"
    assert params["keep"] == "visible"
    assert sanitized["request.path"] == "/login"
  end

  test "passes through a context with no request params" do
    context = %{"other" => "value"}
    assert ErrorFilter.sanitize(context) == context
  end
end
