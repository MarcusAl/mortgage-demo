Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :mortgage_applications, only: [ :create, :index, :show ] do
        resource :assessment, only: [ :create, :show ]
      end
    end
  end
end
