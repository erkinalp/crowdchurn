# Add to config/routes.rb

# Surveys
resources :surveys, only: [:index, :show] do
  member do
    get :results
  end
  resources :survey_responses, only: [:create, :show, :update]
end

# Nest surveys under products and posts
resources :links, only: [] do
  resources :surveys, only: [:new, :create, :edit, :update, :destroy]
end

resources :installments, only: [] do
  resources :surveys, only: [:new, :create, :edit, :update, :destroy]
end

# Message Templates
resources :message_templates, only: [:index, :show] do
  member do
    get :analytics
  end
end

resources :links, only: [] do
  resources :message_templates, only: [:new, :create, :edit, :update, :destroy]
end

resources :installments, only: [] do
  resources :message_templates, only: [:new, :create, :edit, :update, :destroy]
end

# Automated Messages (Inbox)
resources :automated_messages, only: [:index, :show] do
  member do
    post :reply
  end
end
