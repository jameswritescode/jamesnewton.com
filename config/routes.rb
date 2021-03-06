# frozen_string_literal: true

Rails.application.routes.draw do
  # NOTE: Support for redirecting legacy blog.jamesnewton.com
  constraints subdomain: 'blog' do
    get '/', to: redirect('https://jamesnewton.com', status: 302)
    get '/:any', to: redirect('https://jamesnewton.com/blog/%{any}')
  end

  # Errors
  with_options via: :all do
    match '/404', to: 'errors#not_found'
    match '/422', to: 'errors#unprocessable_entity'
    match '/500', to: 'errors#internal_server_error'
  end

  post '/graphql', to: 'graphql#execute'

  get(
    '/sitemap.xml.gz',
    to: redirect("https://jamesnewton-#{Rails.env}.s3-us-west-2.amazonaws.com/sitemaps/sitemap.xml.gz"),
  )

  get '/blog', to: 'application#home'
  get '/blog/*path', to: 'application#home', as: :post
  get '/feed', to: 'application#feed', as: :feed
  get '/gear', to: 'application#home'
  get '/resume', to: 'application#home'

  root to: 'application#home'
end
