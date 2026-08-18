# phoenix_seo's :seo_jsonld compiler (still as of 0.3.1) emits a hand-written Breadcrumbs
# wrapper (pulled in transitively via BreadcrumbList/ListItem; we never emit
# breadcrumbs) whose build/1 breaks its own BreadcrumbList contract. Not fixable
# in our code — the file is regenerated on every compile. Scoped to that one
# generated file so nothing of ours is masked; list_unused_filters will call
# these out once a phoenix_seo release fixes the wrapper, at which point this
# file should be deleted. Monitor: https://github.com/dbernheisel/phoenix_seo/releases
# anubis_mcp 2.0.0's Anubis.Server.Response.json/2 is typed as `data :: map`,
# but its own moduledoc and doctest document passing any JSON-encodable term,
# including lists (`Response.tool() |> Response.json([1, 2, 3])`). ListPosts
# returns a JSON array of row maps, which is exactly that documented, list
# case — the @spec is simply narrower than the implementation. Not fixable in
# our code; revisit if a later anubis_mcp release corrects the spec.
[
  ~r{seo_jsonld_generated/breadcrumbs\.ex:[\d:]+invalid_contract},
  ~r{seo_jsonld_generated/breadcrumbs\.ex:[\d:]+no_return},
  ~r{seo_jsonld_generated/breadcrumbs\.ex:[\d:]+call},
  ~r{mcp/tools/list_posts\.ex:[\d:]+no_return},
  ~r{mcp/tools/list_posts\.ex:[\d:]+call}
]
