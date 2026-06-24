defmodule Newton.Links do
  @moduledoc "The hardcoded set of outbound links shown on the /links page."

  @links [
    %{
      name: "GITHUB",
      url: "https://github.com/jameswritescode",
      description: "Code, experiments, and the source of this very site."
    },
    %{
      name: "LINKEDIN",
      url: "https://www.linkedin.com/in/jameswritescode",
      description: "The professional paper trail."
    },
    %{
      name: "BLUESKY",
      url: "https://bsky.app/profile/jamesnewton.com",
      description: "Short thoughts, mostly about software and craft."
    },
    %{
      name: "MARK OS",
      url: "https://markos.ai",
      description: "Where I work. We think about how software gets built."
    },
    %{
      name: "EMAIL",
      url: "mailto:hello@jamesnewton.com",
      description: "Say hello. I read everything."
    }
    # RSS is deferred until the site has an actual feed. Add once it exists:
    # %{name: "RSS", url: "/feed.xml", description: "Subscribe the old-fashioned way."}
  ]

  @doc "The ordered list of links, each `%{name, url, description}`."
  @spec all() :: [%{name: String.t(), url: String.t(), description: String.t()}]
  def all, do: @links

  @doc "Whether a url points off-site (and should open in a new tab)."
  @spec external?(String.t()) :: boolean()
  def external?(url), do: String.starts_with?(url, "http")
end
