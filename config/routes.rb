# frozen_string_literal: true

Rails.application.routes.draw do
  mount GraphiQL::Rails::Engine, at: '/graphiql', graphql_path: '/graphql' if Rails.env.development?

  post '/graphql', to: 'graphql#execute'

  get '/blog', to: 'application#blog'
  get '/blog/*path', to: 'application#blog', as: :posts

  # TODO
  # get '/resume', to: 'application#resume'

  root to: 'application#home'
end
