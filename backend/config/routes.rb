Rails.application.routes.draw do
  resource :customer, only: :show

  resources :pickups, only: %i[index show create] do
    member do
      post :cancel
      post :collect
      get :certificate
    end
    resources :devices, only: :create
  end

  resources :devices, only: [] do
    member do
      post :receive
      post :mark_not_received
      post :sanitize
      post :dispose
    end
  end

  post "demo/reset" => "demo#reset", as: :demo_reset

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
