defmodule Newton.Links do
  @moduledoc """
  The hardcoded set of outbound links shown on /links. Names are display-cased
  for the fallback page; the Gibson tower uppercases them for its own panel.
  """

  @links [
    %{
      name: "GitHub",
      url: "https://github.com/jameswritescode",
      description: "Code, experiments, and the source of this site."
    },
    %{
      name: "Instagram",
      url: "https://www.instagram.com/raptorexplosion",
      description: "Life away from the keyboard."
    },
    %{
      name: "Bluesky",
      url: "https://bsky.app/profile/jamesnewton.com",
      description: "Short thoughts and photos."
    },
    %{
      name: "Mark OS",
      url: "https://markos.ai",
      description: "Superpower your marketing team. Review your content with AI."
    },
    %{
      name: "LinkedIn",
      url: "https://www.linkedin.com/in/jameswritescode",
      description: "Linkslop."
    },
    %{
      name: "Email",
      url: "mailto:hello@jamesnewton.com",
      description: "Say hello."
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
