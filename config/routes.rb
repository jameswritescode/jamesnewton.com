# frozen_string_literal: true

Rails.application.routes.draw do
  mount GraphiQL::Rails::Engine, at: '/graphiql', graphql_path: '/graphql' if Rails.env.development?

  # NOTE: Support for redirecting legacy blog.jamesnewton.com
  constraints subdomain: 'blog' do
    get '/', to: redirect('https://jamesnewton.com', status: 302)
    get '/:any', to: redirect('https://jamesnewton.com/blog/%{any}')
  end

  post '/graphql', to: 'graphql#execute'

  get '/blog', to: redirect('/')
  get '/blog/*path', to: 'application#home', as: :posts

  # TODO: move / redesign resume
  get '/resume', to: redirect('/', status: 302)

  root to: 'application#home'
end
