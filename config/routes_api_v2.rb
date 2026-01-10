# Add to config/routes.rb

namespace :api do
  namespace :v2 do
    # Surveys API
    resources :surveys, only: [:index, :show, :create, :update, :destroy] do
      member do
        get :analytics
        get :responses
      end

      resources :responses, controller: 'survey_responses', only: [:create, :show, :update]
    end

    # Message Templates API
    resources :message_templates, only: [:index, :show, :create, :update, :destroy] do
      member do
        get :analytics
        post :preview
      end
    end

    # Automated Messages API
    resources :automated_messages, only: [:index, :show] do
      member do
        post :reply
      end

      collection do
        post :send_message
      end
    end
  end
end
