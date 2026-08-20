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

  test "redacts OAuth token-endpoint credentials by keyword" do
    context = %{
      "request.params" => %{
        "client_secret" => "cs-abc",
        "refresh_token" => "rt-abc",
        "access_token" => "at-abc",
        "code_verifier" => "cv-abc",
        "grant_type" => "authorization_code",
        "redirect_uri" => "http://127.0.0.1:9000/cb"
      }
    }

    params = ErrorFilter.sanitize(context)["request.params"]

    assert params["client_secret"] == "[REDACTED]"
    assert params["refresh_token"] == "[REDACTED]"
    assert params["access_token"] == "[REDACTED]"
    assert params["code_verifier"] == "[REDACTED]"
    assert params["grant_type"] == "authorization_code"
    assert params["redirect_uri"] == "http://127.0.0.1:9000/cb"
  end

  test "redacts keyword-matched credentials from the raw query string too" do
    context = %{"request.query" => "refresh_token=rt-abc&grant_type=refresh_token"}

    sanitized = ErrorFilter.sanitize(context)

    refute sanitized["request.query"] =~ "rt-abc"
    assert sanitized["request.query"] =~ "grant_type=refresh_token"
  end

  test "redacts the draft preview token from params and the raw query string" do
    context = %{
      "request.params" => %{"p" => "s3cret-preview-token", "slug" => "a-draft"},
      "request.query" => "p=s3cret-preview-token&utm=x",
      "request.path" => "/posts/a-draft"
    }

    sanitized = ErrorFilter.sanitize(context)

    assert sanitized["request.params"]["p"] == "[REDACTED]"
    assert sanitized["request.params"]["slug"] == "a-draft"
    refute sanitized["request.query"] =~ "s3cret-preview-token"
    assert sanitized["request.query"] =~ "utm=x"
    assert sanitized["request.path"] == "/posts/a-draft"
  end

  test "redacts sensitive values in live_view params" do
    context = %{"live_view.params" => %{"p" => "tok", "id" => "3"}}
    sanitized = ErrorFilter.sanitize(context)

    assert sanitized["live_view.params"]["p"] == "[REDACTED]"
    assert sanitized["live_view.params"]["id"] == "3"
  end

  test "passes through a context with no request params" do
    context = %{"other" => "value"}
    assert ErrorFilter.sanitize(context) == context
  end
end
