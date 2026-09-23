Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :exams, only: %i[index new create show destroy] do
    member do
      patch :pause
      patch :resume
      patch :complete
    end

    # Addressed by position, the number the student sees ("Pregunta 3 de 10").
    resources :questions, only: :show, controller: "exam_questions", param: :position do
      resource :answer, only: %i[create update]
    end
  end

  # Billing and the launch surface. Paid access is a prepaid window granted by the
  # provider's webhook; returning from checkout grants nothing by itself.
  resource :pricing, only: :show, controller: "pricing"
  resources :checkouts, only: :create
  resource :account, only: :show
  post "webhooks/stripe" => "stripe_webhooks#create", as: :stripe_webhook
  get "legal/:page" => "legal#show", as: :legal, constraints: { page: /terms|privacy|refunds/ }

  # Reviewer-only. Generated cases are drafts until a doctor has read them.
  namespace :review do
    resources :clinical_cases, only: %i[index show]
  end

  # The student's own average, streak and coverage of the bank.
  resource :stats, only: :show

  root "home#show"
end
