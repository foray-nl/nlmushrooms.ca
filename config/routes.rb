# frozen_string_literal: true

Rails.application.routes.draw do
  # Host routes come first: the engine is mounted at '/' and its catch-all page route
  # would otherwise answer these paths.
  get 'healthcheck', to: 'healthcheck#index'
  get 'up', to: 'rails/health#show', as: :rails_health_check

  mount BetterTogether::Engine => '/'
end
