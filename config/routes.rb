# frozen_string_literal: true

Rails.application.routes.draw do
  mount GraphiQL::Rails::Engine, at: '/graphiql', graphql_path: '/graphql' if Rails.env.development?

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

  get '/blog', to: 'application#home'
  get '/blog/*path', to: 'application#home', as: :posts
  get '/gear', to: 'application#home'
  get '/resume', to: 'application#home'

  root to: 'application#home'
end
