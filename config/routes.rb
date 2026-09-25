Rails.application.routes.draw do
  legal_pages = /terms|privacy|refunds/

  # The marketing host serves the signed-out landing page, the prices and the legal pages,
  # and sends every other path to the app host. Assets, icons, robots.txt and the sitemap
  # are files in public/ and never reach the router. A signed-in visitor reads the landing
  # and legal pages here and is sent on to the prices by LandingHost.
  constraints Constraints::LandingHostConstraint.new do
    get "/" => "home#show"
    get "pricing" => "pricing#show"
    get "legal/:page" => "legal#show", constraints: { page: legal_pages }
    match "*path" => AppHostRedirect, via: :all, format: false
  end

  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token
  # Sign-up sends a link; until it is followed the account sees only the waiting page.
  resource :email_verification, only: %i[show create]
  get "email_verification/:token" => "email_verifications#confirm", as: :verify_email

  # OmniAuth's middleware answers POST /auth/:provider itself and hands the callback on
  # with the provider's answer in request.env["omniauth.auth"].
  get "auth/:provider/callback" => "omniauth_callbacks#create", as: :omniauth_callback,
    constraints: { provider: /google_oauth2/ }
  get "auth/failure" => "omniauth_callbacks#failure", as: :omniauth_failure
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The web app manifest makes the site installable ("Agregar a pantalla de inicio"), which
  # is also what lets iPhone receive Web Push at all. The service worker is only there for
  # push: it caches nothing.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :exams, only: %i[index new create show destroy] do
    member do
      patch :pause
      patch :resume
      patch :complete
    end

    # Addressed by position, the number the student sees ("Pregunta 3 de 10").
    resources :questions, only: :show, controller: "exam_questions", param: :position do
      resource :answer, only: %i[create update]
      resource :report, only: :create, controller: "question_reports"
    end
  end

  # Billing and the launch surface. Paid access is a prepaid window granted by the
  # provider's webhook; returning from checkout grants nothing by itself.
  resource :pricing, only: :show, controller: "pricing"
  resources :checkouts, only: :create
  resource :account, only: %i[show update] do
    resource :name, only: :update, controller: "account_names"
    resource :reminders, only: :update, controller: "reminder_preferences"
  end

  # Study reminders. A browser's push subscription is addressed by its endpoint, which is
  # all the page knows about it; the unsubscribe link in each reminder email works signed
  # out, and its POST is the one-click unsubscribe mail clients send (RFC 8058).
  resource :push_subscription, only: %i[create destroy]
  get "reminders/unsubscribe/:token" => "reminder_unsubscribes#show", as: :reminder_unsubscribe
  post "reminders/unsubscribe/:token" => "reminder_unsubscribes#create"
  post "webhooks/stripe" => "stripe_webhooks#create", as: :stripe_webhook
  get "legal/:page" => "legal#show", as: :legal, constraints: { page: legal_pages }

  # Reviewer-only. Generated cases are drafts until a doctor has read them.
  namespace :review do
    resources :clinical_cases, only: %i[index show]
  end

  # The student's own average, streak and coverage of the bank.
  resource :stats, only: :show

  # Staff only, authorised in Admin::BaseController: reviewers see the queue and the
  # reports, admins everything.
  namespace :admin do
    root "dashboard#show"
    resources :clinical_cases, only: %i[index update] do
      resource :setting, only: :update, controller: "clinical_case_settings"
    end
    resources :question_reports, only: %i[index update]
    resource :costs, only: :show
    resource :ingestion, only: :show, controller: "ingestion"
    resources :users, only: %i[index show update] do
      resource :email_verification, only: :create, controller: "user_email_verifications"
    end
  end

  # The study calendar: one plan per student, its days addressed by date.
  resource :study_plan do
    post :catch_up
    resources :days, only: :show, controller: "study_plan_days", param: :date do
      member do
        post :quiz
        patch :complete
      end
    end
  end

  # Spaced repetition: the missed cases due again today, and pearls — guideline
  # statements as flashcards — on the same schedule.
  resources :reviews, only: :index
  resource :pearls, only: :show do
    post :review
  end

  root "home#show"

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
end
