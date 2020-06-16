# frozen_string_literal: true

Rails.application.routes.draw do
  mount GraphiQL::Rails::Engine, at: '/graphiql', graphql_path: '/graphql' if Rails.env.development?

  constraints subdomain: 'blog' do
    get '/', to: redirect('https://jamesnewton.com'), status: 302
    get '/:any', to: redirect('https://jamesnewton.com/blog/%{any}')
  end

  post '/graphql', to: 'graphql#execute'

  # get '/blog', to: 'application#home'
  get '/blog' => redirect('/')
  get '/blog/*path', to: 'application#home', as: :posts

  # TODO
  # get '/resume', to: 'application#resume'

  root to: 'application#home'
end
