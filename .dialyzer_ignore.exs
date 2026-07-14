# phoenix_seo 0.3.0-rc's :seo_jsonld compiler emits a hand-written Breadcrumbs
# wrapper (pulled in transitively via BreadcrumbList/ListItem; we never emit
# breadcrumbs) whose build/1 breaks its own BreadcrumbList contract. Not fixable
# in our code — the file is regenerated on every compile. Scoped to that one
# generated file so nothing of ours is masked; list_unused_filters will call
# these out once a phoenix_seo release fixes the wrapper, at which point this
# file should be deleted. Monitor: https://github.com/dbernheisel/phoenix_seo/releases
[
  ~r{seo_jsonld_generated/breadcrumbs\.ex:[\d:]+invalid_contract},
  ~r{seo_jsonld_generated/breadcrumbs\.ex:[\d:]+no_return},
  ~r{seo_jsonld_generated/breadcrumbs\.ex:[\d:]+call}
]
